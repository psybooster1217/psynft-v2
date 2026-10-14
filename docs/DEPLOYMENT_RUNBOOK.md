# Deployment runbook

A step‑by‑step, reversible‑where‑possible sequence to test and deploy PsyNFT V2 and migrate the 33
holders, then winds down the V1 exit pool into the Main Safe. **Rehearse on a mainnet fork before
touching mainnet:** the real-Safe rehearsal (§0 gate) replaces a Sepolia rehearsal, and §2 dry-runs
the deploy scripts on a local fork.

Addresses used below (mainnet):

| Name | Address | Admin |
|---|---|---|
| V1 PsyNFT | `0x6c6Ab7b3215374dE4A65De63eAC9BC7A0c7f402d` | former operator wallet `0xC3aC…e445` (not the DAO), moves to Main Safe in §0a |
| V1 PsycSale (proxy) | `0xe94828A923538709c58764159D6CD99C4381d82B` | `0x00c1…6061` (Steven, a single wallet), moves to Main Safe in §0b |
| V1 CoreLogic (proxy) | `0xDAAAC6a81fE6a230B880b96a2B5ca903d0c1d4F6` | `0x00c1…6061` (Steven, a single wallet), moves to Main Safe in §0b |
| V1 Treasury (exit pool) | `0xB4528213285CD10Fdb6a14847a398d71670b3d61` | Main Safe |
| Main Treasury Safe (2‑of‑4, v1.3.0) | `0xB253a1Ab24B612C2AF37f8fC935b40c7304650e5` | n/a |

Order of events (the same sequence as the holder brief, the README and the bug bounty):

