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
 * Env: PRIVATE_KEY (current/temporary owner), PSYNFT_V2, SAFE_OWNER
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

        if (pk != 0) vm.startBroadcast(pk);
        else vm.startBroadcast(); // signer comes from --account / --ledger
        nft.transferOwnership(safe);
        vm.stopBroadcast();

        console2.log("Ownership transfer INITIATED to Safe:", safe);
        console2.log("pendingOwner:", nft.pendingOwner());
        console2.log("ACTION REQUIRED: the Safe must call acceptOwnership() to finalize.");
    }
}
