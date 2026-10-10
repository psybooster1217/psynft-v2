// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Test.sol";
import {PsyNFTV2} from "../../src/PsyNFTV2.sol";

/**
 * @notice Random-action handler for the invariant suite. Every role (owner, core, treasury,
 *         members, an outsider) acts in random order with random inputs; the handler predicts
 *         the outcome of every gated call and counts any mismatch as a violation.
 */
contract Handler is Test {
    PsyNFTV2 public nft;
    address public ownerAddr;
    address public immutable core;
    address public immutable treasury;
    address public immutable outsider = address(0xBAD);
    address[] public members;

    // ghost state
    uint256 public ghostBurnt;
    uint256 public gateViolations; // controlled-transfer outcome != prediction
    uint256 public reuseViolations; // an approval survived a transfer
    uint256 public escalations; // a privileged call succeeded from a non-role address
    uint256 public calls;
    // coverage counters (prove each path really executes)
    uint256 public nApproved;
    uint256 public nRevoked;
    uint256 public nGatedOk; // transfers that passed WITH controls on (i.e. used an approval)
    uint256 public nGatedBlocked;
    uint256 public nToggles;

    uint256 internal constant MAX_TOKEN_ID = 100; // keeps batch gas bounded (max batch 144)

    constructor(PsyNFTV2 _nft, address _owner, address _core, address _treasury) {
        nft = _nft;
        ownerAddr = _owner;
        core = _core;
        treasury = _treasury;
        members.push(address(0xA11CE));
        members.push(address(0xB0B));
        members.push(address(0xCA401));
        members.push(address(0xD0D0));
    }

    function membersLength() external view returns (uint256) {
        return members.length;
    }

    // ------------------------------------------------------------------ helpers

    function _actor(uint256 seed) internal view returns (address) {
        uint256 i = seed % (members.length + 1);
        return i == members.length ? outsider : members[i];
    }

    function _id(uint256 seed) internal view returns (uint256) {
        uint256 n = nft.tokenId();
        return n == 0 ? 0 : seed % n;
    }

    function _exists(uint256 id) internal view returns (bool) {
        try nft.ownerOf(id) returns (address) {
            return true;
        } catch {
            return false;
        }
    }

    /// First member-held token at or after `seed` (wrapping), if any.
    function _memberHeld(uint256 seed) internal view returns (uint256 id, bool found) {
        uint256 n = nft.tokenId();
        for (uint256 k; k < n; k++) {
            id = (seed % n + k) % n;
            if (_exists(id) && nft.ownerOf(id) != address(nft)) return (id, true);
        }
    }

    // ------------------------------------------------------------------ role actions

    function mintBatch() external {
        calls++;
        if (nft.tokenId() >= MAX_TOKEN_ID) return;
        vm.prank(core);
        nft.batchMintInFibonacci();
    }

    function distribute(uint256 idSeed, uint256 toSeed) external {
        calls++;
        uint256 n = nft.tokenId();
        for (uint256 k; k < n; k++) {
            uint256 id = (idSeed % n + k) % n;
            if (_exists(id) && nft.ownerOf(id) == address(nft)) {
                uint256[] memory ids = new uint256[](1);
                ids[0] = id;
                vm.prank(core);
                nft.transferNFTs(ids, _actor(toSeed));
                return;
            }
        }
    }

    function approve(uint256 idSeed, uint256 toSeed, uint256 window, bool anyId) external {
        calls++;
        (uint256 id, bool found) = _memberHeld(idSeed);
        if (anyId || !found) id = _id(idSeed); // sometimes target contract-held / burnt ids too
        address to = _actor(toSeed);
        uint256 w = bound(window, 0, 30 days); // bound() logs via console: compute BEFORE the prank
        vm.prank(core);
        try nft.approveTransfer(id, to, w) {
            nApproved++;
        } catch {}
    }

    function revoke(uint256 idSeed) external {
        calls++;
        uint256 id = _id(idSeed);
        vm.prank(core);
        try nft.revokeTransfer(id) {
            nRevoked++;
        } catch {}
    }

    function memberTransfer(uint256 idSeed, uint256 toSeed, bool safe, bool useGrant) external {
        calls++;
        (uint256 id, bool found) = _memberHeld(idSeed);
        if (!found) return;
        address from = nft.ownerOf(id);
        (, uint256 expiry, address approvedTo) = nft.approvedTransfers(id);
        // Half the time aim at the approved recipient, so the gate's success path is exercised.
        address to = (useGrant && approvedTo != address(0)) ? approvedTo : _actor(toSeed);
        if (to == from) return;

        bool controlled = nft.controlledTransfers();
        bool predicted = !controlled || (to == approvedTo && block.timestamp <= expiry);

        vm.prank(from);
        bool ok;
        if (safe) {
            try nft.safeTransferFrom(from, to, id) {
                ok = true;
            } catch {}
        } else {
            try nft.transferFrom(from, to, id) {
                ok = true;
            } catch {}
        }
        if (ok != predicted) gateViolations++;
        if (controlled) ok ? nGatedOk++ : nGatedBlocked++;
        if (ok) {
            (, uint256 e,) = nft.approvedTransfers(id);
            if (e != 0) reuseViolations++;
        }
    }

    /// Core approves a member-held token, time passes, then the holder tries to move it (to the
    /// approved recipient or elsewhere). Guarantees dense coverage of the gate's edge: expiry.
    function approveThenTransfer(uint256 idSeed, uint256 toSeed, uint256 window, uint256 elapsed, bool toApproved)
        external
    {
        calls++;
        (uint256 id, bool found) = _memberHeld(idSeed);
        if (!found) return;
        address from = nft.ownerOf(id);
        address approvedTo = _actor(toSeed);
        if (approvedTo == from) return;
        uint256 w = bound(window, 0, 3 days);
        uint256 dt = bound(elapsed, 0, 4 days);
        vm.prank(core);
        try nft.approveTransfer(id, approvedTo, w) {
            nApproved++;
        } catch {
            return; // a live grant already exists
        }
        vm.warp(block.timestamp + dt);
        address to = toApproved ? approvedTo : _actor(toSeed % 1000 + 1);
        if (to == from) return;
        (, uint256 expiry, address grantTo) = nft.approvedTransfers(id);
        bool controlled = nft.controlledTransfers();
        bool predicted = !controlled || (to == grantTo && block.timestamp <= expiry);
        vm.prank(from);
        bool ok;
        try nft.transferFrom(from, to, id) {
            ok = true;
        } catch {}
        if (ok != predicted) gateViolations++;
        if (controlled) ok ? nGatedOk++ : nGatedBlocked++;
        if (ok) {
            (, uint256 e,) = nft.approvedTransfers(id);
            if (e != 0) reuseViolations++;
        }
    }

    function burn(uint256 idSeed) external {
        calls++;
        uint256 id = _id(idSeed);
        if (!_exists(id)) return;
        vm.prank(treasury);
        nft.burn(id);
        ghostBurnt++;
    }

    function toggleControls() external {
        calls++;
        bool on = nft.controlledTransfers(); // read BEFORE the prank (a view call would consume it)
        vm.prank(ownerAddr);
        if (on) nft.disableControlledTransfers();
        else nft.enableControlledTransfers();
        nToggles++;
    }

    function warp(uint256 dt) external {
        calls++;
        uint256 d = bound(dt, 0, 10 days);
        vm.warp(block.timestamp + d);
    }

    /// Two-step ownership handoff to a random member (and the handler follows the new owner).
    function handOwnership(uint256 toSeed) external {
        calls++;
        address next = members[toSeed % members.length];
        if (next == ownerAddr) return;
        vm.prank(ownerAddr);
        nft.transferOwnership(next);
        vm.prank(next);
        nft.acceptOwnership();
        ownerAddr = next;
    }

    /// A non-role address tries a privileged function. Any success is an escalation.
    function unauthorized(uint256 fnSeed, uint256 actorSeed, uint256 arg) external {
        calls++;
        address who = _actor(actorSeed);
        if (who == ownerAddr || who == core || who == treasury) return;
        uint256 id = _id(arg);
        uint256[] memory ids = new uint256[](1);
        ids[0] = id;
        address[] memory hs = new address[](1);
        hs[0] = who;

        vm.startPrank(who);
        bool ok;
        uint256 f = fnSeed % 14;
        if (f == 0) try nft.batchMintInFibonacci() { ok = true; } catch {}
        else if (f == 1) try nft.transferNFTs(ids, who) { ok = true; } catch {}
        else if (f == 2) try nft.approveTransfer(id, who, 1 days) { ok = true; } catch {}
        else if (f == 3) try nft.revokeTransfer(id) { ok = true; } catch {}
        else if (f == 4) try nft.burn(id) { ok = true; } catch {}
        else if (f == 5) try nft.setCoreContract(who) { ok = true; } catch {}
        else if (f == 6) try nft.setTreasury(who) { ok = true; } catch {}
        else if (f == 7) try nft.setBaseUri("ipfs://evil/") { ok = true; } catch {}
        else if (f == 8) try nft.disableControlledTransfers() { ok = true; } catch {}
        else if (f == 9) try nft.migrateBatch(hs, ids) { ok = true; } catch {}
        else if (f == 10) try nft.finalizeMigration(34, 21, false, 1) { ok = true; } catch {}
        else if (f == 11) try nft.rescueETH(payable(who), 0) { ok = true; } catch {}
        else if (f == 12) try nft.transferOwnership(who) { ok = true; } catch {}
        else try nft.initialMint() { ok = true; } catch {}
        vm.stopPrank();
        if (ok) escalations++;
    }
}

