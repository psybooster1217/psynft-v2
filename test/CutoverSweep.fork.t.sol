// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Test.sol";
import {PsyNFTV2} from "../src/PsyNFTV2.sol";

interface IPsyNFTV1 {
    function tokenId() external view returns (uint256);
    function ownerOf(uint256) external view returns (address);
    function totalTokensBurnt() external view returns (uint256);
    function previousFibonacci() external view returns (uint256);
    function controlledTransfers() external view returns (bool);
}

interface IV1Treasury {
    function rageQuitBalance() external view returns (uint256);
    function pendingBalances() external view returns (uint256);
    function userBalances(address) external view returns (uint256);
    function core() external view returns (address);
    function owner() external view returns (address);
    function exit(uint256 tokenId, uint256 numberOfTokensSold, address user) external;
    function setCoreContract(address) external;
    function updatePsyNftContract(address) external;
    function withdrawUserFunds() external;
}

interface ISafe {
    function setFallbackHandler(address handler) external;
}

interface IV1CoreLogic {
    function owner() external view returns (address);
    function rageQuitAllowed() external view returns (bool);
    function switchRageQuit() external;
    function rageQuit(uint256 tokenId) external;
    function transferOwnership(address) external;
    function acceptOwnership() external;
}

/**
 * @notice Cutover + exit-pool wind-down, replayed against LIVE mainnet state.
 *
 * Sequence under test (see docs/DEPLOYMENT_RUNBOOK.md §4d):
 *   0. CoreLogic ownership: 0x00c1…6061 -> Main Safe (Ownable2Step). The Main Safe also sets the
 *      standard fallback handler: it has none today, so it cannot receive an ERC-721 via safeTransfer.
 *   1. Freeze: Safe calls CoreLogic.switchRageQuit() (V1 ego death off; withdrawals still work).
 *   2. Deploy V2 (core = Safe, treasury = V1 Treasury), migrate the live holder set, hand off to Safe.
 *   3. One Safe multisend: repoint the V1 Treasury to V2, make the Safe its core, mint batch 7,
 *      exit one Safe-held seat with n = burnt + 1 (full pool), withdraw, set V2.treasury = Safe.
 *
 * Proves: the Safe receives exactly the pool, the pool reads 0, balances owed to past exiters are
 * untouched, V1 ego death cannot pay out anything afterwards, and every holder keeps their V2 seat.
 *
 * Requires MAINNET_RPC_URL (skipped otherwise). Optional FORK_BLOCK pin.
 *   MAINNET_RPC_URL=... forge test --match-path test/CutoverSweep.fork.t.sol -vv
 */
