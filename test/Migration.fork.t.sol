// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Test.sol";
import {PsyNFTV2} from "../src/PsyNFTV2.sol";

interface IPsyNFTV1 {
    function tokenId() external view returns (uint256);
    function ownerOf(uint256) external view returns (address);
    function totalTokensBurnt() external view returns (uint256);
    function previousFibonacci() external view returns (uint256);
    function controlledTransfers() external view returns (bool);
}

/**
 * @notice End-to-end migration validation against the LIVE mainnet PsyNFT.
 *
 * Forks mainnet, snapshots the real `ownerOf` of every V1 token, deploys V2, replays the
 * migration exactly as the production script will, and asserts holder-for-holder parity plus
 * a correct resume of the Fibonacci schedule.
 *
 * Requires MAINNET_RPC_URL. If unset, the whole suite is skipped (so CI without an RPC is green).
 * Run explicitly:  MAINNET_RPC_URL=... forge test --match-path test/Migration.fork.t.sol -vv
 */
contract MigrationForkTest is Test {
    address internal constant V1 = 0x6c6Ab7b3215374dE4A65De63eAC9BC7A0c7f402d;

    IPsyNFTV1 internal v1;
    PsyNFTV2 internal v2;
    bool internal enabled;

    function setUp() public {
        string memory url = vm.envOr("MAINNET_RPC_URL", string(""));
        if (bytes(url).length == 0) {
            enabled = false;
            return;
        }
        // Optional pin for reproducibility: set FORK_BLOCK to a specific block.
        uint256 pin = vm.envOr("FORK_BLOCK", uint256(0));
        if (pin == 0) {
            vm.createSelectFork(url);
        } else {
            vm.createSelectFork(url, pin);
        }
        enabled = true;
        v1 = IPsyNFTV1(V1);
        v2 = new PsyNFTV2(address(this)); // this test acts as the temporary deployer/owner
    }

    function test_MigrationParityWithMainnet() public {
        if (!enabled) {
            emit log("SKIP: set MAINNET_RPC_URL to run the fork migration test");
            vm.skip(true);
            return;
        }

        uint256 counter = v1.tokenId(); // ids 0..counter-1 were ever minted
        assertGt(counter, 0, "v1 counter");

        // 1. Snapshot every still-existing V1 token and its owner.
        address[] memory holders = new address[](counter);
        uint256[] memory ids = new uint256[](counter);
        uint256 n; // number of live tokens
        uint256 burnt;
        for (uint256 id; id < counter; id++) {
            try v1.ownerOf(id) returns (address o) {
                // Undistributed tokens (held by the V1 contract) go to the NEW contract so
                // the new core can re-distribute them. Everything else maps 1:1.
                holders[n] = (o == V1) ? address(v2) : o;
                ids[n] = id;
                n++;
            } catch {
                burnt++; // ownerOf reverts for burnt ids -> simply omitted from the migration
            }
        }

        emit log_named_uint("v1 counter (tokenId)", counter);
        emit log_named_uint("live tokens migrated", n);
        emit log_named_uint("burnt/omitted", burnt);
        assertEq(n + burnt, counter, "accounting");
        assertEq(burnt, v1.totalTokensBurnt(), "burnt count matches V1");

        // Trim arrays to length n.
        assembly {
            mstore(holders, n)
            mstore(ids, n)
        }

        // 2. Replay migration exactly as the production script (chunked in batches of 50).
        uint256 CHUNK = 50;
        for (uint256 start; start < n; start += CHUNK) {
            uint256 end = start + CHUNK > n ? n : start + CHUNK;
            uint256 len = end - start;
            address[] memory hb = new address[](len);
            uint256[] memory ib = new uint256[](len);
            for (uint256 i; i < len; i++) {
                hb[i] = holders[start + i];
                ib[i] = ids[start + i];
            }
            v2.migrateBatch(hb, ib);
        }

        // 3. Finalize at the live V1 counters so the schedule resumes seamlessly.
        //    expectedCount is derived independently from V1 (tokenId - totalTokensBurnt).
        uint256 expectedCount = counter - v1.totalTokensBurnt();
        assertEq(expectedCount, n, "independent live-count matches snapshot");
        v2.finalizeMigration(counter, v1.previousFibonacci(), v1.controlledTransfers(), expectedCount);

        // 4. Assert holder-for-holder parity.
        for (uint256 i; i < n; i++) {
            assertEq(v2.ownerOf(ids[i]), holders[i], "owner parity");
        }
        // Burnt ids must NOT exist in V2.
        for (uint256 id; id < counter; id++) {
            bool live;
            for (uint256 i; i < n; i++) {
                if (ids[i] == id) {
                    live = true;
                    break;
                }
            }
            if (!live) {
                vm.expectRevert();
                v2.ownerOf(id);
            }
        }

        // 5. Counters resumed.
        assertEq(v2.tokenId(), counter, "resumed tokenId");
        assertEq(v2.previousFibonacci(), v1.previousFibonacci(), "resumed prevFib");
        assertEq(v2.controlledTransfers(), v1.controlledTransfers(), "resumed controlled flag");
        assertTrue(v2.migrationFinalized(), "finalized");

        // 6. The schedule continues: wire a core and mint the next Fibonacci batch.
        address core = makeAddr("newCore");
        v2.setCoreContract(core);
        uint256 expectedBatch = v1.previousFibonacci(); // next batch size
        uint256 before = v2.tokenId();
        vm.prank(core);
        v2.batchMintInFibonacci();
        assertEq(v2.tokenId(), before + expectedBatch, "next batch size");
        for (uint256 id = before; id < before + expectedBatch; id++) {
            assertEq(v2.ownerOf(id), address(v2), "new tokens held by contract");
        }
    }
}