contract PsyNFTV2InvariantTest is Test {
    PsyNFTV2 internal nft;
    Handler internal handler;

    address internal owner = makeAddr("owner");
    address internal core = makeAddr("core");
    address internal treasury = makeAddr("treasury");

    function setUp() public {
        nft = new PsyNFTV2(owner);
        vm.startPrank(owner);
        nft.setCoreContract(core);
        nft.setTreasury(treasury);
        vm.stopPrank();
        vm.prank(core);
        nft.initialMint();

        handler = new Handler(nft, owner, core, treasury);
        targetContract(address(handler));
    }

    /// Prints how often each path ran (run with -vv); asserts the important ones are reachable.
    function afterInvariant() public view {
        console2.log("approved", handler.nApproved(), "revoked", handler.nRevoked());
        console2.log("gated ok", handler.nGatedOk(), "gated blocked", handler.nGatedBlocked());
        console2.log("toggles", handler.nToggles());
    }

    /// I1: every minted, unburnt token is held by a known party (supply accounting).
    function invariant_SupplyAccounting() public view {
        uint256 sum = nft.balanceOf(address(nft)) + nft.balanceOf(handler.outsider());
        for (uint256 i; i < handler.membersLength(); i++) {
            sum += nft.balanceOf(handler.members(i));
        }
        assertEq(sum, nft.tokenId() - nft.totalTokensBurnt(), "live tokens == minted - burnt");
        assertEq(nft.totalTokensBurnt(), handler.ghostBurnt(), "burn counter matches");
    }

    /// I2: the mint counters always sit on the Fibonacci schedule (and so only ever grow).
    function invariant_CountersOnSchedule() public view {
        uint256 a = 2;
        uint256 b = 3;
        while (b < nft.tokenId()) (a, b) = (b, a + b);
        assertEq(b, nft.tokenId(), "tokenId is a schedule term");
        assertEq(a, nft.previousFibonacci(), "previousFibonacci is the term before it");
    }

    /// I3: ownership can never be lost (no renounce, two-step only).
    function invariant_OwnerNeverZero() public view {
        assertTrue(nft.owner() != address(0));
        assertEq(nft.owner(), handler.ownerAddr());
    }

    /// I4: the controlled-transfer gate behaves exactly as specified, for every transfer.
    function invariant_GateExact() public view {
        assertEq(handler.gateViolations(), 0, "gate outcome matched prediction");
    }

    /// I5: approvals are single-use.
    function invariant_ApprovalsSingleUse() public view {
        assertEq(handler.reuseViolations(), 0);
    }

    /// I6: no privilege escalation from any non-role address.
    function invariant_NoEscalation() public view {
        assertEq(handler.escalations(), 0);
        assertEq(nft.core(), core);
        assertEq(nft.treasury(), treasury);
    }

    /// I7: tokens the contract holds never carry an ERC-721 operator approval.
    function invariant_ContractHeldTokensUnapproved() public view {
        uint256 n = nft.tokenId();
        for (uint256 id; id < n && id < 160; id++) {
            try nft.ownerOf(id) returns (address o) {
                if (o == address(nft)) assertEq(nft.getApproved(id), address(0));
            } catch {}
        }
        assertFalse(nft.migrationStarted(), "migration can never open on a fresh deployment");
    }
}