1. Step 0 + §0a/§0b: the V1 contracts move to the Main Safe.
2. The bug bounty runs (21 days) on the reviewed code.
3. PSYC vote (exit window dates, the switch-over, the Safe's powers).
4. Exit window (V1 ego death stays on).
5. Freeze (§1) and holder snapshot.
6. V2 deployed, seats migrated, the Safe accepts ownership (§4a–§4c).
7. Switch-over transaction §4d, only if no Critical or High bounty report is open.
8. Snapshot voting and marketplaces switch to V2 (§5).

> Legend: 🧪 test‑only · 🔴 mainnet/irreversible · ✅ verification gate

---

## 0. Prerequisites

- [ ] Foundry installed (`forge --version`). Deps are vendored under `lib/` (OpenZeppelin v5.0.2, forge‑std).
- [ ] `.env` created from `.env.example` and filled in. **Never commit `.env`.**
- [ ] A mainnet RPC endpoint (Alchemy/Infura/your node), archive-capable for the fork tests.
- [ ] `ETHERSCAN_API_KEY` for source verification.
- [ ] A funded **deployer** key (temporary owner). Prefer a hardware wallet / keystore; a raw
      `PRIVATE_KEY` is acceptable only on a local fork or testnet.
- [ ] The **Gnosis Safe** that will own V2 (create at <https://app.safe.global> if needed). Put its
      address in `SAFE_OWNER`.
- [ ] The **core** and **treasury** addresses you control for V2 (`NEW_CORE`, `NEW_TREASURY`).
- [ ] **Metadata re-pinned (audit 2026-10, META-1).** V1's metadata host no longer exists. Follow
      [metadata/README.md](../metadata/README.md): pin `metadata/psyc-metadata-v2.car` and the six image
      folders on two services, then `node metadata/verify-pinned.mjs` must print `ALL 34 OK` via two
      gateways (the default `https://gateway.pinata.cloud/ipfs/` and `https://ipfs.filebase.io/ipfs/`;
      ipfs.io and dweb.link no longer serve path requests). `BASE_URI` = `ipfs://<that CID>/` (already
      in `.env.example`). The contract rejects a URI without the trailing `/`.

✅ Gate: `forge test --no-match-path "test/*.fork.t.sol"` is green (unit, fuzz, invariants), and
`MAINNET_RPC_URL=… forge test --match-path "test/*.fork.t.sol" -vv` passes. The second covers:
- the migration (`Migration.fork.t.sol`);
- the cutover + exit-pool sweep (`CutoverSweep.fork.t.sol`);
- **the whole cutover executed through the real Main Safe contract**, from Step 0 to §4d, with its
  real 2-of-4 threshold and its owners' addresses, via MultiSendCallOnly and the exact batch bytes
  signers will import (`SafeRehearsal.fork.t.sol`). This is a simulation on a mainnet fork
  (approved-hash signatures); no signer signs anything. It replaces a Sepolia rehearsal.

The RPC must serve historical state (an archive-capable endpoint); `eth.drpc.org` works.

### Generating the Safe batches (every Safe step below)

Every Main Safe transaction in this runbook is generated, not hand-typed:

```bash
forge script script/SafeBatches.s.sol --rpc-url mainnet                     # Step 0 list + §0a, §0b, §1
PSYNFT_V2=0x… forge script script/SafeBatches.s.sol --rpc-url mainnet       # + §4c + §4d
```

This writes two kinds of file:
- `safe-batches/*.json` (`0a-accept-v1-nft.json`, `0b-setup.json`, `1-freeze.json`, then
  `4c-accept-v2.json`, `4d-cutover-sweep.json`): load these in Safe → Apps → Transaction Builder.
- `safe-batches/CHECKLIST.md`: lists the Step 0 wallet transactions, every Safe call and the
  **expected safeTxHash** at the current Safe nonce. Before signing, each signer checks that the hash
  on their hardware wallet equals the one in the checklist.

Expected Safe nonces in the current checklist: §0a = 141, §0b = 142, §1 = 143. §4c (144) and
§4d (145) are generated once `PSYNFT_V2` is set. The batches assume this order and consecutive
nonces.

The bytes come from `script/lib/CutoverCalls.sol`, the same library the real-Safe rehearsal executes.
Re-run the script if the Safe executes anything else in between (or if §0b has to go before §0a),
because the nonces change.

---

## Step 0, §0a, §0b. Move the V1 contracts to the Main Safe 🔴 (first: before the bounty and the vote)

Three V1 contracts are still owned by individual wallets, not by the DAO:
- V1 PsyNFT is still owned by a former operator wallet (`0xC3aC…e445`). Until Step 0 and §0a hand it
  to the Main Safe, V1's admin functions are outside DAO control.
- CoreLogic and PsycSale are owned by one individual's wallet (`0x00c1…6061`). Step 0 and §0b hand
  them to the Main Safe, so that no single key controls the exit machinery.

Those keys must not sit with individuals. None of these changes touches holders. Each handover is
two-step (Ownable2Step): nothing changes until the Safe accepts.

1. **Step 0 (individual wallets, not the Safe).** Exact targets and calldata are in
   `safe-batches/CHECKLIST.md`:
   ```
   from 0xC3aC5Ef1A15c40241233C722FE322D83B010e445:  V1 PsyNFT.transferOwnership(0xB253a1Ab24B612C2AF37f8fC935b40c7304650e5)
   from 0x00c15f6db575ef6ef7814d4900507eC4B3276061:  CoreLogic.transferOwnership(0xB253a1Ab24B612C2AF37f8fC935b40c7304650e5)
   from 0x00c15f6db575ef6ef7814d4900507eC4B3276061:  PsycSale.transferOwnership(0xB253a1Ab24B612C2AF37f8fC935b40c7304650e5)
   ```
2. **§0a, Safe batch `safe-batches/0a-accept-v1-nft.json`** (nonce 141), one call:
   `V1 PsyNFT.acceptOwnership()`. Run it as soon as the former operator wallet has started its
   handover. It is separate from §0b because it depends on a different wallet.
3. **§0b, Safe batch `safe-batches/0b-setup.json`** (nonce 142), three calls:
   - `CoreLogic.acceptOwnership()`;
   - `PsycSale.acceptOwnership()`;
   - `Safe.setFallbackHandler(0xf48f2B2d2a534e402487b3ee7C18c33Aec0Fe5e4)`: the canonical v1.3.0
     CompatibilityFallbackHandler, verified against the safe-deployments registry.

   The Main Safe has no fallback handler today, so it cannot receive an ERC‑721 through
   `safeTransfer`. `transferNFTs` uses `_safeTransfer`, so §4d would revert without it. That revert is
   atomic, so nothing changes (proven by `test_SweepBatchIsAtomic`).

After §0a and §0b the Safe owns V1 PsyNFT, CoreLogic, PsycSale and the V1 Treasury.

✅ Gate (owner == Main Safe for all three contracts):
- [ ] `cast call 0x6c6A…402d "owner()(address)"` returns the Main Safe (V1 PsyNFT).
- [ ] `cast call 0xDAAA…d4F6 "owner()(address)"` returns the Main Safe (CoreLogic).
- [ ] `cast call 0xe948…d82B "owner()(address)"` returns the Main Safe (PsycSale).
- [ ] `cast storage 0xB253…50e5 0x6c9a6c4a39284e37ed1cf53d337577d14212a4870fb976a4366c693b939918d5`
      returns the handler address.

### Exit window

From the day the PDP passes until the freeze in §1, V1 ego death stays **on**. Any legacy holder may
exit on V1 as today (`CoreLogic.rageQuit(id)`, then `Treasury.withdrawUserFunds()`) and receive
`pool ÷ live seats`. Announce the window and its closing date with the PDP result. Seats exited in
the window are burned on V1 and are simply not migrated (the snapshot and `finalizeMigration`
completeness check already handle burns).

---

## 1. Freeze the snapshot 🔴 (decide a block)

The holder set can change until V1 is truly inactive. First close the exit window, then pin a block
so the snapshot is reproducible.

```
Safe batch safe-batches/1-freeze.json:  CoreLogic.switchRageQuit()        // rageQuitAllowed -> false
```

> ⚠️ `switchRageQuit` is a **toggle** (audit 2026-10, OPS-03). Check `rageQuitAllowed() == true`
> before signing and execute it **exactly once**. A second execution re-opens ego death (pinned by
> `test_FreezeBatchIsAToggle`).

Use `switchRageQuit`, **not** `Treasury.pause()`: pausing would also block `withdrawUserFunds`, so
holders who exited in the window (and the token‑0 exiter, owed 0.0943 ETH) could not collect.

✅ Gate: `cast call 0xDAAA…d4F6 "rageQuitAllowed()(bool)"` returns `false`.

```bash
# Pin the latest block (or choose one after which no V1 transfers should count).
# --verify-rpc is REQUIRED for the production snapshot: every owner is re-read from an
# INDEPENDENT second provider and the run aborts on any mismatch (see docs/AUDIT.md, SNAP-2).
export MAINNET_RPC_URL=https://your-mainnet-rpc          # provider A (e.g. Alchemy)
node snapshot/snapshot.mjs --block latest --verify-rpc https://ethereum-rpc.publicnode.com   # provider B
git add snapshot/holders.json && git commit -m "freeze holder snapshot @ <block>"
```

✅ Gate: `forge test --match-path test/HoldersJson.t.sol -vv` passes (parity on the committed file).
Review `holders.json` by eye: `counter`, `burnt`, and `tokenIds.length` should match Etherscan's
holder count. Cross‑check a few `owners` against the Etherscan holders tab.

> If holders can still move V1 tokens, plan a short comms window: "snapshot at block N; transfers
> after N won't carry to V2." Because V1 transfers are controlled, in practice the set is stable.

---

## 2. Dry run on a local mainnet fork 🧪 (no Sepolia gate)

There is no Sepolia rehearsal: the real-Safe rehearsal on a mainnet fork (§0 gate) replaces it,
because it executes the exact Safe batches against live state. Before mainnet, also run the deploy
scripts once against a local anvil fork of mainnet, so the checks below run on the same scripts and
snapshot. Nothing is broadcast to mainnet. Sign with an anvil dev key (a public test key; never use
it on a real network).

```bash
source .env
# in a second terminal: anvil --fork-url <your mainnet RPC>
export RPC=http://127.0.0.1:8545
export PRIVATE_KEY=<anvil account #0 key, printed by anvil at start>

# 2a. Deploy (deployer = temporary owner)
forge script script/Deploy.s.sol --rpc-url $RPC --broadcast
# → note the deployed address; set it:
export PSYNFT_V2=0xDEPLOYED_ADDRESS

# 2b. Migrate the committed snapshot + finalize
forge script script/Migrate.s.sol --rpc-url $RPC --broadcast

# 2c. Hand off to the Safe (pre-handoff check, then initiates the Ownable2Step transfer)
forge script script/Handoff.s.sol --rpc-url $RPC --broadcast
# → accept as the Main Safe on the fork by impersonation (anvil_impersonateAccount, or the
#   admin UI's "Act as": docs/TESTING_HANDBOOK.md Part F)
```

✅ Gates (via `cast` against `$RPC`):
- [ ] `tokenId() == 34`, `previousFibonacci() == 21`, `controlledTransfers() == true`,
      `migrationFinalized() == true`.
- [ ] Spot‑check `ownerOf(id)` for several ids equals the snapshot owner.
- [ ] `ownerOf(0)` **reverts** (burnt id not re‑minted).
- [ ] **Art:** `tokenURI(5)` returns
      `ipfs://bafybeib2aqk4vcfbpgs7aoyk6z6pk5zfcli6qjuvuqohdsdriexeji6m3i/5` (the re-pinned CID-v2).
      It deliberately differs from V1's `tokenURI`, whose host no longer exists (META-1): never
      redeploy with V1's URL to make them match. The image resolves (admin UI → **Art / metadata
      preview**), and `node metadata/verify-pinned.mjs` prints `ALL 34 OK`.
      `cast call $PSYNFT_V2 "tokenURI(uint256)(string)" 5 --rpc-url $RPC`. See [METADATA.md](METADATA.md).
- [ ] `owner()` is still the deployer; `pendingOwner()` is the Safe — until the Safe accepts, then
      `owner()` is the Safe and `pendingOwner()` is zero.
- [ ] From the Safe, `setCoreContract`/`setTreasury` succeed; from any other address they revert.
- [ ] `batchMintInFibonacci` (called by `core`) mints 21 tokens (ids 34–54) to the contract.

Stop anvil, fix anything, and only then proceed.

---

## 3. Audit and bug bounty ✅ (before mainnet value)

- [x] Internal, AI-assisted audit 2026-10 complete (carried out by the proposer with substantial AI
      assistance); all findings fixed or accepted: [AUDIT-2026-10.md](AUDIT-2026-10.md).
- [ ] The bug bounty ([BUG_BOUNTY.md](BUG_BOUNTY.md), [SECURITY.md](../SECURITY.md)) has run its
      21-day window on the reviewed code (after §0a/§0b, before the PSYC vote), and no Critical or
      High report is open. §4d executes only then. Rewards are proposed, pending approval by 2 Main
      Safe signers: up to $2,500, $5,000 total, paid in ETH or USDC from the Main Safe.
- [ ] `forge test` fully green, including all fork tests.

There has been no paid external audit, and there is no external-audit gate: the public bug bounty is
the independent check. An optional external review stays possible; the scope is small (about 450
lines plus the §4d batch).
- [ ] Confirm compiler/settings: `solc 0.8.20`, `paris`, optimizer 1,000,000 runs (matches V1).

---

## 4. Mainnet deployment 🔴

Use a hardware wallet for the deployer if at all possible: leave `PRIVATE_KEY` **unset** and pass
`--ledger`/`--trezor` or a keystore via `--account <name>` — the scripts support keyless
broadcasting and will refuse to run with no signer configured. A raw `PRIVATE_KEY` env var is a
local-fork / testnet fallback only.

```bash
source .env
export RPC=$MAINNET_RPC_URL

# 4a. Deploy. The V1 Treasury becomes V2's treasury (needed for the sweep in 4d).
export NEW_CORE=0xB253a1Ab24B612C2AF37f8fC935b40c7304650e5      # Main Safe
export NEW_TREASURY=0xB4528213285CD10Fdb6a14847a398d71670b3d61  # V1 Treasury
forge script script/Deploy.s.sol --rpc-url $RPC --broadcast --verify
export PSYNFT_V2=0xDEPLOYED_ADDRESS

# 4b. Migrate + finalize (re‑mints all 33 holders, resumes schedule)
forge script script/Migrate.s.sol --rpc-url $RPC --broadcast
```

✅ Gate (repeat the section‑2 checks on mainnet). Do **not** proceed to handoff until every check
passes. If something is wrong *before* finalize you can keep migrating; after finalize the contract
is fixed — if it's wrong, redeploy fresh (the migration is idempotent from a new deploy).

```bash
# 4c. Point the ecosystem at V2, then hand off ownership
#     (set core/treasury now if not done in Deploy)
forge script script/Handoff.s.sol --rpc-url $RPC --broadcast
PSYNFT_V2=$PSYNFT_V2 forge script script/SafeBatches.s.sol --rpc-url $RPC   # writes 4c + 4d
#     → Safe executes safe-batches/4c-accept-v2.json (acceptOwnership on PSYNFT_V2)
```

✅ Gate before the Safe signs `4c-accept-v2.json` (final review N8). The deployer stays owner until
the Safe accepts, so check the state the Safe is about to inherit:
- [ ] `Handoff.s.sol` printed `pre-handoff check OK: 33 snapshot seats match, no approvals on ids 0..33`.
      It refuses to hand over unless the migration is finalized, all 33 snapshot seats are owned by
      their snapshot holder, and no id has a transfer approval.
- [ ] Right before signing, nothing has changed since:
      ```bash
      for id in $(seq 0 33); do cast call $PSYNFT_V2 "approvedTransfers(uint256)(uint256,uint256,address)" $id --rpc-url $RPC; done
      # → the second value (expiry) is 0 for every id
      cast logs --from-block <deploy block> --address $PSYNFT_V2 "TransferApproved(uint256,address,uint256)" --rpc-url $RPC
      # → no entries
      ```
      and V2's event log since deployment shows only what Deploy, Migrate and Handoff emitted (no
      `TokenBurnt`, no extra `CoreUpdated` / `TreasuryUpdated`).

