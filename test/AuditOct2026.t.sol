// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Test.sol";
import {PsyNFTV2} from "../src/PsyNFTV2.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC721Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

/// @dev Rejects ETH, to exercise rescueETH's failure branch.
contract EthRejecter {
    receive() external payable {
        revert("no ETH");
    }
}

/**
 * @notice Regression tests for the October 2026 audit (docs/AUDIT-2026-10.md):
 *         PNFT-01 single-use approvals, PNFT-02 revocation, PNFT-03 Fibonacci finalize guard,
 *         PNFT-04 base-URI guard + ERC-4906, plus every branch the baseline suite never hit.
 */
contract AuditOct2026Test is Test {
    PsyNFTV2 internal nft;

    address internal owner = makeAddr("owner");
    address internal core = makeAddr("core");
    address internal treasury = makeAddr("treasury");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal carol = makeAddr("carol");

    event TransferApprovalRevoked(uint256 indexed tokenId);
    event BatchMetadataUpdate(uint256 _fromTokenId, uint256 _toTokenId);

    function setUp() public {
        nft = new PsyNFTV2(owner);
        vm.startPrank(owner);
        nft.setCoreContract(core);
        nft.setTreasury(treasury);
        vm.stopPrank();
    }

    // ------------------------------------------------------------------ //
    //                               helpers                              //
    // ------------------------------------------------------------------ //

    /// Fresh lifecycle: ids 0-4 minted, ids 0 and 1 distributed to alice.
    function _mintAndGiveAlice() internal {
        vm.startPrank(core);
        nft.initialMint();
        nft.batchMintInFibonacci();
        uint256[] memory ids = new uint256[](2);
        ids[0] = 0;
        ids[1] = 1;
        nft.transferNFTs(ids, alice);
        vm.stopPrank();
    }

    function _expiry(uint256 id) internal view returns (uint256 e) {
        (, e,) = nft.approvedTransfers(id);
    }

    function _approvedTo(uint256 id) internal view returns (address to) {
        (,, to) = nft.approvedTransfers(id);
    }

    function _migrateOne(address holder, uint256 id) internal {
        address[] memory h = new address[](1);
        uint256[] memory i = new uint256[](1);
        h[0] = holder;
        i[0] = id;
        vm.prank(owner);
        nft.migrateBatch(h, i);
    }

    // ------------------------------------------------------------------ //
    //  PNFT-01: approvals are single-use                                 //
    // ------------------------------------------------------------------ //

    function test_PNFT01_ApprovalConsumedOnUse() public {
        _mintAndGiveAlice();
        vm.prank(core);
        nft.approveTransfer(0, bob, 30 days);
        vm.prank(alice);
        nft.transferFrom(alice, bob, 0);

        assertEq(_expiry(0), 0, "grant cleared after use");
        assertEq(_approvedTo(0), address(0), "grant recipient cleared");
        // V1 blocked a fresh approval for the full 30 days; now core can act immediately.
        vm.prank(core);
        nft.approveTransfer(0, carol, 1 days);
        assertEq(_approvedTo(0), carol);
    }

    function test_PNFT01_StaleGrantCannotRevive() public {
        // The V1 scenario: grant to bob, alice->bob, controls off, bob->carol, controls back on.
        // In V1 the 30-day grant stayed live, so carol could hand the token to bob with no new
        // core approval. In V2 the grant died with the first transfer.
        _mintAndGiveAlice();
        vm.prank(core);
        nft.approveTransfer(0, bob, 30 days);
        vm.prank(alice);
        nft.transferFrom(alice, bob, 0);

        vm.prank(owner);
        nft.disableControlledTransfers();
        vm.prank(bob);
        nft.transferFrom(bob, carol, 0);
        vm.prank(owner);
        nft.enableControlledTransfers();

        vm.prank(carol);
        vm.expectRevert("PsyNFT: Incorrect Receiver");
        nft.transferFrom(carol, bob, 0);
    }

    function test_PNFT01_SafeTransferAlsoConsumes() public {
        _mintAndGiveAlice();
        vm.prank(core);
        nft.approveTransfer(1, bob, 1 days);
        vm.prank(alice);
        nft.safeTransferFrom(alice, bob, 1);
        assertEq(_expiry(1), 0);
        assertEq(nft.ownerOf(1), bob);
    }

    function test_PNFT01_FreeTransferClearsStaleGrant() public {
        _mintAndGiveAlice();
        vm.prank(core);
        nft.approveTransfer(0, bob, 1 days);
        vm.prank(owner);
        nft.disableControlledTransfers();
        vm.prank(alice);
        nft.transferFrom(alice, carol, 0); // moved somewhere else entirely
        assertEq(_expiry(0), 0, "grant does not follow the token to a new owner");
    }

    function test_PNFT01_BurnClearsGrant() public {
        _mintAndGiveAlice();
        vm.prank(core);
        nft.approveTransfer(0, bob, 1 days);
        vm.prank(treasury);
        nft.burn(0);
        assertEq(_expiry(0), 0);
    }

    function test_PNFT01_DistributionClearsGrant() public {
        // A grant on a contract-held token is meaningless; distribution must not leave it behind.
        vm.startPrank(core);
        nft.initialMint();
        nft.approveTransfer(2, bob, 1 days);
        uint256[] memory ids = new uint256[](1);
        ids[0] = 2;
        nft.transferNFTs(ids, alice);
        vm.stopPrank();
        assertEq(_expiry(2), 0);
        vm.prank(alice);
        vm.expectRevert("PsyNFT: Incorrect Receiver");
        nft.transferFrom(alice, bob, 2);
    }

    function test_PNFT01_MintDoesNotTouchApprovals() public {
        // Gas guard: minting never reads approval storage (from == 0 short-circuits).
        vm.prank(core);
        nft.initialMint();
        vm.prank(core);
        uint256 g = gasleft();
        nft.batchMintInFibonacci();
        g -= gasleft();
        assertLt(g, 150_000, "batch of 2 stays cheap");
    }

    // ------------------------------------------------------------------ //
    //  PNFT-02: core can revoke a live approval                          //
    // ------------------------------------------------------------------ //

    function test_PNFT02_RevokeTransfer() public {
        _mintAndGiveAlice();
        vm.prank(core);
        nft.approveTransfer(0, bob, 365 days); // the "wrong address, long window" mistake

        vm.expectEmit(true, false, false, false, address(nft));
        emit TransferApprovalRevoked(0);
        vm.prank(core);
        nft.revokeTransfer(0);

        assertEq(_expiry(0), 0);
        vm.prank(alice);
        vm.expectRevert("PsyNFT: Incorrect Receiver");
        nft.transferFrom(alice, bob, 0);

        // and the corrected approval can be issued straight away
        vm.prank(core);
        nft.approveTransfer(0, carol, 1 days);
        vm.prank(alice);
        nft.transferFrom(alice, carol, 0);
        assertEq(nft.ownerOf(0), carol);
    }

    function test_PNFT02_RevokeOnlyCore() public {
        _mintAndGiveAlice();
        vm.prank(core);
        nft.approveTransfer(0, bob, 1 days);
        address[4] memory notCore = [owner, treasury, alice, bob];
        for (uint256 i; i < notCore.length; i++) {
            vm.prank(notCore[i]);
            vm.expectRevert("PsyNFT: Caller Not Core Contract");
            nft.revokeTransfer(0);
        }
    }

    function test_PNFT02_RevokeRequiresApproval() public {
        _mintAndGiveAlice();
        vm.prank(core);
        vm.expectRevert("PsyNFT: No Approval To Revoke");
        nft.revokeTransfer(0);
    }

    // ------------------------------------------------------------------ //
    //  PNFT-03: finalize only accepts on-schedule counters               //
    // ------------------------------------------------------------------ //

    function test_PNFT03_RejectsTypos() public {
        _migrateOne(alice, 33);
        uint256[2][6] memory bad = [
            [uint256(210), uint256(34)], // extra digit
            [uint256(20), uint256(34)], // off by one
            [uint256(21), uint256(35)],
            [uint256(55), uint256(34)], // prev/next swapped
            [uint256(0), uint256(34)],
            [uint256(13), uint256(34)] // skipped a term
        ];
        for (uint256 i; i < bad.length; i++) {
            vm.prank(owner);
            vm.expectRevert("PsyNFT: Counters Not On Schedule");
            nft.finalizeMigration(bad[i][1], bad[i][0], true, 1);
        }
        vm.prank(owner);
        nft.finalizeMigration(34, 21, true, 1); // the real V1 values
        assertEq(nft.tokenId(), 34);
        assertEq(nft.previousFibonacci(), 21);
    }

    function test_PNFT03_AcceptsEveryScheduleTerm() public pure {
        // Mirror of the private check over the first terms the real schedule can reach.
        uint256 a = 2;
        uint256 b = 3;
        for (uint256 i; i < 40; i++) {
            assertTrue(_pair(a, b));
            assertFalse(_pair(a + 1, b));
            assertFalse(_pair(a, b + 1));
            (a, b) = (b, a + b);
        }
    }

    function testFuzz_PNFT03_FinalizeAcceptsOnlyFibonacciPairs(uint256 prev, uint256 next) public {
        next = bound(next, 34, 1e30);
        prev = bound(prev, 0, 1e30);
        _migrateOne(alice, 33);
        vm.prank(owner);
        if (_pair(prev, next)) {
            nft.finalizeMigration(next, prev, true, 1);
            assertTrue(nft.migrationFinalized());
        } else {
            vm.expectRevert("PsyNFT: Counters Not On Schedule");
            nft.finalizeMigration(next, prev, true, 1);
        }
    }

    function _pair(uint256 prev, uint256 next) internal pure returns (bool) {
        uint256 a = 2;
        uint256 b = 3;
        while (b < next) (a, b) = (b, a + b);
        return a == prev && b == next;
    }

    // ------------------------------------------------------------------ //
    //  PNFT-04: base URI guard + ERC-4906                                //
    // ------------------------------------------------------------------ //

    function test_PNFT04_BaseUriNeedsTrailingSlash() public {
        vm.prank(owner);
        vm.expectRevert("PsyNFT: Base URI Must End With Slash");
        nft.setBaseUri("ipfs://bafyexample");

        vm.prank(owner);
        nft.setBaseUri("ipfs://bafyexample/");
        assertEq(nft.baseUri(), "ipfs://bafyexample/");

        vm.prank(owner);
        nft.setBaseUri(""); // clearing stays possible
        assertEq(nft.baseUri(), "");
    }

    function test_PNFT04_EmitsBatchMetadataUpdate() public {
        vm.expectEmit(false, false, false, true, address(nft));
        emit BatchMetadataUpdate(0, type(uint256).max);
        vm.prank(owner);
        nft.setBaseUri("ipfs://new/");
    }

    function test_PNFT04_SupportsInterfaces() public view {
        assertTrue(nft.supportsInterface(0x49064906), "ERC-4906");
        assertTrue(nft.supportsInterface(0x80ac58cd), "ERC-721");
        assertTrue(nft.supportsInterface(0x5b5e139f), "ERC-721 metadata");
        assertTrue(nft.supportsInterface(0x01ffc9a7), "ERC-165");
        assertFalse(nft.supportsInterface(0xffffffff));
        assertFalse(nft.supportsInterface(0x780e9d63), "not enumerable");
    }

    // ------------------------------------------------------------------ //
    //  Branches the baseline suite never hit                             //
    // ------------------------------------------------------------------ //

    function test_Gap_MigrateAfterFinalizeReverts() public {
        _migrateOne(alice, 33);
        vm.prank(owner);
        nft.finalizeMigration(34, 21, true, 1);
        address[] memory h = new address[](1);
        uint256[] memory i = new uint256[](1);
        h[0] = bob;
        i[0] = 40;
        vm.prank(owner);
        vm.expectRevert("PsyNFT: Migration Finalized");
        nft.migrateBatch(h, i);
        vm.prank(owner);
        vm.expectRevert("PsyNFT: Migration Finalized");
        nft.finalizeMigration(34, 21, true, 1);
    }

    function test_Gap_MigrateAfterInitialMintReverts() public {
        vm.prank(core);
        nft.initialMint();
        address[] memory h = new address[](1);
        uint256[] memory i = new uint256[](1);
        h[0] = bob;
        i[0] = 10;
        vm.prank(owner);
        vm.expectRevert("PsyNFT: Initial Mint Done");
        nft.migrateBatch(h, i);
    }

    function test_Gap_SetTreasuryZeroReverts() public {
        vm.prank(owner);
        vm.expectRevert("PsyNFT: Treasury Cannot Be Zero Address");
        nft.setTreasury(address(0));
    }

    function test_Gap_ReEnableControlledTransfers() public {
        vm.startPrank(owner);
        nft.disableControlledTransfers();
        assertFalse(nft.controlledTransfers());
        nft.enableControlledTransfers();
        vm.stopPrank();
        assertTrue(nft.controlledTransfers(), "re-enable restores the gate");

        _mintAndGiveAlice();
        vm.prank(alice);
        vm.expectRevert("PsyNFT: Incorrect Receiver");
        nft.transferFrom(alice, bob, 0);
    }

    function test_Gap_RescueToZeroReverts() public {
        vm.startPrank(owner);
        vm.expectRevert("PsyNFT: Rescue To Zero");
        nft.rescueERC20(address(0x1234), address(0), 1);
        vm.expectRevert("PsyNFT: Rescue To Zero");
        nft.rescueERC721(address(0x1234), address(0), 1);
        vm.expectRevert("PsyNFT: Rescue To Zero");
        nft.rescueETH(payable(address(0)), 1);
        vm.stopPrank();
    }

    function test_Gap_RescueEthFailureReverts() public {
        vm.deal(address(nft), 1 ether);
        EthRejecter r = new EthRejecter();
        vm.prank(owner);
        vm.expectRevert("PsyNFT: ETH Transfer Failed");
        nft.rescueETH(payable(address(r)), 1 ether);
        assertEq(address(nft).balance, 1 ether, "nothing left the contract");
    }

    function test_Gap_ContractRejectsPlainEth() public {
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        (bool ok,) = address(nft).call{value: 1 ether}("");
        assertFalse(ok, "no receive/fallback: ETH only arrives by force");
    }

    function test_Gap_UnmintedAndBurntTokenUri() public {
        vm.prank(owner);
        nft.setBaseUri("ipfs://cid/");
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, 7));
        nft.tokenURI(7);
        _mintAndGiveAlice();
        assertEq(nft.tokenURI(4), "ipfs://cid/4");
        vm.prank(treasury);
        nft.burn(4);
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, 4));
        nft.tokenURI(4);
    }

    function test_Gap_PendingOwnerCanBeCancelled() public {
        vm.prank(owner);
        nft.transferOwnership(alice);
        vm.prank(owner);
        nft.transferOwnership(address(0)); // OZ Ownable2Step: cancel a mistaken handoff
        assertEq(nft.pendingOwner(), address(0));
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        nft.acceptOwnership();
        assertEq(nft.owner(), owner);
    }

    function test_Gap_ContractHeldTokensHaveNoOperators() public {
        // Nobody can become an operator for tokens the contract holds: the contract never
        // calls approve/setApprovalForAll, and members' approvals can't touch them.
        vm.prank(core);
        nft.initialMint();
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721InvalidApprover.selector, alice));
        nft.approve(alice, 0);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721InsufficientApproval.selector, alice, 0));
        nft.transferFrom(address(nft), alice, 0);
        assertEq(nft.getApproved(0), address(0));
    }

    // ------------------------------------------------------------------ //
    //  Fuzz: the controlled-transfer gate                                //
    // ------------------------------------------------------------------ //

    /// A member transfer succeeds iff (controls off) or (to == approved recipient and now <= expiry).
    function testFuzz_ControlledTransferGate(
        uint64 window,
        uint64 elapsed,
        bool toApproved,
        bool controls,
        bool viaOperator
    ) public {
        _mintAndGiveAlice();
        if (!controls) {
            vm.prank(owner);
            nft.disableControlledTransfers();
        }
        vm.prank(core);
        nft.approveTransfer(0, bob, window);
        uint256 expiry = block.timestamp + window;
        vm.warp(block.timestamp + elapsed);

        address to = toApproved ? bob : carol;
        address caller = alice;
        if (viaOperator) {
            vm.prank(alice);
            nft.setApprovalForAll(carol, true); // operators get no bypass
            caller = carol;
        }
        bool shouldPass = !controls || (to == bob && block.timestamp <= expiry);

        vm.prank(caller);
        if (shouldPass) {
            nft.transferFrom(alice, to, 0);
            assertEq(nft.ownerOf(0), to);
            assertEq(_expiry(0), 0, "single-use");
        } else {
            vm.expectRevert();
            nft.transferFrom(alice, to, 0);
            assertEq(nft.ownerOf(0), alice);
        }
    }

    /// approveTransfer can only replace a grant once it has expired (or been used/revoked).
    function testFuzz_ApprovalReplacement(uint32 window, uint32 elapsed) public {
        _mintAndGiveAlice();
        vm.prank(core);
        nft.approveTransfer(0, bob, window);
        uint256 expiry = block.timestamp + window;
        vm.warp(block.timestamp + elapsed);
        vm.prank(core);
        if (block.timestamp > expiry) {
            nft.approveTransfer(0, carol, 1);
            assertEq(_approvedTo(0), carol);
        } else {
            vm.expectRevert("PsyNFT: Transfer Request Currently Active");
            nft.approveTransfer(0, carol, 1);
        }
    }

    /// Arbitrary (unique, non-zero-holder) migrations: ids and owners are reproduced exactly and
    /// finalize only succeeds with the exact count.
    function testFuzz_MigrateBatch(uint8 n, uint256 seed, uint8 wrongBy) public {
        n = uint8(bound(n, 1, 34)); // ids 0..33, the V1 range below the resume point
        address[] memory h = new address[](n);
        uint256[] memory ids = new uint256[](n);
        for (uint256 i; i < n; i++) {
            h[i] = address(uint160(uint256(keccak256(abi.encode(seed, i))) | 1));
            ids[i] = i; // unique, all below the 34 resume point
        }
        vm.prank(owner);
        nft.migrateBatch(h, ids);
        assertEq(nft.migratedCount(), n);
        for (uint256 i; i < n; i++) {
            assertEq(nft.ownerOf(ids[i]), h[i]);
        }
        if (wrongBy % 2 == 1) {
            vm.prank(owner);
            vm.expectRevert("PsyNFT: Incomplete Migration");
            nft.finalizeMigration(34, 21, true, uint256(n) + 1 + wrongBy);
        }
        vm.prank(owner);
        nft.finalizeMigration(34, 21, true, n);
        assertTrue(nft.migrationFinalized());
    }
}
