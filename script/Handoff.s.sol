// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Script.sol";
import {PsyNFTV2} from "../src/PsyNFTV2.sol";

/**
 * @notice Transfers ownership from the temporary deployer to the Gnosis Safe.
 *         Uses Ownable2Step: this only *initiates* the transfer. The Safe must then call
 *         `acceptOwnership()` (e.g. via the Safe UI / Transaction Builder) to complete it.
 *         Until the Safe accepts, the deployer remains owner (safe against fat-fingering).
 *
 *         Before handing over, it checks the state the Safe is about to inherit (audit 2026-10,
 *         final review N8): migration finalized, every snapshot seat owned by its snapshot holder,
 *         and no transfer approval set on any id. The temporary deployer could otherwise leave an
 *         approval behind that survives the handoff.
 *
 * Env: PRIVATE_KEY (current/temporary owner), PSYNFT_V2, SAFE_OWNER, [V1_CONTRACT]
 *
 *   forge script script/Handoff.s.sol --rpc-url mainnet --broadcast
 */
contract Handoff is Script {
    function run() external {
        // PRIVATE_KEY optional: leave unset and pass --account/--ledger to sign with a
        // hardware wallet or keystore instead of a raw key (see Deploy.s.sol).
        uint256 pk = vm.envOr("PRIVATE_KEY", uint256(0));
        PsyNFTV2 nft = PsyNFTV2(vm.envAddress("PSYNFT_V2"));
        address safe = vm.envAddress("SAFE_OWNER");
        require(safe != address(0), "Handoff: SAFE_OWNER unset");

        _checkInheritedState(nft);

        if (pk != 0) vm.startBroadcast(pk);
        else vm.startBroadcast(); // signer comes from --account / --ledger
        nft.transferOwnership(safe);
        vm.stopBroadcast();

        console2.log("Ownership transfer INITIATED to Safe:", safe);
        console2.log("pendingOwner:", nft.pendingOwner());
        console2.log("ACTION REQUIRED: the Safe must call acceptOwnership() to finalize.");
    }

    /// Reverts unless the contract is exactly what the snapshot says, with no leftover approvals.
    function _checkInheritedState(PsyNFTV2 nft) internal view {
        require(nft.migrationFinalized(), "Handoff: migration not finalized");

        string memory json = vm.readFile("snapshot/holders.json");
        uint256[] memory ids = vm.parseJsonUintArray(json, ".tokenIds");
        address[] memory owners = vm.parseJsonAddressArray(json, ".owners");
        address v1 = vm.envOr("V1_CONTRACT", address(0x6c6Ab7b3215374dE4A65De63eAC9BC7A0c7f402d));
        for (uint256 i; i < ids.length; i++) {
            address want = owners[i] == v1 ? address(nft) : owners[i]; // V1-held seats were re-pointed
            require(nft.ownerOf(ids[i]) == want, string.concat("Handoff: owner mismatch for id ", vm.toString(ids[i])));
        }

        uint256 next = nft.tokenId();
        for (uint256 id; id < next; id++) {
            (, uint256 expiry,) = nft.approvedTransfers(id);
            require(expiry == 0, string.concat("Handoff: transfer approval set on id ", vm.toString(id)));
        }
        console2.log("pre-handoff check OK: %s snapshot seats match, no approvals on ids 0..%s", ids.length, next - 1);
    }
}
