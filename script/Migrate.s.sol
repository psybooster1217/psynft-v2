// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Script.sol";
import {PsyNFTV2} from "../src/PsyNFTV2.sol";

interface IPsyNFTV1Read {
    function tokenId() external view returns (uint256);
    function totalTokensBurnt() external view returns (uint256);
}

/**
 * @notice Replays the V1 holder snapshot (snapshot/holders.json) into a freshly deployed
 *         PsyNFTV2, then finalizes the migration so the Fibonacci schedule resumes.
 *
 * Prereqs:
 *   1. Run `node snapshot/snapshot.mjs` to produce snapshot/holders.json.
 *   2. Deploy V2 (Deploy.s.sol) and export PSYNFT_V2=<deployed address>.
 *
 * Env: PRIVATE_KEY (the temporary owner from Deploy), PSYNFT_V2, [V1_CONTRACT]
 *
 *   forge script script/Migrate.s.sol --rpc-url mainnet --broadcast
 */
contract Migrate is Script {
    uint256 internal constant CHUNK = 50; // holders per migrateBatch tx

    function run() external {
        // PRIVATE_KEY optional: leave unset and pass --account/--ledger to sign with a
        // hardware wallet or keystore instead of a raw key (see Deploy.s.sol).
        uint256 pk = vm.envOr("PRIVATE_KEY", uint256(0));
        PsyNFTV2 nft = PsyNFTV2(vm.envAddress("PSYNFT_V2"));
        address v1 = vm.envOr("V1_CONTRACT", address(0x6c6Ab7b3215374dE4A65De63eAC9BC7A0c7f402d));

        string memory json = vm.readFile("snapshot/holders.json");
        uint256[] memory tokenIds = vm.parseJsonUintArray(json, ".tokenIds");
        address[] memory owners = vm.parseJsonAddressArray(json, ".owners");
        uint256 counter = vm.parseJsonUint(json, ".counter");
        uint256 prevFib = vm.parseJsonUint(json, ".previousFibonacci");
        bool controlled = vm.parseJsonBool(json, ".controlledTransfers");
        uint256 liveCount = vm.parseJsonUint(json, ".liveCount");
        require(tokenIds.length == owners.length, "Migrate: length mismatch");
        require(tokenIds.length > 0, "Migrate: empty snapshot");
        // Guard against a truncated/hand-edited snapshot: the arrays must match the
        // independently-recorded live count. finalizeMigration enforces the same on-chain.
        require(tokenIds.length == liveCount, "Migrate: arrays truncated vs liveCount");

        // Pre-flight against LIVE V1 when reachable (mainnet). Skipped where V1 has no code
        // (e.g. the Sepolia rehearsal), where the committed snapshot is trusted as-is.
        try IPsyNFTV1Read(v1).tokenId() returns (uint256 liveCounter) {
            uint256 liveBurnt = IPsyNFTV1Read(v1).totalTokensBurnt();
            require(counter == liveCounter, "Migrate: snapshot counter != live V1");
            require(liveCount == liveCounter - liveBurnt, "Migrate: liveCount != live V1 live tokens");
            console2.log("preflight OK vs live V1 -> counter:", liveCounter);
        } catch {
            console2.log("V1 not reachable on this chain; using committed snapshot as-is");
        }

        // Undistributed V1-held tokens are re-pointed to the new contract for core to hand out.
        uint256 repointed;
        for (uint256 i; i < owners.length; i++) {
            if (owners[i] == v1) {
                owners[i] = address(nft);
                repointed++;
            }
        }

        console2.log("migrating %s tokens (%s repointed to V2)", tokenIds.length, repointed);

        if (pk != 0) vm.startBroadcast(pk);
        else vm.startBroadcast(); // signer comes from --account / --ledger
        for (uint256 start; start < tokenIds.length; start += CHUNK) {
            uint256 end = start + CHUNK > tokenIds.length ? tokenIds.length : start + CHUNK;
            uint256 len = end - start;
            address[] memory hb = new address[](len);
            uint256[] memory ib = new uint256[](len);
            for (uint256 i; i < len; i++) {
                hb[i] = owners[start + i];
                ib[i] = tokenIds[start + i];
            }
            nft.migrateBatch(hb, ib);
        }
        nft.finalizeMigration(counter, prevFib, controlled, liveCount);
        vm.stopBroadcast();

        console2.log("=====================================================");
        console2.log("Migration finalized.");
        console2.log("tokenId (resume):       ", nft.tokenId());
        console2.log("previousFibonacci:      ", nft.previousFibonacci());
        console2.log("controlledTransfers:    ", nft.controlledTransfers());
        console2.log("=====================================================");
        console2.log("NEXT: run Handoff.s.sol to transfer ownership to the Safe.");
    }
}