✅ Final gate:
- [ ] `owner() == SAFE_OWNER`, `pendingOwner() == 0`.
- [ ] `core()` / `treasury()` are the intended V2 addresses.
- [ ] Contract verified on Etherscan (green checkmark, "Exact Match" ideally).

---

## 4d. Cutover + exit‑pool sweep 🔴 (one Safe transaction)

Why this works: the V1 Treasury pays `rageQuitBalance ÷ (n − psyNFT.totalTokensBurnt())` on
`exit()`, and `n` is supplied by whoever is `Treasury.core`. The owner withdraw function cannot touch
the pool, so `exit()` is the only way out. The Safe owns the Treasury, makes itself core, points the
Treasury at V2, holds one fresh V2 seat and exits it with `n − burnt = 1`, which releases the whole
pool to the Safe. Balances already owed to past exiters (`pendingBalances`) are not affected.

Execute as **one** Transaction Builder batch from the Main Safe (`safe-batches/4d-cutover-sweep.json`),
in this order:

```
1. V1Treasury.updatePsyNftContract(PSYNFT_V2)
2. V1Treasury.setCoreContract(MainSafe)
3. PsyNFTV2.batchMintInFibonacci()                          // ids 34–54 to the V2 contract
4. PsyNFTV2.transferNFTs([34], MainSafe)                    // needs the fallback handler from §0b
5. V1Treasury.exit(34, 1, MainSafe)                         // n = V2.totalTokensBurnt() + 1 = 1
6. V1Treasury.withdrawUserFunds()                           // pool -> Main Safe
7. PsyNFTV2.setTreasury(MainSafe)                           // Safe burns directly from now on
8. CoreLogic.updatePsyNftAddress(PSYNFT_V2)                 // V1 minting switched off (OPS-02)
```

