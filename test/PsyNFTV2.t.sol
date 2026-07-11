// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Test.sol";
import {PsyNFTV2} from "../src/PsyNFTV2.sol";
import {IERC721Errors, IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @dev Minimal ERC20 for rescue tests.
contract MockERC20 is ERC20 {
    constructor() ERC20("Mock", "MOCK") {}

    function mint(address to, uint256 amt) external {
        _mint(to, amt);
    }
}

/// @dev Minimal ERC721 for foreign-rescue tests.
contract MockERC721 is ERC721 {
    constructor() ERC721("MockNFT", "MNFT") {}

    function mint(address to, uint256 id) external {
        _mint(to, id);
    }
}

contract PsyNFTV2Test is Test {
    PsyNFTV2 internal nft;

    address internal owner = makeAddr("owner");
    address internal core = makeAddr("core");
    address internal treasury = makeAddr("treasury");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    // Mirror the contract events for expectEmit.
    event CoreUpdated(address indexed previousCore, address indexed newCore);
    event TreasuryUpdated(address indexed previousTreasury, address indexed newTreasury);
    event BaseUriUpdated(string newBaseUri);
    event ControlledTransfersSet(bool enabled);
    event TransferApproved(uint256 indexed tokenId, address indexed to, uint256 expiry);
    event TokenBurnt(uint256 indexed tokenId, address indexed from);
    event Migrated(uint256 indexed tokenId, address indexed to);
    event MigrationFinalized(uint256 nextTokenId, uint256 previousFibonacci, bool controlledTransfers);

    function setUp() public {
        vm.prank(owner);
        nft = new PsyNFTV2(owner);
        // Wire roles as owner.
        vm.startPrank(owner);
        nft.setCoreContract(core);
        nft.setTreasury(treasury);
        vm.stopPrank();
    }

    // ------------------------------------------------------------------ //
    //                            Construction                            //
    // ------------------------------------------------------------------ //

    function test_Construction() public view {
        assertEq(nft.name(), "PsyNFT");
        assertEq(nft.symbol(), "PSY");
        assertEq(nft.owner(), owner);
        assertTrue(nft.controlledTransfers());
        assertEq(nft.previousFibonacci(), 2);
        assertEq(nft.core(), core);
        assertEq(nft.treasury(), treasury);
        assertFalse(nft.initialMintCalled());
    }

    function test_ConstructorOwnerCanBeSafe() public {
        address safe = makeAddr("safe");
        PsyNFTV2 n = new PsyNFTV2(safe);
        assertEq(n.owner(), safe);
    }

    // ------------------------------------------------------------------ //
    //                         Fresh initialMint                          //
    // ------------------------------------------------------------------ //

    function test_InitialMint_OnlyCore() public {
        vm.expectRevert("PsyNFT: Caller Not Core Contract");
        vm.prank(owner);
        nft.initialMint();
    }

    function test_InitialMint_MintsThreeToContract() public {
        vm.prank(core);
        nft.initialMint();
        assertEq(nft.tokenId(), 3);
        for (uint256 i; i < 3; i++) {
            assertEq(nft.ownerOf(i), address(nft));
        }
        assertTrue(nft.initialMintCalled());
    }

    function test_InitialMint_CannotRunTwice() public {
        vm.prank(core);
        nft.initialMint();
        vm.expectRevert("PsyNFT: Initial Mint Complete");
        vm.prank(core);
        nft.initialMint();
    }

    // ------------------------------------------------------------------ //
    //                       Fibonacci batch schedule                     //
    // ------------------------------------------------------------------ //

    function test_FibonacciSchedule_MatchesV1State() public {
        vm.prank(core);
        nft.initialMint(); // tokenId=3, prevFib=2

        uint256[6] memory expectedTokenIdAfter = [uint256(3), 5, 8, 13, 21, 34];
        uint256[6] memory expectedPrevFibAfter = [uint256(2), 3, 5, 8, 13, 21];
        // index 0 == state right after initialMint
        assertEq(nft.tokenId(), expectedTokenIdAfter[0]);
        assertEq(nft.previousFibonacci(), expectedPrevFibAfter[0]);

        for (uint256 b = 1; b <= 5; b++) {
            vm.prank(core);
            nft.batchMintInFibonacci();
            assertEq(nft.tokenId(), expectedTokenIdAfter[b], "tokenId");
            assertEq(nft.previousFibonacci(), expectedPrevFibAfter[b], "prevFib");
        }
        // 5 batches from a fresh mint reproduce the live V1 counters exactly.
        assertEq(nft.tokenId(), 34);
        assertEq(nft.previousFibonacci(), 21);
        // Every id 0..33 is owned by the contract, awaiting distribution.
        for (uint256 i; i < 34; i++) {
            assertEq(nft.ownerOf(i), address(nft));
        }
    }

    function test_BatchMint_RequiresInitialMint() public {
        vm.expectRevert("PsyNFT: Initial Mint Not Completed");
        vm.prank(core);
        nft.batchMintInFibonacci();
    }

    function test_BatchMint_OnlyCore() public {
        vm.prank(core);
        nft.initialMint();
        vm.expectRevert("PsyNFT: Caller Not Core Contract");
        vm.prank(alice);
        nft.batchMintInFibonacci();
    }

    // ------------------------------------------------------------------ //
    //                            Distribution                            //
    // ------------------------------------------------------------------ //

    function _mintAndDistribute(address to, uint256 id) internal {
        vm.prank(core);
        nft.initialMint(); // ids 0,1,2 held by contract
        uint256[] memory ids = new uint256[](1);
        ids[0] = id;
        vm.prank(core);
        nft.transferNFTs(ids, to);
    }

    function test_TransferNFTs_DistributesToMember() public {
        _mintAndDistribute(alice, 0);
        assertEq(nft.ownerOf(0), alice);
    }

    function test_TransferNFTs_OnlyCore() public {
        vm.prank(core);
        nft.initialMint();
        uint256[] memory ids = new uint256[](1);
        ids[0] = 0;
        vm.expectRevert("PsyNFT: Caller Not Core Contract");
        vm.prank(alice);
        nft.transferNFTs(ids, alice);
    }

    function test_TransferNFTs_RejectsZeroAndEmpty() public {
        vm.prank(core);
        nft.initialMint();
        uint256[] memory ids = new uint256[](1);
        ids[0] = 0;
        vm.prank(core);
        vm.expectRevert("PsyNFT: Recipient Cannot Be Zero Address");
        nft.transferNFTs(ids, address(0));

        uint256[] memory empty = new uint256[](0);
        vm.prank(core);
        vm.expectRevert("PsyNFT: Token Array Empty");
        nft.transferNFTs(empty, alice);
    }

    // ------------------------------------------------------------------ //
    //                       Controlled transfers                         //
    // ------------------------------------------------------------------ //

    function test_ControlledTransfer_BlockedWithoutApproval() public {
        _mintAndDistribute(alice, 0);
        vm.prank(alice);
        vm.expectRevert("PsyNFT: Incorrect Receiver");
        nft.transferFrom(alice, bob, 0);
    }

    function test_ControlledTransfer_SucceedsWithApproval() public {
        _mintAndDistribute(alice, 0);
        vm.prank(core);
        nft.approveTransfer(0, bob, 1 days);

        vm.prank(alice);
        nft.transferFrom(alice, bob, 0);
        assertEq(nft.ownerOf(0), bob);
    }

    function test_ControlledTransfer_WrongReceiverReverts() public {
        _mintAndDistribute(alice, 0);
        vm.prank(core);
        nft.approveTransfer(0, bob, 1 days);
        vm.prank(alice);
        vm.expectRevert("PsyNFT: Incorrect Receiver");
        nft.transferFrom(alice, makeAddr("carol"), 0);
    }

    function test_ControlledTransfer_ExpiredReverts() public {
        _mintAndDistribute(alice, 0);
        vm.prank(core);
        nft.approveTransfer(0, bob, 1 days);
        vm.warp(block.timestamp + 1 days + 1);
        vm.prank(alice);
        vm.expectRevert("PsyNFT: Approval Expired");
        nft.transferFrom(alice, bob, 0);
    }

    function test_ControlledTransfer_GatesSafeTransferFrom() public {
        // safeTransferFrom routes through the overridden transferFrom in OZ v5.
        _mintAndDistribute(alice, 0);
        vm.prank(alice);
        vm.expectRevert("PsyNFT: Incorrect Receiver");
        nft.safeTransferFrom(alice, bob, 0);
    }

    function test_Disabled_AllowsFreeTransfer() public {
        _mintAndDistribute(alice, 0);
        vm.prank(owner);
        nft.disableControlledTransfers();
        vm.prank(alice);
        nft.transferFrom(alice, bob, 0);
        assertEq(nft.ownerOf(0), bob);
    }

    function test_ApproveTransfer_OnlyCore_NonExistent_Active() public {
        _mintAndDistribute(alice, 0);
        // only core
        vm.prank(alice);
        vm.expectRevert("PsyNFT: Caller Not Core Contract");
        nft.approveTransfer(0, bob, 1 days);
        // non existent (id >= tokenId == 3)
        vm.prank(core);
        vm.expectRevert("PsyNFT: Non Existent Token");
        nft.approveTransfer(99, bob, 1 days);
        // active request cannot be overwritten
        vm.prank(core);
        nft.approveTransfer(0, bob, 1 days);
        vm.prank(core);
        vm.expectRevert("PsyNFT: Transfer Request Currently Active");
        nft.approveTransfer(0, alice, 1 days);
    }

    // ------------------------------------------------------------------ //
    //                                Burn                                //
    // ------------------------------------------------------------------ //

    function test_Burn_OnlyTreasury() public {
        _mintAndDistribute(alice, 0);
        vm.prank(alice);
        vm.expectRevert("PsyNFT: Caller Is Not Treasury");
        nft.burn(0);
    }

    function test_Burn_ByTreasury() public {
        _mintAndDistribute(alice, 0);
        vm.expectEmit(true, true, false, true);
        emit TokenBurnt(0, alice);
        vm.prank(treasury);
        nft.burn(0);
        assertEq(nft.totalTokensBurnt(), 1);
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, 0));
        nft.ownerOf(0);
    }

    // ------------------------------------------------------------------ //
    //                          Admin setters                             //
    // ------------------------------------------------------------------ //

    function test_Setters_OnlyOwner() public {
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        nft.setCoreContract(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        nft.setTreasury(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        nft.setBaseUri("x");
        vm.stopPrank();
    }

    function test_SetCore_EmitsAndRejectsZero() public {
        vm.expectEmit(true, true, false, false);
        emit CoreUpdated(core, alice);
        vm.prank(owner);
        nft.setCoreContract(alice);
        assertEq(nft.core(), alice);

        vm.prank(owner);
        vm.expectRevert("PsyNFT: Core Cannot Be Zero Address");
        nft.setCoreContract(address(0));
    }

    function test_SetBaseUri_AffectsTokenURI() public {
        vm.prank(core);
        nft.initialMint();
        vm.prank(owner);
        nft.setBaseUri("ipfs://base/");
        assertEq(nft.tokenURI(0), "ipfs://base/0");
    }

    function test_ControlledToggle_Guards() public {
        // already enabled
        vm.prank(owner);
        vm.expectRevert("PsyNFT: Controlled Transfers Already Enabled");
        nft.enableControlledTransfers();
        // disable then can't disable again
        vm.prank(owner);
        nft.disableControlledTransfers();
        vm.prank(owner);
        vm.expectRevert("PsyNFT: Controlled Transfers Already Disabled");
        nft.disableControlledTransfers();
    }

    // ------------------------------------------------------------------ //
    //                      Ownership handoff (2-step)                    //
    // ------------------------------------------------------------------ //

    function test_OwnershipHandoffToSafe() public {
        address safe = makeAddr("safe");
        vm.prank(owner);
        nft.transferOwnership(safe);
        assertEq(nft.owner(), owner); // not yet
        assertEq(nft.pendingOwner(), safe);

        vm.prank(safe);
        nft.acceptOwnership();
        assertEq(nft.owner(), safe);

        // old owner no longer privileged
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, owner));
        nft.setTreasury(alice);
    }

    // ------------------------------------------------------------------ //
    //                           Migration path                           //
    // ------------------------------------------------------------------ //

    function test_Migrate_OnlyOwner() public {
        address[] memory h = new address[](1);
        uint256[] memory ids = new uint256[](1);
        h[0] = alice;
        ids[0] = 0;
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        nft.migrateBatch(h, ids);
    }

    function test_Migrate_MintsToHoldersPreservingIds() public {
        address[] memory h = new address[](3);
        uint256[] memory ids = new uint256[](3);
        h[0] = alice;
        h[1] = bob;
        h[2] = address(nft); // undistributed token -> held by new contract
        ids[0] = 5;
        ids[1] = 9;
        ids[2] = 2;

        vm.expectEmit(true, true, false, true);
        emit Migrated(5, alice);
        vm.prank(owner);
        nft.migrateBatch(h, ids);

        assertEq(nft.ownerOf(5), alice);
        assertEq(nft.ownerOf(9), bob);
        assertEq(nft.ownerOf(2), address(nft));
        assertTrue(nft.migrationStarted());
    }

    function test_Migrate_RejectsBadInput() public {
        address[] memory h = new address[](2);
        uint256[] memory ids = new uint256[](1);
        vm.prank(owner);
        vm.expectRevert("PsyNFT: Length Mismatch");
        nft.migrateBatch(h, ids);

        address[] memory eh = new address[](0);
        uint256[] memory eids = new uint256[](0);
        vm.prank(owner);
        vm.expectRevert("PsyNFT: Empty Batch");
        nft.migrateBatch(eh, eids);

        address[] memory zh = new address[](1);
        uint256[] memory zids = new uint256[](1);
        zh[0] = address(0);
        zids[0] = 0;
        vm.prank(owner);
        vm.expectRevert("PsyNFT: Zero Holder");
        nft.migrateBatch(zh, zids);
    }

    function test_Migrate_NoDoubleMint() public {
        address[] memory h = new address[](1);
        uint256[] memory ids = new uint256[](1);
        h[0] = alice;
        ids[0] = 7;
        vm.prank(owner);
        nft.migrateBatch(h, ids);
        // same id again -> ERC721 rejects existing token
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721InvalidSender.selector, address(0)));
        nft.migrateBatch(h, ids);
    }

    function test_Migrate_BlocksInitialMint() public {
        address[] memory h = new address[](1);
        uint256[] memory ids = new uint256[](1);
        h[0] = alice;
        ids[0] = 0;
        vm.prank(owner);
        nft.migrateBatch(h, ids);
        vm.prank(core);
        vm.expectRevert("PsyNFT: Migration In Progress");
        nft.initialMint();
    }

    function test_Finalize_RequiresStartedAndCeiling() public {
        // not started
        vm.prank(owner);
        vm.expectRevert("PsyNFT: Migration Not Started");
        nft.finalizeMigration(34, 21, true, 33);

        // start with id 33 -> ceiling 34; nextTokenId 33 too low
        address[] memory h = new address[](1);
        uint256[] memory ids = new uint256[](1);
        h[0] = alice;
        ids[0] = 33;
        vm.prank(owner);
        nft.migrateBatch(h, ids);
        vm.prank(owner);
        vm.expectRevert("PsyNFT: nextTokenId Too Low");
        nft.finalizeMigration(33, 21, true, 1);
    }

    function test_Finalize_RejectsIncompleteMigration() public {
        // migrate 1 token but declare 2 expected -> must revert (completeness guard, MIG-1)
        address[] memory h = new address[](1);
        uint256[] memory ids = new uint256[](1);
        h[0] = alice;
        ids[0] = 5;
        vm.prank(owner);
        nft.migrateBatch(h, ids);
        assertEq(nft.migratedCount(), 1);
        vm.prank(owner);
        vm.expectRevert("PsyNFT: Incomplete Migration");
        nft.finalizeMigration(34, 21, true, 2);
    }

    /// @notice The realistic migration: re-mint 33 existing tokens, finalize at V1 counters,
    ///         then the schedule resumes and the next batch mints 21 tokens (ids 34..54).
    function test_FullMigration_ResumesSchedule() public {
        // Re-mint ids 0..32 to a mix of holders (simulating the 33 live tokens; id 33 assumed burnt).
        uint256 n = 33;
        address[] memory h = new address[](n);
        uint256[] memory ids = new uint256[](n);
        for (uint256 i; i < n; i++) {
            h[i] = i % 3 == 0 ? address(nft) : (i % 2 == 0 ? alice : bob);
            ids[i] = i;
        }
        vm.prank(owner);
        nft.migrateBatch(h, ids);

        vm.expectEmit(false, false, false, true);
        emit MigrationFinalized(34, 21, true);
        vm.prank(owner);
        nft.finalizeMigration(34, 21, true, 33);

        assertEq(nft.tokenId(), 34);
        assertEq(nft.previousFibonacci(), 21);
        assertTrue(nft.initialMintCalled());
        assertTrue(nft.migrationFinalized());

        assertEq(nft.migratedCount(), 33);

        // migration is locked
        vm.prank(owner);
        vm.expectRevert("PsyNFT: Migration Finalized");
        nft.migrateBatch(h, ids);

        // schedule resumes: next batch mints previousFibonacci (21) tokens -> ids 34..54
        vm.prank(core);
        nft.batchMintInFibonacci();
        assertEq(nft.tokenId(), 55);
        assertEq(nft.previousFibonacci(), 34);
        for (uint256 i = 34; i < 55; i++) {
            assertEq(nft.ownerOf(i), address(nft));
        }
    }

    // ------------------------------------------------------------------ //
    //                              Rescue                                //
    // ------------------------------------------------------------------ //

    function test_RescueERC20() public {
        MockERC20 token = new MockERC20();
        token.mint(address(nft), 1_000e18);
        vm.prank(owner);
        nft.rescueERC20(address(token), alice, 1_000e18);
        assertEq(token.balanceOf(alice), 1_000e18);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        nft.rescueERC20(address(token), alice, 1);
    }

    function test_RescueERC721_ForeignOnly() public {
        MockERC721 foreign = new MockERC721();
        foreign.mint(address(nft), 42);
        vm.prank(owner);
        nft.rescueERC721(address(foreign), alice, 42);
        assertEq(foreign.ownerOf(42), alice);

        // cannot rescue self
        vm.prank(owner);
        vm.expectRevert("PsyNFT: Cannot Rescue Self");
        nft.rescueERC721(address(nft), alice, 0);
    }

    function test_RescueETH() public {
        vm.deal(address(nft), 1 ether);
        uint256 before = alice.balance;
        vm.prank(owner);
        nft.rescueETH(payable(alice), 1 ether);
        assertEq(alice.balance, before + 1 ether);
    }
}