contract CutoverSweepForkTest is Test {
    address internal constant V1_NFT = 0x6c6Ab7b3215374dE4A65De63eAC9BC7A0c7f402d;
    address internal constant V1_TREASURY = 0xB4528213285CD10Fdb6a14847a398d71670b3d61;
    address internal constant V1_CORE = 0xDAAAC6a81fE6a230B880b96a2B5ca903d0c1d4F6;
    address internal constant MAIN_SAFE = 0xB253a1Ab24B612C2AF37f8fC935b40c7304650e5;
    /// Canonical Safe v1.3.0 CompatibilityFallbackHandler (implements onERC721Received).
    address internal constant SAFE_FALLBACK_HANDLER = 0xf48f2B2d2a534e402487b3ee7C18c33Aec0Fe5e4;
    /// keccak256("fallback_manager.handler.address")
    bytes32 internal constant FALLBACK_HANDLER_SLOT = 0x6c9a6c4a39284e37ed1cf53d337577d14212a4870fb976a4366c693b939918d5;

    IPsyNFTV1 internal v1;
    IV1Treasury internal treasury;
    IV1CoreLogic internal core;
    PsyNFTV2 internal v2;
    bool internal enabled;

    uint256[] internal liveIds;
    address[] internal liveHolders;

    function setUp() public {
        string memory url = vm.envOr("MAINNET_RPC_URL", string(""));
        if (bytes(url).length == 0) {
            enabled = false;
            return;
        }
        uint256 pin = vm.envOr("FORK_BLOCK", uint256(0));
        if (pin == 0) vm.createSelectFork(url);
        else vm.createSelectFork(url, pin);
        enabled = true;

        v1 = IPsyNFTV1(V1_NFT);
        treasury = IV1Treasury(V1_TREASURY);
        core = IV1CoreLogic(V1_CORE);

        // Preconditions this sequence depends on. If any fails, the plan needs revisiting.
        assertEq(treasury.owner(), MAIN_SAFE, "V1 Treasury owner is the Main Safe");
        assertEq(treasury.core(), V1_CORE, "V1 Treasury core is V1 CoreLogic");
    }

    // ------------------------------------------------------------------ //
    //                               Tests                                //
    // ------------------------------------------------------------------ //

    /// Full sequence with no exits during the window: the Safe sweeps the whole pool.
    /// Documents the blocker found on the first run: without a fallback handler the Safe can't receive a seat.
    function test_SafeWithoutHandlerCannotReceiveSeat() public {
        if (!_enabled()) return;
        assertEq(vm.load(MAIN_SAFE, FALLBACK_HANDLER_SLOT), bytes32(0), "Main Safe has no fallback handler today");
        v2 = new PsyNFTV2(address(this));
        v2.setCoreContract(address(this));
        _snapshotV1();
        // minimal migration so batch minting is allowed
        v2.migrateBatch(liveHolders, liveIds);
        v2.finalizeMigration(v1.tokenId(), v1.previousFibonacci(), true, v1.tokenId() - v1.totalTokensBurnt());
        v2.batchMintInFibonacci();
        uint256[] memory one = new uint256[](1);
        one[0] = 34;
        vm.expectRevert();
        v2.transferNFTs(one, MAIN_SAFE);
    }

    function test_CutoverAndSweep() public {
        if (!_enabled()) return;

        _transferCoreToSafe();
        _freeze();

        uint256 pool = treasury.rageQuitBalance();
        uint256 owed = treasury.pendingBalances();
        uint256 safeBefore = MAIN_SAFE.balance;
        assertGt(pool, 0, "pool non-empty before sweep");

        _deployMigrateHandoff();
        uint256 sweepId = _cutoverAndSweep();

        _assertSweep(pool, owed, safeBefore, sweepId);
    }

    /// A legacy holder takes their share during the exit window; the sweep takes only what is left.
    function test_ExitWindowThenSweep() public {
        if (!_enabled()) return;

        _transferCoreToSafe();

        // Pick the first live V1 seat and exit it on V1 while ego death is still ON.
        (uint256 exitId, address exiter) = _firstLiveSeat();
        uint256 poolBefore = treasury.rageQuitBalance();
        uint256 soldV1 = _v1NumberSold();
        uint256 expectedShare = poolBefore / (soldV1 - v1.totalTokensBurnt());

        vm.prank(exiter);
        core.rageQuit(exitId);
        assertEq(treasury.userBalances(exiter), expectedShare, "fair share credited");

        uint256 exiterBalBefore = exiter.balance;
        vm.prank(exiter);
        treasury.withdrawUserFunds();
        assertEq(exiter.balance, exiterBalBefore + expectedShare, "exiter paid");

        _freeze();

        uint256 pool = treasury.rageQuitBalance();
        uint256 owed = treasury.pendingBalances();
        uint256 safeBefore = MAIN_SAFE.balance;
        assertEq(pool, poolBefore - expectedShare, "pool reduced by the share");

        _deployMigrateHandoff();
        assertEq(liveIds.length, 32, "exited seat is not migrated");
        vm.expectRevert();
        v2.ownerOf(exitId);

        uint256 sweepId = _cutoverAndSweep();
        _assertSweep(pool, owed, safeBefore, sweepId);
    }

    // ------------------------------------------------------------------ //
    //                               Steps                                //
    // ------------------------------------------------------------------ //

    /// Step 0: CoreLogic ownership from the current owner wallet to the Main Safe,
    /// plus the Safe fallback handler so the Safe can hold a V2 seat (transferNFTs uses _safeTransfer).
    function _transferCoreToSafe() internal {
        if (vm.load(MAIN_SAFE, FALLBACK_HANDLER_SLOT) == bytes32(0)) {
            vm.prank(MAIN_SAFE);
            ISafe(MAIN_SAFE).setFallbackHandler(SAFE_FALLBACK_HANDLER);
        }
        assertEq(
            address(uint160(uint256(vm.load(MAIN_SAFE, FALLBACK_HANDLER_SLOT)))), SAFE_FALLBACK_HANDLER, "handler set"
        );

        address currentOwner = core.owner();
        vm.prank(currentOwner);
        core.transferOwnership(MAIN_SAFE);
        vm.prank(MAIN_SAFE);
        core.acceptOwnership();
        assertEq(core.owner(), MAIN_SAFE, "CoreLogic owned by Safe");
    }

    /// Step 1: freeze V1 ego death (not Treasury.pause, so past exiters can still withdraw).
    function _freeze() internal {
        if (core.rageQuitAllowed()) {
            vm.prank(MAIN_SAFE);
            core.switchRageQuit();
        }
        assertFalse(core.rageQuitAllowed(), "V1 ego death off");
    }

    /// Step 2: Deploy.s.sol (NEW_CORE = Safe, NEW_TREASURY = V1 Treasury) + Migrate.s.sol + Handoff.s.sol.
    function _deployMigrateHandoff() internal {
        v2 = new PsyNFTV2(address(this)); // test = temporary deployer/owner
        v2.setCoreContract(MAIN_SAFE);
        v2.setTreasury(V1_TREASURY);

        _snapshotV1();
        uint256 n = liveIds.length;
        uint256 CHUNK = 50;
        for (uint256 start; start < n; start += CHUNK) {
            uint256 end = start + CHUNK > n ? n : start + CHUNK;
            address[] memory hb = new address[](end - start);
            uint256[] memory ib = new uint256[](end - start);
            for (uint256 i; i < end - start; i++) {
                hb[i] = liveHolders[start + i];
                ib[i] = liveIds[start + i];
            }
            v2.migrateBatch(hb, ib);
        }
        v2.finalizeMigration(v1.tokenId(), v1.previousFibonacci(), v1.controlledTransfers(), v1.tokenId() - v1.totalTokensBurnt());

        v2.transferOwnership(MAIN_SAFE);
        vm.prank(MAIN_SAFE);
        v2.acceptOwnership();
        assertEq(v2.owner(), MAIN_SAFE, "V2 owned by Safe");
    }

    /// Step 3: the single cutover + sweep multisend, executed by the Main Safe.
    function _cutoverAndSweep() internal returns (uint256 sweepId) {
        sweepId = v2.tokenId(); // first id of batch 7 (34 today)

        vm.startPrank(MAIN_SAFE);
        treasury.updatePsyNftContract(address(v2));
        treasury.setCoreContract(MAIN_SAFE);
        v2.batchMintInFibonacci();
        uint256[] memory one = new uint256[](1);
        one[0] = sweepId;
        v2.transferNFTs(one, MAIN_SAFE);
        // payout = rageQuitBalance / (n - v2.totalTokensBurnt()) ; n - burnt == 1 -> whole pool
        treasury.exit(sweepId, v2.totalTokensBurnt() + 1, MAIN_SAFE);
        treasury.withdrawUserFunds();
        v2.setTreasury(MAIN_SAFE); // Safe burns directly from now on (removals, lapses)
        vm.stopPrank();
    }

    // ------------------------------------------------------------------ //
    //                              Checks                                //
    // ------------------------------------------------------------------ //

    function _assertSweep(uint256 pool, uint256 owed, uint256 safeBefore, uint256 sweepId) internal {
        // Money
        assertEq(MAIN_SAFE.balance, safeBefore + pool, "Safe received exactly the pool");
        assertEq(treasury.rageQuitBalance(), 0, "pool empty");
        assertEq(treasury.pendingBalances(), owed, "amounts owed to past exiters untouched");
        assertEq(V1_TREASURY.balance, owed, "Treasury now holds only what it owes");
        emit log_named_decimal_uint("swept to Main Safe (ETH)", pool, 18);
        emit log_named_decimal_uint("left for past exiters (ETH)", owed, 18);

        // V2 state
        vm.expectRevert();
        v2.ownerOf(sweepId); // the sweep seat is burned
        assertEq(v2.totalTokensBurnt(), 1, "only the sweep seat burned on V2");
        assertEq(v2.treasury(), MAIN_SAFE, "V2 treasury back to Safe");
        assertEq(v2.core(), MAIN_SAFE, "V2 core is Safe");
        for (uint256 i; i < liveIds.length; i++) {
            assertEq(v2.ownerOf(liveIds[i]), liveHolders[i], "every holder keeps their V2 seat");
        }
        for (uint256 id = sweepId + 1; id < v2.tokenId(); id++) {
            assertEq(v2.ownerOf(id), address(v2), "rest of batch 7 held by the contract");
        }

        // No double claim: V1 ego death reverts while off ...
        vm.prank(liveHolders[0]);
        vm.expectRevert(bytes("CoreLogic: Rage Quit Disabled"));
        core.rageQuit(liveIds[0]);

        // ... and even if someone switched it back on, the Treasury no longer trusts V1 CoreLogic.
        vm.prank(MAIN_SAFE);
        core.switchRageQuit();
        vm.prank(liveHolders[0]);
        vm.expectRevert(bytes("Treasury: Only callable by CoreLogic.sol"));
        core.rageQuit(liveIds[0]);

        // The Safe can still remove a seat directly (governed burn, no payout).
        vm.prank(MAIN_SAFE);
        v2.burn(sweepId + 1);
        assertEq(v2.totalTokensBurnt(), 2, "Safe burn works");
    }

    // ------------------------------------------------------------------ //
    //                              Helpers                               //
    // ------------------------------------------------------------------ //

    function _enabled() internal returns (bool) {
        if (!enabled) {
            emit log("SKIP: set MAINNET_RPC_URL to run the cutover/sweep fork test");
            vm.skip(true);
        }
        return enabled;
    }

    function _snapshotV1() internal {
        delete liveIds;
        delete liveHolders;
        uint256 counter = v1.tokenId();
        for (uint256 id; id < counter; id++) {
            try v1.ownerOf(id) returns (address o) {
                liveIds.push(id);
                liveHolders.push(o == V1_NFT ? address(v2) : o);
            } catch {}
        }
        assertEq(liveIds.length, counter - v1.totalTokensBurnt(), "snapshot complete");
    }

    function _firstLiveSeat() internal view returns (uint256 id, address holder) {
        uint256 counter = v1.tokenId();
        for (id = 0; id < counter; id++) {
            try v1.ownerOf(id) returns (address o) {
                if (o != V1_NFT && o.code.length == 0) return (id, o);
            } catch {}
        }
        revert("no live EOA-held seat");
    }

    function _v1NumberSold() internal view returns (uint256) {
        // PsycSale proxy (lost-key owner): numberOfNftsSold is what V1 CoreLogic passes to Treasury.exit.
        (bool ok, bytes memory data) =
            address(0xe94828A923538709c58764159D6CD99C4381d82B).staticcall(abi.encodeWithSignature("numberOfNftsSold()"));
        require(ok, "numberOfNftsSold");
        return abi.decode(data, (uint256));
    }
}
