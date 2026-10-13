// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Test.sol";
import {PsyNFTV2} from "../src/PsyNFTV2.sol";
import {CutoverCalls} from "../script/lib/CutoverCalls.sol";

interface IGnosisSafe {
    function getOwners() external view returns (address[] memory);
    function getThreshold() external view returns (uint256);
    function nonce() external view returns (uint256);
    function approveHash(bytes32 hashToApprove) external;
    function getTransactionHash(
        address to,
        uint256 value,
        bytes calldata data,
        uint8 operation,
        uint256 safeTxGas,
        uint256 baseGas,
        uint256 gasPrice,
        address gasToken,
        address refundReceiver,
        uint256 _nonce
    ) external view returns (bytes32);
    function execTransaction(
        address to,
        uint256 value,
        bytes calldata data,
        uint8 operation,
        uint256 safeTxGas,
        uint256 baseGas,
        uint256 gasPrice,
        address gasToken,
        address payable refundReceiver,
        bytes memory signatures
    ) external payable returns (bool);
}

interface IV1NFT {
    function tokenId() external view returns (uint256);
    function ownerOf(uint256) external view returns (address);
    function totalTokensBurnt() external view returns (uint256);
    function previousFibonacci() external view returns (uint256);
    function controlledTransfers() external view returns (bool);
}

interface IV1Treasury {
    function rageQuitBalance() external view returns (uint256);
    function pendingBalances() external view returns (uint256);
    function core() external view returns (address);
    function owner() external view returns (address);
    function psyNFT() external view returns (address);
}

interface IV1Core {
    function owner() external view returns (address);
    function rageQuitAllowed() external view returns (bool);
    function rageQuit(uint256) external;
    function psyNFT() external view returns (address);
}

/**
 * @notice The whole cutover executed through the REAL Main Safe on a mainnet fork (audit 2026-10, W4).
 *
 *  - Real Safe v1.3.0 contract, its real 4 owners and real threshold (2). Owners sign with Safe's
 *    on-chain "approved hash" mechanism (owner calls approveHash; signature type v=1), which runs
 *    the same checkNSignatures path as ECDSA signatures; a third party relays execTransaction.
 *  - Batches go through the canonical MultiSendCallOnly via DELEGATECALL, as the Transaction
 *    Builder does, using the exact calldata from script/lib/CutoverCalls.sol (the same bytes the
 *    signers will import). The off-chain safeTxHash computation is checked against the Safe's own.
 *
 *    MAINNET_RPC_URL=https://eth.drpc.org forge test --match-path test/SafeRehearsal.fork.t.sol -vv
 */