**Why step 8 (audit 2026-10, OPS-02).** CoreLogic is V1 PsyNFT's minter. Without step 8, the Safe
(as CoreLogic owner) could still call `mintNextBatch` and `createSaleBatchPsycSale`, creating new V1
seats after V2 is canonical. Pointing CoreLogic at V2 sends every CoreLogic mint/approve/kick call to
V2, where CoreLogic has no role, so they all revert: V1 minting is switched off. Re-enabling it would
take a deliberate 2-of-4 Safe transaction (the Safe owns CoreLogic and V1 PsyNFT after §0a/§0b), a
governance decision, not an accident.

Seat #34 is burned by step 5, so batch 7 has 20 seats to allocate (ids 35–54).

✅ Gates (all read‑only, right after execution):
- [ ] Main Safe ETH balance rose by exactly the `rageQuitBalance()` read just before execution.
- [ ] `V1Treasury.rageQuitBalance() == 0` and `V1Treasury.balance == V1Treasury.pendingBalances()`.
- [ ] `PsyNFTV2.ownerOf(34)` reverts; `totalTokensBurnt() == 1`; `treasury()` is the Main Safe.
- [ ] `cast call 0xDAAA…d4F6 "rageQuit(uint256)" <any id> --from <holder>` reverts
      (`Rage Quit Disabled`; and if ever switched back on, `Only callable by CoreLogic.sol`).
