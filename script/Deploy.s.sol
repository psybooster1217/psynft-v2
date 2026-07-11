// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Script.sol";
import {PsyNFTV2} from "../src/PsyNFTV2.sol";

/**
 * @notice Deploys PsyNFTV2 with the DEPLOYER as temporary owner (so it can script the
 *         migration), sets metadata + treasury (+ optional core), and prints next steps.
 *         Ownership is handed to the Gnosis Safe later via Handoff.s.sol.
 *
 * Env: PRIVATE_KEY, BASE_URI, NEW_TREASURY, [NEW_CORE]
 *
 * Testnet:  forge script script/Deploy.s.sol --rpc-url sepolia --broadcast --verify
 * Mainnet:  forge script script/Deploy.s.sol --rpc-url mainnet --broadcast --verify
 */
contract Deploy is Script {
    /// @dev Foundry's default script sender — broadcasting from it means no real signer
    ///      was configured, and it must never become the (temporary) owner.
    address internal constant FOUNDRY_DEFAULT_SENDER = 0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38;

    function run() external returns (PsyNFTV2 nft) {
        // Prefer a hardware wallet / keystore: leave PRIVATE_KEY unset and pass
        // `--account <name>` or `--ledger` (Foundry then supplies the signer). A raw
        // PRIVATE_KEY env var is supported as a fallback for testnets.
        uint256 pk = vm.envOr("PRIVATE_KEY", uint256(0));
        address deployer = pk != 0 ? vm.addr(pk) : msg.sender;
        require(
            deployer != FOUNDRY_DEFAULT_SENDER,
            "Deploy: no signer configured (set PRIVATE_KEY or pass --account/--ledger)"
        );
        string memory baseUri = vm.envOr("BASE_URI", string(""));
        address treasury = vm.envOr("NEW_TREASURY", address(0));
        address core = vm.envOr("NEW_CORE", address(0));

        // Loud warnings so a missing/misspelled env var can't silently ship a zero role.
        // (These are intentionally non-fatal: the trusted Safe owner can set them post-deploy,
        //  and neither is required by the migration itself.)
        if (treasury == address(0)) {
            console2.log("!! WARNING: NEW_TREASURY is UNSET -> treasury=0x0; burn() is unusable until set.");
        }
        if (core == address(0)) {
            console2.log("!! WARNING: NEW_CORE is UNSET -> core=0x0; minting/distribution is unusable until set.");
        }
        if (bytes(baseUri).length == 0) {
            console2.log("!! WARNING: BASE_URI is UNSET -> tokenURI returns a bare id; no art resolves until setBaseUri (docs/METADATA.md).");
        } else if (bytes(baseUri)[bytes(baseUri).length - 1] != "/") {
            console2.log("!! WARNING: BASE_URI has no trailing '/' -> tokenURI will be malformed (baseUri + id concatenation).");
        }

        if (pk != 0) vm.startBroadcast(pk);
        else vm.startBroadcast(); // signer comes from --account / --ledger
        nft = new PsyNFTV2(deployer);
        if (bytes(baseUri).length > 0) nft.setBaseUri(baseUri);
        if (treasury != address(0)) nft.setTreasury(treasury);
        if (core != address(0)) nft.setCoreContract(core);
        vm.stopBroadcast();

        console2.log("=====================================================");
        console2.log("PsyNFTV2 deployed:      ", address(nft));
        console2.log("temporary owner:        ", deployer);
        console2.log("treasury:               ", treasury);
        console2.log("core:                   ", core);
        console2.log("=====================================================");
        console2.log("NEXT: export PSYNFT_V2=%s", address(nft));
        console2.log("      then run: forge script script/Migrate.s.sol --broadcast");
    }
}
