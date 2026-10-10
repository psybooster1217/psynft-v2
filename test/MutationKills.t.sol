// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Test.sol";
import {PsyNFTV2} from "../src/PsyNFTV2.sol";
import {MockERC20, MockERC721} from "./PsyNFTV2.t.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @notice Tests written to kill the mutants that survived the first mutation-testing run
 *         (audit/2026-10/mutation/results.md): un-asserted events, missing access-control
 *         negatives, and two boundary conditions. Each test names the mutant it kills.
 */
contract MutationKillsTest is Test {
    PsyNFTV2 internal nft;
    address internal owner = makeAddr("owner");
    address internal core = makeAddr("core");
    address internal treasury = makeAddr("treasury");
    address internal alice = makeAddr("alice");
    address internal mallory = makeAddr("mallory");

    event TreasuryUpdated(address indexed previousTreasury, address indexed newTreasury);
    event BaseUriUpdated(string newBaseUri);
    event ControlledTransfersSet(bool enabled);
    event TransferApproved(uint256 indexed tokenId, address indexed to, uint256 expiry);
    event ERC20Rescued(address indexed token, address indexed to, uint256 amount);
    event ERC721Rescued(address indexed token, address indexed to, uint256 tokenId);
    event ETHRescued(address indexed to, uint256 amount);

    function setUp() public {
        nft = new PsyNFTV2(owner);
        vm.startPrank(owner);
        nft.setCoreContract(core);
        nft.setTreasury(treasury);
        vm.stopPrank();
    }

    function _unauth(address who) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, who);
    }

    // ------------------------------------------------ access control (mutants #59, #133, #151)

    function test_Kill59_FinalizeOnlyOwner() public {
        address[] memory h = new address[](1);
        uint256[] memory i = new uint256[](1);
        h[0] = alice;
        i[0] = 33;
        vm.prank(owner);
        nft.migrateBatch(h, i);
        vm.prank(mallory);
        vm.expectRevert(_unauth(mallory));
        nft.finalizeMigration(34, 21, true, 1);
    }

    function test_Kill133_EnableControlledTransfersOnlyOwner() public {
        vm.prank(owner);
        nft.disableControlledTransfers();
        vm.prank(mallory);
        vm.expectRevert(_unauth(mallory));
        nft.enableControlledTransfers();
    }

    function test_Kill151_RescueERC721OnlyOwner() public {
        MockERC721 foreign = new MockERC721();
        foreign.mint(address(nft), 1);
        vm.prank(mallory);
        vm.expectRevert(_unauth(mallory));
        nft.rescueERC721(address(foreign), mallory, 1);
        assertEq(foreign.ownerOf(1), address(nft));
    }

    function test_RescueERC20AndEthOnlyOwner() public {
        MockERC20 t = new MockERC20();
        t.mint(address(nft), 10);
        vm.deal(address(nft), 1 ether);
        vm.startPrank(mallory);
        vm.expectRevert(_unauth(mallory));
        nft.rescueERC20(address(t), mallory, 10);
        vm.expectRevert(_unauth(mallory));
        nft.rescueETH(payable(mallory), 1 ether);
        vm.stopPrank();
    }

    // ------------------------------------------------ boundaries (mutants #54, #66, #100)

    /// #54: the migration ceiling must count the highest id itself (id + 1), so a resume
    /// counter equal to a migrated id is rejected.
    function test_Kill54_CeilingIncludesHighestId() public {
        address[] memory h = new address[](2);
        uint256[] memory i = new uint256[](2);
        h[0] = alice;
        h[1] = alice;
        i[0] = 33;
        i[1] = 34; // id 34 exists, so resuming at 34 would collide with it
        vm.prank(owner);
        nft.migrateBatch(h, i);
        vm.prank(owner);
        vm.expectRevert("PsyNFT: nextTokenId Too Low");
        nft.finalizeMigration(34, 21, true, 2);
    }

    /// #66: finalize must apply the controlledTransfers flag it is given.
    function test_Kill66_FinalizeAppliesControlledFlag() public {
        address[] memory h = new address[](1);
        uint256[] memory i = new uint256[](1);
        h[0] = alice;
        i[0] = 33;
        vm.prank(owner);
        nft.migrateBatch(h, i);
        vm.prank(owner);
        nft.finalizeMigration(34, 21, false, 1);
        assertFalse(nft.controlledTransfers());
        vm.prank(alice);
        nft.transferFrom(alice, mallory, 33); // free transfer now allowed
        assertEq(nft.ownerOf(33), mallory);
    }

    /// #100: the next unminted id (== tokenId) is not approvable.
    function test_Kill100_ApproveNextUnmintedIdReverts() public {
        vm.prank(core);
        nft.initialMint(); // tokenId == 3
        vm.prank(core);
        vm.expectRevert("PsyNFT: Non Existent Token");
        nft.approveTransfer(3, alice, 1 days);
        vm.prank(core);
        nft.approveTransfer(2, alice, 1 days); // last minted id is fine
    }

    // ------------------------------------------------ exact-second expiry boundaries (run-3 survivors)

    function _giveAliceToken0() internal {
        vm.startPrank(core);
        nft.initialMint();
        uint256[] memory ids = new uint256[](1);
        ids[0] = 0;
        nft.transferNFTs(ids, alice);
        vm.stopPrank();
    }

    /// `transferFrom` uses `<=`: a transfer IN the expiry second is still allowed.
    function test_KillBoundary_TransferAtExactExpirySucceeds() public {
        _giveAliceToken0();
        vm.prank(core);
        nft.approveTransfer(0, mallory, 100);
        vm.warp(block.timestamp + 100); // == expiry
        vm.prank(alice);
        nft.transferFrom(alice, mallory, 0);
        assertEq(nft.ownerOf(0), mallory);
    }

    /// `approveTransfer` uses `>`: a grant is still live in its expiry second, so it can't be replaced yet.
    function test_KillBoundary_ApproveAtExactExpiryReverts() public {
        _giveAliceToken0();
        vm.prank(core);
        nft.approveTransfer(0, mallory, 100);
        vm.warp(block.timestamp + 100); // == expiry
        vm.prank(core);
        vm.expectRevert("PsyNFT: Transfer Request Currently Active");
        nft.approveTransfer(0, alice, 100);
        vm.warp(block.timestamp + 1); // one second later it can be replaced
        vm.prank(core);
        nft.approveTransfer(0, alice, 100);
    }

    // ------------------------------------------------ events (#106, #126, #131/2, #137/8, #144, #150, #155, #159)

    function test_Kill106_EmitsTransferApproved() public {
        vm.prank(core);
        nft.initialMint();
        vm.expectEmit(true, true, false, true, address(nft));
        emit TransferApproved(1, alice, block.timestamp + 3600);
        vm.prank(core);
        nft.approveTransfer(1, alice, 3600);
    }

    function test_Kill126_EmitsTreasuryUpdated() public {
        vm.expectEmit(true, true, false, false, address(nft));
        emit TreasuryUpdated(treasury, alice);
        vm.prank(owner);
        nft.setTreasury(alice);
    }

    function test_Kill131_137_EmitsControlledTransfersSet() public {
        vm.expectEmit(false, false, false, true, address(nft));
        emit ControlledTransfersSet(false);
        vm.prank(owner);
        nft.disableControlledTransfers();

        vm.expectEmit(false, false, false, true, address(nft));
        emit ControlledTransfersSet(true);
        vm.prank(owner);
        nft.enableControlledTransfers();
    }

    function test_Kill144_EmitsBaseUriUpdated() public {
        vm.expectEmit(false, false, false, true, address(nft));
        emit BaseUriUpdated("ipfs://cid/");
        vm.prank(owner);
        nft.setBaseUri("ipfs://cid/");
    }

    function test_Kill150_155_159_EmitsRescueEvents() public {
        MockERC20 t = new MockERC20();
        t.mint(address(nft), 10);
        MockERC721 foreign = new MockERC721();
        foreign.mint(address(nft), 7);
        vm.deal(address(nft), 1 ether);

        vm.startPrank(owner);
        vm.expectEmit(true, true, false, true, address(nft));
        emit ERC20Rescued(address(t), alice, 10);
        nft.rescueERC20(address(t), alice, 10);

        vm.expectEmit(true, true, false, true, address(nft));
        emit ERC721Rescued(address(foreign), alice, 7);
        nft.rescueERC721(address(foreign), alice, 7);

        vm.expectEmit(true, false, false, true, address(nft));
        emit ETHRescued(alice, 1 ether);
        nft.rescueETH(payable(alice), 1 ether);
        vm.stopPrank();

        assertEq(t.balanceOf(alice), 10);
        assertEq(foreign.ownerOf(7), alice);
        assertEq(alice.balance, 1 ether);
    }
}