- [ ] `cast call 0xDAAA…d4F6 "psyNFT()(address)"` returns `PSYNFT_V2` (V1 minting off).

Rehearsed against live mainnet state by two tests:
- `test/CutoverSweep.fork.t.sol`: direct calls;
- `test/SafeRehearsal.fork.t.sol`: through the real Main Safe contract, from Step 0 and §0a/§0b on,
  with 2 of its 4 owners' addresses (simulated approved-hash signatures; nobody signs), via
  MultiSendCallOnly.

On 2026-10-11 the Safe receives 3.110298529411764706 ETH and 0.094251470588235294 ETH stays
claimable by the token‑0 exiter. A second test runs one legacy exit during the window first and
confirms the sweep takes only what is left. **Re-run both within 24 h before executing §4d**,
because exits during the window change the numbers. (The real-Safe rehearsal skips handover and
freeze steps that have already executed on mainnet, so it can be re-run at any later block.)

> Governance: the sweep ends the exit right of the legacy seats. Execute only on a passed PSYC
> proposal that names the exit window and the sweep, and only with no open Critical or High bounty
> report.

---

## 5. Cutover & comms

- [ ] Update the frontend / metadata / subgraph / marketplace listings to the V2 address.
- [ ] Switch the Snapshot space's PSYC voting strategy from the V1 to the V2 address, or V1 tokens
      keep voting.
