// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Test.sol";
import {PsyNFTV2} from "../src/PsyNFTV2.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

/**
 * @notice PoC / regression tests for the findings of the internal security audit
 *         (docs/AUDIT.md). Each test documents a property the audit relies on.
 */

/// @dev A hostile NFT recipient that, during the `onERC721Received` callback of a core
///      distribution, attempts to reenter every state-changing function. It records which
///      attempts succeed — the audit asserts none do.
contract ReentrantReceiver is IERC721Receiver {
    PsyNFTV2 public immutable nft;
    uint256 public successes;
    bool internal armed;

    constructor(PsyNFTV2 _nft) {
        nft = _nft;
    }

    function arm() external {
        armed = true;
    }

    function onERC721Received(address, address, uint256 id, bytes calldata) external returns (bytes4) {
        if (armed) {
            armed = false; // single-shot; avoid infinite recursion

            // 1. Try to mint (core-gated)
            try nft.batchMintInFibonacci() {
                successes++;
            } catch {}
            // 2. Try to distribute more tokens to ourselves (core-gated)
            uint256[] memory ids = new uint256[](1);
            ids[0] = id == 0 ? 1 : 0;
            try nft.transferNFTs(ids, address(this)) {
                successes++;
            } catch {}
            // 3. Try to grant ourselves a transfer approval (core-gated)
            try nft.approveTransfer(id, address(0xBEEF), 1 days) {
                successes++;
            } catch {}
            // 4. Try to burn (treasury-gated)
            try nft.burn(id) {
                successes++;
            } catch {}
            // 5. Try to move the just-received token (controlled-transfer gate applies:
            //    ownership has already been updated to us before this callback runs)
            try nft.transferFrom(address(this), address(0xBEEF), id) {
                successes++;
            } catch {}
            // 6. Try to open a migration (owner-gated)
            address[] memory h = new address[](1);
            uint256[] memory mids = new uint256[](1);
            h[0] = address(this);
            mids[0] = 999;
            try nft.migrateBatch(h, mids) {
                successes++;
            } catch {}
        }
        return IERC721Receiver.onERC721Received.selector;
    }
}

contract AuditTest is Test {
    PsyNFTV2 internal nft;

    address internal owner = makeAddr("owner");
    address internal core = makeAddr("core");
    address internal treasury = makeAddr("treasury");

    function setUp() public {
        nft = new PsyNFTV2(owner);
        vm.startPrank(owner);
        nft.setCoreContract(core);
        nft.setTreasury(treasury);
        vm.stopPrank();
    }

    // ------------------------------------------------------------------ //
    //  CON-1: ownership must be indestructible                           //
    // ------------------------------------------------------------------ //

    function test_RenounceOwnership_Blocked() public {
        // The owner cannot renounce into the void (the V1 failure mode).
        vm.prank(owner);
        vm.expectRevert("PsyNFT: Ownership Cannot Be Renounced");
        nft.renounceOwnership();
        assertEq(nft.owner(), owner);

        // Non-owners are rejected by the standard Ownable check.
        vm.prank(address(0xBAD));
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(0xBAD)));
        nft.renounceOwnership();
    }

    // ------------------------------------------------------------------ //
    //  CON-3: reentrancy via distribution callback is inert              //
    // ------------------------------------------------------------------ //

    function test_ReentrantReceiver_CannotEscalate() public {
        vm.prank(core);
        nft.initialMint(); // ids 0..2 held by the contract

        ReentrantReceiver attacker = new ReentrantReceiver(nft);
        attacker.arm();

        uint256[] memory ids = new uint256[](1);
        ids[0] = 0;
        vm.prank(core);
        nft.transferNFTs(ids, address(attacker)); // triggers the hostile callback

        // The distribution itself succeeded…
        assertEq(nft.ownerOf(0), address(attacker));
        // …but every reentrant escalation attempt failed.
        assertEq(attacker.successes(), 0, "reentrant call escalated privileges");
        // And no state was corrupted: supply counter and other tokens untouched.
        assertEq(nft.tokenId(), 3);
        assertEq(nft.ownerOf(1), address(nft));
        assertEq(nft.ownerOf(2), address(nft));
        assertFalse(nft.migrationStarted());
    }

    // ------------------------------------------------------------------ //
    //  CON-2: Fibonacci batch gas ceiling (inherited V1 design limit)    //
    // ------------------------------------------------------------------ //

    function test_FibonacciBatch_GasCeiling() public {
        vm.prank(core);
        nft.initialMint(); // tokenId=3, prevFib=2

        // Batches mint 2,3,5,8,13,21,34,55,89,144,233,377 over the first 12 calls;
        // the V1 mainnet state (tokenId=34, prevFib=21) sits right after batch 5.
        for (uint256 i; i < 12; i++) {
            vm.prank(core);
            nft.batchMintInFibonacci();
        }
        assertEq(nft.previousFibonacci(), 610); // next three batches mint 610, 987, 1597
        assertEq(nft.tokenId(), 987);

        uint256[3] memory batchSizes = [uint256(610), 987, 1597];
        for (uint256 i; i < 3; i++) {
            uint256 g0 = gasleft();
            vm.prank(core);
            nft.batchMintInFibonacci();
            uint256 used = g0 - gasleft();
            emit log_named_uint(string.concat("gas for batch of ", vm.toString(batchSizes[i])), used);
            // The 1597 batch (10th after the migration resume point) cannot fit a ~30M block.
            if (batchSizes[i] == 1597) {
                assertGt(used, 30_000_000, "expected the 1597 batch to exceed a 30M block");
            }
        }
        // Whichever batch first exceeds the prevailing block gas limit permanently halts the
        // schedule (the tx reverts; no state corruption; existing tokens unaffected).
        // Inherited 1:1 from V1's design — documented in docs/AUDIT.md (CON-2).
    }

    // ------------------------------------------------------------------ //
    //  Rescue cannot be abused to move PsyNFTs                           //
    // ------------------------------------------------------------------ //

    function test_Rescue_CannotMovePsyNFTs() public {
        vm.prank(core);
        nft.initialMint();

        // rescueERC721 on self is explicitly blocked.
        vm.prank(owner);
        vm.expectRevert("PsyNFT: Cannot Rescue Self");
        nft.rescueERC721(address(nft), owner, 0);

        // rescueERC20 pointed at self cannot move NFTs either: PsyNFTV2 has no
        // transfer(address,uint256) function, so the SafeERC20 call reverts.
        vm.prank(owner);
        vm.expectRevert();
        nft.rescueERC20(address(nft), owner, 1);

        assertEq(nft.ownerOf(0), address(nft)); // custody unchanged
    }
}