contract SafeRehearsalForkTest is Test {
    address internal constant V1_NFT = 0x6c6Ab7b3215374dE4A65De63eAC9BC7A0c7f402d;
    address internal constant PSYC_SALE = 0xe94828A923538709c58764159D6CD99C4381d82B;
    bytes32 internal constant FALLBACK_HANDLER_SLOT = 0x6c9a6c4a39284e37ed1cf53d337577d14212a4870fb976a4366c693b939918d5;

    IGnosisSafe internal safe = IGnosisSafe(CutoverCalls.MAIN_SAFE);
    IV1NFT internal v1 = IV1NFT(V1_NFT);
    IV1Treasury internal treasury = IV1Treasury(CutoverCalls.V1_TREASURY);
    IV1Core internal core = IV1Core(CutoverCalls.V1_CORE);
    PsyNFTV2 internal v2;
    address internal relayer = makeAddr("relayer");
    address internal deployer = makeAddr("deployer");
    bool internal enabled;

    uint256[] internal liveIds;
    address[] internal liveHolders;

    function setUp() public {
        string memory url = vm.envOr("MAINNET_RPC_URL", string(""));
        if (bytes(url).length == 0) return;
        uint256 pin = vm.envOr("FORK_BLOCK", uint256(0));
        if (pin == 0) vm.createSelectFork(url);
        else vm.createSelectFork(url, pin);
        enabled = true;
    }

    function _skipIfNoFork() internal returns (bool) {
        if (!enabled) {
            emit log("SKIP: set MAINNET_RPC_URL to run the real-Safe rehearsal");
            vm.skip(true);
        }
        return !enabled;
    }

    // ------------------------------------------------------------------ //
    //                                tests                               //
    // ------------------------------------------------------------------ //

    function test_FullCutoverThroughRealSafe() public {
        if (_skipIfNoFork()) return;
        _preconditions();

        // §0b — EOA hands CoreLogic to the Safe; the Safe accepts and installs the fallback handler.
        _coreLogicHandover();
        _execSafe(CutoverCalls.setupBatch(), "0b setup");
        assertEq(core.owner(), CutoverCalls.MAIN_SAFE, "CoreLogic owned by Safe");
        assertEq(
            address(uint160(uint256(vm.load(CutoverCalls.MAIN_SAFE, FALLBACK_HANDLER_SLOT)))),
            CutoverCalls.SAFE_FALLBACK_HANDLER,
            "fallback handler installed"
        );

        // §1 — close the exit window.
        _execSafe(CutoverCalls.freezeBatch(), "1 freeze");
        assertFalse(core.rageQuitAllowed(), "V1 ego death off");

        // §4a/4b — deploy + migrate + start handoff (deployer EOA), §4c — Safe accepts.
        _deployAndMigrate();
        _execSafe(CutoverCalls.acceptV2Batch(address(v2)), "4c accept V2");
        assertEq(v2.owner(), CutoverCalls.MAIN_SAFE);
        assertEq(v2.pendingOwner(), address(0));

        // §4d — the cutover + sweep batch.
        uint256 pool = treasury.rageQuitBalance();
        uint256 owed = treasury.pendingBalances();
        uint256 safeBefore = CutoverCalls.MAIN_SAFE.balance;
        uint256 v1Counter = v1.tokenId();
        assertGt(pool, 0, "pool non-empty");
        _execSafe(CutoverCalls.cutoverBatch(address(v2), 34), "4d cutover+sweep");

        // Money: exactly the pool, nothing owed to past exiters touched.
        assertEq(CutoverCalls.MAIN_SAFE.balance, safeBefore + pool, "Safe received exactly the pool");
        assertEq(treasury.rageQuitBalance(), 0, "pool empty");
        assertEq(treasury.pendingBalances(), owed, "past exiters still owed the same");
        assertEq(CutoverCalls.V1_TREASURY.balance, owed, "Treasury holds only what it owes");
        emit log_named_decimal_uint("swept to Main Safe through real multisig (ETH)", pool, 18);

        // V2 state.
        vm.expectRevert();
        v2.ownerOf(34);
        assertEq(v2.totalTokensBurnt(), 1);
        assertEq(v2.tokenId(), 55, "batch 7 minted");
        assertEq(v2.treasury(), CutoverCalls.MAIN_SAFE);
        assertEq(v2.core(), CutoverCalls.MAIN_SAFE);
        for (uint256 i; i < liveIds.length; i++) {
            assertEq(v2.ownerOf(liveIds[i]), liveHolders[i], "every holder keeps their seat");
        }
        for (uint256 id = 35; id < 55; id++) {
            assertEq(v2.ownerOf(id), address(v2), "20 seats held for allocation");
        }

        // OPS-02: V1 can no longer be minted, kicked or rage-quit through CoreLogic.
        assertEq(core.psyNFT(), address(v2), "CoreLogic now points at V2");
        CutoverCalls.Call[] memory mint = new CutoverCalls.Call[](1);
        mint[0] = CutoverCalls.Call(CutoverCalls.V1_CORE, abi.encodeWithSignature("mintNextBatch()"), "CoreLogic.mintNextBatch()");
        _execSafeExpectRevert(mint);
        assertEq(v1.tokenId(), v1Counter, "no new V1 seats");
        CutoverCalls.Call[] memory kick = new CutoverCalls.Call[](1);
        kick[0] = CutoverCalls.Call(
            CutoverCalls.V1_CORE, abi.encodeWithSignature("kick(uint256,address)", liveIds[0], liveHolders[0]), "kick"
        );
        _execSafeExpectRevert(kick);
        vm.prank(liveHolders[0]);
        vm.expectRevert(bytes("CoreLogic: Rage Quit Disabled"));
        core.rageQuit(liveIds[0]);

        // Day-2 operations through the real Safe.
        _day2Operations();
    }

    /// If the fallback handler is missing, the whole §4d batch reverts and NOTHING changes.
    function test_SweepBatchIsAtomic() public {
        if (_skipIfNoFork()) return;
        _coreLogicHandover();
        CutoverCalls.Call[] memory acceptOnly = new CutoverCalls.Call[](1);
        acceptOnly[0] = CutoverCalls.setupBatch()[0]; // accept CoreLogic, but NO fallback handler
        _execSafe(acceptOnly, "0b without handler");
        _execSafe(CutoverCalls.freezeBatch(), "1 freeze");
        _deployAndMigrate();
        _execSafe(CutoverCalls.acceptV2Batch(address(v2)), "4c");

        uint256 pool = treasury.rageQuitBalance();
        uint256 safeBefore = CutoverCalls.MAIN_SAFE.balance;
        _execSafeExpectRevert(CutoverCalls.cutoverBatch(address(v2), 34));

        assertEq(treasury.rageQuitBalance(), pool, "pool untouched");
        assertEq(treasury.core(), CutoverCalls.V1_CORE, "Treasury core unchanged (step 2 rolled back)");
        assertEq(treasury.psyNFT(), V1_NFT, "Treasury NFT unchanged (step 1 rolled back)");
        assertEq(v2.tokenId(), 34, "no batch minted");
        assertEq(CutoverCalls.MAIN_SAFE.balance, safeBefore);
    }

    /// `switchRageQuit` is a toggle: signing the freeze batch twice re-opens ego death.
    function test_FreezeBatchIsAToggle() public {
        if (_skipIfNoFork()) return;
        _coreLogicHandover();
        _execSafe(CutoverCalls.setupBatch(), "0b");
        bool before = core.rageQuitAllowed();
        _execSafe(CutoverCalls.freezeBatch(), "freeze #1");
        _execSafe(CutoverCalls.freezeBatch(), "freeze #2");
        assertEq(core.rageQuitAllowed(), before, "two executions cancel out: check state before signing");
    }

    /// The safeTxHash the script prints for signers equals what the Safe itself computes.
    function test_OffchainSafeTxHashMatches() public {
        if (_skipIfNoFork()) return;
        address fakeV2 = address(0x1234);
        CutoverCalls.Call[][4] memory batches = [
            CutoverCalls.setupBatch(),
            CutoverCalls.freezeBatch(),
            CutoverCalls.acceptV2Batch(fakeV2),
            CutoverCalls.cutoverBatch(fakeV2, 34)
        ];
        uint256 n = safe.nonce();
        for (uint256 i; i < batches.length; i++) {
            _checkHash(batches[i], n + i);
        }
    }

    function _checkHash(CutoverCalls.Call[] memory c, uint256 n) internal view {
        (address to, bytes memory data, uint8 op) = CutoverCalls.safeTxFor(c);
        bytes32 onchain = safe.getTransactionHash(to, 0, data, op, 0, 0, 0, address(0), address(0), n);
        assertEq(CutoverCalls.safeTxHash(CutoverCalls.MAIN_SAFE, block.chainid, to, data, op, n), onchain);
    }

    // ------------------------------------------------------------------ //
    //                                steps                               //
    // ------------------------------------------------------------------ //

    function _preconditions() internal view {
        assertEq(safe.getThreshold(), 2, "Main Safe threshold");
        assertEq(safe.getOwners().length, 4, "Main Safe owners");
        assertEq(treasury.owner(), CutoverCalls.MAIN_SAFE, "V1 Treasury owned by Safe");
        assertEq(treasury.core(), CutoverCalls.V1_CORE);
        assertTrue(core.rageQuitAllowed(), "exit window open (as of the audit)");
    }

    function _coreLogicHandover() internal {
        address current = core.owner();
        if (current == CutoverCalls.MAIN_SAFE) return;
        assertEq(current, CutoverCalls.V1_CORE_OWNER, "CoreLogic still on the documented EOA");
        vm.prank(current);
        (bool ok,) = CutoverCalls.V1_CORE.call(CutoverCalls.coreLogicHandoverCalldata());
        assertTrue(ok, "EOA transferOwnership");
    }

    function _deployAndMigrate() internal {
        vm.startPrank(deployer);
        v2 = new PsyNFTV2(deployer);
        v2.setBaseUri("ipfs://bafyREPINNEDMETADATA/");
        v2.setTreasury(CutoverCalls.V1_TREASURY);
        v2.setCoreContract(CutoverCalls.MAIN_SAFE);
        vm.stopPrank();

        delete liveIds;
        delete liveHolders;
        uint256 counter = v1.tokenId();
        for (uint256 id; id < counter; id++) {
            try v1.ownerOf(id) returns (address o) {
                liveIds.push(id);
                liveHolders.push(o == V1_NFT ? address(v2) : o);
            } catch {}
        }
        vm.startPrank(deployer);
        v2.migrateBatch(liveHolders, liveIds);
        v2.finalizeMigration(counter, v1.previousFibonacci(), v1.controlledTransfers(), counter - v1.totalTokensBurnt());
        v2.transferOwnership(CutoverCalls.MAIN_SAFE);
        vm.stopPrank();
        assertEq(v2.pendingOwner(), CutoverCalls.MAIN_SAFE);
    }

    function _day2Operations() internal {
        // a holder moves their seat to a new wallet: Safe approves, holder transfers
        address holder = _firstEoaHolder();
        uint256 seat = _seatOf(holder);
        address newWallet = makeAddr("holder-new-wallet");
        CutoverCalls.Call[] memory a = new CutoverCalls.Call[](1);
        a[0] = CutoverCalls.Call(
            address(v2), abi.encodeWithSignature("approveTransfer(uint256,address,uint256)", seat, newWallet, 7 days), ""
        );
        _execSafe(a, "approve wallet move");
        vm.prank(holder);
        v2.transferFrom(holder, newWallet, seat);
        assertEq(v2.ownerOf(seat), newWallet);

        // revoke a mistaken approval
        a[0] = CutoverCalls.Call(
            address(v2), abi.encodeWithSignature("approveTransfer(uint256,address,uint256)", seat, address(0xdead), 365 days), ""
        );
        _execSafe(a, "mistaken approval");
        a[0] = CutoverCalls.Call(address(v2), abi.encodeWithSignature("revokeTransfer(uint256)", seat), "");
        _execSafe(a, "revoke");
        vm.prank(newWallet);
        vm.expectRevert("PsyNFT: Incorrect Receiver");
        v2.transferFrom(newWallet, address(0xdead), seat);

        // allocate a batch-7 seat, refresh metadata, and remove a seat (governed burn) in one batch
        uint256[] memory ids = new uint256[](1);
        ids[0] = 35;
        CutoverCalls.Call[] memory b = new CutoverCalls.Call[](3);
        b[0] = CutoverCalls.Call(address(v2), abi.encodeWithSignature("transferNFTs(uint256[],address)", ids, newWallet), "");
        b[1] = CutoverCalls.Call(address(v2), abi.encodeWithSignature("setBaseUri(string)", "ipfs://bafyNEXTFOLDER/"), "");
        b[2] = CutoverCalls.Call(address(v2), abi.encodeWithSignature("burn(uint256)", 36), "");
        _execSafe(b, "allocate + metadata + burn");
        assertEq(v2.ownerOf(35), newWallet);
        assertEq(v2.tokenURI(35), "ipfs://bafyNEXTFOLDER/35");
        assertEq(v2.totalTokensBurnt(), 2);
    }

    // ------------------------------------------------------------------ //
    //                        real-Safe execution                         //
    // ------------------------------------------------------------------ //

    /// Executes a batch through the Main Safe with `threshold` real owners approving the hash.
    function _execSafe(CutoverCalls.Call[] memory c, string memory what) internal {
        (address to, bytes memory data, uint8 op, bytes memory sigs) = _signed(c);
        vm.prank(relayer);
        bool ok = safe.execTransaction(to, 0, data, op, 0, 0, 0, address(0), payable(address(0)), sigs);
        assertTrue(ok, what);
    }

    function _execSafeExpectRevert(CutoverCalls.Call[] memory c) internal {
        (address to, bytes memory data, uint8 op, bytes memory sigs) = _signed(c);
        uint256 n = safe.nonce();
        vm.prank(relayer);
        vm.expectRevert(bytes("GS013")); // inner call failed and no refund params: Safe reverts
        safe.execTransaction(to, 0, data, op, 0, 0, 0, address(0), payable(address(0)), sigs);
        assertEq(safe.nonce(), n, "failed batch does not consume the nonce");
    }

    function _signed(CutoverCalls.Call[] memory c)
        internal
        returns (address to, bytes memory data, uint8 op, bytes memory sigs)
    {
        (to, data, op) = CutoverCalls.safeTxFor(c);
        uint256 n = safe.nonce();
        bytes32 h = safe.getTransactionHash(to, 0, data, op, 0, 0, 0, address(0), address(0), n);
        assertEq(h, CutoverCalls.safeTxHash(CutoverCalls.MAIN_SAFE, block.chainid, to, data, op, n), "off-chain hash");

        address[] memory owners = _sortedOwners();
        uint256 t = safe.getThreshold();
        for (uint256 i; i < t; i++) {
            vm.prank(owners[i]);
            safe.approveHash(h);
            // approved-hash signature: r = owner, s = 0, v = 1 (sorted ascending by owner)
            sigs = abi.encodePacked(sigs, bytes32(uint256(uint160(owners[i]))), bytes32(0), uint8(1));
        }
    }

    function _sortedOwners() internal view returns (address[] memory o) {
        o = safe.getOwners();
        for (uint256 i; i < o.length; i++) {
            for (uint256 j = i + 1; j < o.length; j++) {
                if (o[j] < o[i]) (o[i], o[j]) = (o[j], o[i]);
            }
        }
    }

    function _firstEoaHolder() internal view returns (address) {
        for (uint256 i; i < liveHolders.length; i++) {
            if (liveHolders[i].code.length == 0) return liveHolders[i];
        }
        revert("no EOA holder");
    }

    function _seatOf(address h) internal view returns (uint256) {
        for (uint256 i; i < liveHolders.length; i++) {
            if (liveHolders[i] == h) return liveIds[i];
        }
        revert("no seat");
    }
}
