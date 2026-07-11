// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Test.sol";
import {PsyNFTV2} from "../src/PsyNFTV2.sol";

/**
 * @notice Validates snapshot/holders.json against the migration pipeline WITHOUT an RPC.
 *         Parses the committed snapshot with the same cheatcodes Migrate.s.sol uses, replays
 *         it into a fresh V2, and asserts holder parity + resumed counters. Catches any
 *         mismatch between the snapshot tool's JSON shape and the on-chain migration.
 */
contract HoldersJsonTest is Test {
    uint256 internal constant CHUNK = 50;
    address internal constant V1 = 0x6c6Ab7b3215374dE4A65De63eAC9BC7A0c7f402d;

    function test_ReplayCommittedSnapshot() public {
        string memory path = "snapshot/holders.json";
        try vm.readFile(path) returns (string memory json) {
            _replay(json);
        } catch {
            emit log("SKIP: snapshot/holders.json not present (run node snapshot/snapshot.mjs)");
            vm.skip(true);
        }
    }

    function _replay(string memory json) internal {
        uint256[] memory tokenIds = vm.parseJsonUintArray(json, ".tokenIds");
        address[] memory owners = vm.parseJsonAddressArray(json, ".owners");
        uint256 counter = vm.parseJsonUint(json, ".counter");
        uint256 prevFib = vm.parseJsonUint(json, ".previousFibonacci");
        bool controlled = vm.parseJsonBool(json, ".controlledTransfers");

        assertEq(tokenIds.length, owners.length, "parallel arrays");
        assertGt(tokenIds.length, 0, "non-empty");
        assertLe(tokenIds.length, counter, "live <= counter");

        PsyNFTV2 nft = new PsyNFTV2(address(this));

        // Repoint V1-held tokens to the new contract (same as Migrate.s.sol).
        for (uint256 i; i < owners.length; i++) {
            if (owners[i] == V1) owners[i] = address(nft);
            assertTrue(owners[i] != address(0), "no zero owner in snapshot");
        }

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
        // liveCount is written independently by the snapshot tool; it must equal what we migrated.
        uint256 liveCount = vm.parseJsonUint(json, ".liveCount");
        assertEq(liveCount, tokenIds.length, "liveCount matches array length");
        nft.finalizeMigration(counter, prevFib, controlled, liveCount);

        for (uint256 i; i < tokenIds.length; i++) {
            assertEq(nft.ownerOf(tokenIds[i]), owners[i], "holder parity");
        }
        assertEq(nft.tokenId(), counter, "resumed counter");
        assertEq(nft.previousFibonacci(), prevFib, "resumed prevFib");
        assertEq(nft.controlledTransfers(), controlled, "resumed controlled");
        assertTrue(nft.migrationFinalized(), "finalized");

        emit log_named_uint("replayed live holders", tokenIds.length);
    }
}