- [ ] Book the swept ETH in the accounts (V1 Treasury → Main Safe, exit-pool wind-down).
- [ ] Update `baseUri` if the metadata moved (owner = Safe). For future Fibonacci batches, the art
      workflow (pin a superset folder → `setBaseUri`, or IPNS) is in [docs/METADATA.md](METADATA.md).
- [ ] Announce: new contract address, that holdings were preserved 1:1, and that the old contract is
      deprecated. Publish the snapshot block and `holders.json` for transparency.
- [ ] (Optional) Ask marketplaces (OpenSea, etc.) to delist/flag the V1 contract to avoid confusion.

---

## Rollback / failure modes

| Situation | Action |
|---|---|
| §0a or §0b submitted before its Step 0 handover | `acceptOwnership()` reverts (the Safe is not yet the pending owner), so nothing executes. Wait for the Step 0 transaction, re-run `SafeBatches.s.sol` if the nonce moved, and resubmit. |
| A Step 0 `transferOwnership` names the wrong address | Nothing changes until that address accepts (Ownable2Step). Send `transferOwnership(MainSafe)` again from the same wallet. |
| Wrong data migrated, **before** `finalizeMigration` | Continue `migrateBatch` only mints *new* ids; a wrong owner on an already‑minted id can't be fixed in place → redeploy fresh and re‑run (cheap; do it). |
| Wrong counters at finalize | Redeploy fresh; finalize is one‑shot per deployment. |
| Deployer key compromised mid‑process, before handoff | Redeploy from a clean key; nothing of value is lost (V2 not yet canonical). |
| Safe address wrong in handoff | `Ownable2Step` means it isn't owner until it `accepts`; just call `transferOwnership` again to the correct Safe. |
| §4d batch reverts | Nothing executes (Safe batches are atomic). Most likely cause: fallback handler missing (§0b). Fix and resubmit. |
| §4d executed against a wrong V2 address | The pool is already in the Safe; only V2 is wrong. Redeploy V2 fresh as usual; the sweep does not need repeating. |

Because each mainnet mistake is recoverable by **redeploying a fresh V2** (the migration is a pure
function of the snapshot), there is no destructive step until you publicly declare V2 canonical in
step 5.

---

## Handy `cast` checks

```bash
cast call $PSYNFT_V2 "tokenId()(uint256)"              --rpc-url $RPC
cast call $PSYNFT_V2 "previousFibonacci()(uint256)"    --rpc-url $RPC
cast call $PSYNFT_V2 "controlledTransfers()(bool)"     --rpc-url $RPC
cast call $PSYNFT_V2 "migrationFinalized()(bool)"      --rpc-url $RPC
cast call $PSYNFT_V2 "owner()(address)"                --rpc-url $RPC
cast call $PSYNFT_V2 "pendingOwner()(address)"         --rpc-url $RPC
cast call $PSYNFT_V2 "ownerOf(uint256)(address)" 5     --rpc-url $RPC

# V1 side
export V1T=0xB4528213285CD10Fdb6a14847a398d71670b3d61
cast call $V1T "rageQuitBalance()(uint256)"            --rpc-url $RPC
cast call $V1T "pendingBalances()(uint256)"            --rpc-url $RPC
cast call $V1T "core()(address)"                       --rpc-url $RPC
cast call $V1T "psyNFT()(address)"                     --rpc-url $RPC
cast call 0xDAAAC6a81fE6a230B880b96a2B5ca903d0c1d4F6 "rageQuitAllowed()(bool)" --rpc-url $RPC
cast call 0xDAAAC6a81fE6a230B880b96a2B5ca903d0c1d4F6 "owner()(address)"        --rpc-url $RPC
cast call 0xDAAAC6a81fE6a230B880b96a2B5ca903d0c1d4F6 "psyNFT()(address)"       --rpc-url $RPC
cast call 0x6c6Ab7b3215374dE4A65De63eAC9BC7A0c7f402d "owner()(address)"        --rpc-url $RPC   # V1 PsyNFT
cast call 0xe94828A923538709c58764159D6CD99C4381d82B "owner()(address)"        --rpc-url $RPC   # PsycSale
```
