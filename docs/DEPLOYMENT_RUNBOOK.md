# Deployment runbook

A step‑by‑step, reversible‑where‑possible sequence to test and deploy PsyNFT V2 and migrate the 33
holders. **Do the Sepolia rehearsal in full before touching mainnet.**

> Legend: 🧪 test‑only · 🔴 mainnet/irreversible · ✅ verification gate

---

## 0. Prerequisites

- [ ] Foundry installed (`forge --version`). Deps are vendored under `lib/` (OpenZeppelin v5.0.2, forge‑std).
- [ ] `.env` created from `.env.example` and filled in. **Never commit `.env`.**
- [ ] RPC endpoints for Sepolia and mainnet (Alchemy/Infura/your node).
- [ ] `ETHERSCAN_API_KEY` for source verification.
- [ ] A funded **deployer** key (temporary owner). Prefer a hardware wallet / keystore; a raw
      `PRIVATE_KEY` is acceptable for testnet.
- [ ] The **Gnosis Safe** that will own V2 (create at <https://app.safe.global> if needed). Put its
      address in `SAFE_OWNER`.
- [ ] The **core** and **treasury** addresses you control for V2 (`NEW_CORE`, `NEW_TREASURY`).
- [ ] `BASE_URI` set in `.env` to the metadata folder (carry V1's art over by using V1's CID). Must
      end with a trailing `/`. If left blank, tokens have **no image** until the Safe calls
      `setBaseUri`. See [docs/METADATA.md](METADATA.md).

✅ Gate: `forge test --no-match-path test/Migration.fork.t.sol` is green, and
`MAINNET_RPC_URL=… forge test --match-path test/Migration.fork.t.sol -vv` passes.

---

## 1. Freeze the snapshot 🔴 (decide a block)

The holder set can change until V1 is truly inactive. Pin a block so the snapshot is reproducible.

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

## 2. Sepolia rehearsal 🧪 (full dry run)

Run the **entire** mainnet sequence on Sepolia first.

```bash
source .env
export RPC=$SEPOLIA_RPC_URL

# 2a. Deploy (deployer = temporary owner)
forge script script/Deploy.s.sol --rpc-url $RPC --broadcast --verify
# → note the deployed address; set it:
export PSYNFT_V2=0xDEPLOYED_ADDRESS

# 2b. Migrate the committed snapshot + finalize
forge script script/Migrate.s.sol --rpc-url $RPC --broadcast

# 2c. Hand off to the Safe (initiates Ownable2Step transfer)
forge script script/Handoff.s.sol --rpc-url $RPC --broadcast
# → in the Safe UI, execute acceptOwnership() on PSYNFT_V2
```

✅ Gates (read the contract on Sepolia Etherscan or via `cast`):
- [ ] `tokenId() == 34`, `previousFibonacci() == 21`, `controlledTransfers() == true`,
      `migrationFinalized() == true`.
- [ ] Spot‑check `ownerOf(id)` for several ids equals the snapshot owner.
- [ ] `ownerOf(0)` **reverts** (burnt id not re‑minted).
- [ ] **Art carried over:** `tokenURI(5)` (and a couple more ids) matches V1's `tokenURI` for the
      same id and the image resolves. Easiest check: admin UI → **Art / metadata preview**. Or
      `cast call $PSYNFT_V2 "tokenURI(uint256)(string)" 5 --rpc-url $RPC`. See [METADATA.md](METADATA.md).
- [ ] `owner()` is still the deployer; `pendingOwner()` is the Safe — until the Safe accepts, then
      `owner()` is the Safe and `pendingOwner()` is zero.
- [ ] From the Safe, `setCoreContract`/`setTreasury` succeed; from any other address they revert.
- [ ] `batchMintInFibonacci` (called by `core`) mints 21 tokens (ids 34–54) to the contract.

Tear down mentally, fix anything, and only then proceed.

---

## 3. Independent audit ✅ (before mainnet value)

- [ ] Run `docs/SECURITY_REVIEW.md` findings to closure (this repo ships an adversarial internal
      review; an **external audit** is still strongly recommended before real value moves).
- [ ] `forge test` fully green, including the live fork test.
- [ ] Confirm compiler/settings: `solc 0.8.20`, `paris`, optimizer 1,000,000 runs (matches V1).

---

## 4. Mainnet deployment 🔴

Use a hardware wallet for the deployer if at all possible: leave `PRIVATE_KEY` **unset** and pass
`--ledger`/`--trezor` or a keystore via `--account <name>` — the scripts support keyless
broadcasting and will refuse to run with no signer configured. A raw `PRIVATE_KEY` env var is a
testnet fallback only.

```bash
source .env
export RPC=$MAINNET_RPC_URL

# 4a. Deploy
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
#     → Safe executes acceptOwnership() on PSYNFT_V2
```

✅ Final gate:
- [ ] `owner() == SAFE_OWNER`, `pendingOwner() == 0`.
- [ ] `core()` / `treasury()` are the intended V2 addresses.
- [ ] Contract verified on Etherscan (green checkmark, "Exact Match" ideally).

---

## 5. Cutover & comms

- [ ] Update the frontend / metadata / subgraph / marketplace listings to the V2 address.
- [ ] Update `baseUri` if the metadata moved (owner = Safe). For future Fibonacci batches, the art
      workflow (pin a superset folder → `setBaseUri`, or IPNS) is in [docs/METADATA.md](METADATA.md).
- [ ] Announce: new contract address, that holdings were preserved 1:1, and that the old contract is
      deprecated. Publish the snapshot block and `holders.json` for transparency.
- [ ] (Optional) Ask marketplaces (OpenSea, etc.) to delist/flag the V1 contract to avoid confusion.

---

## Rollback / failure modes

| Situation | Action |
|---|---|
| Wrong data migrated, **before** `finalizeMigration` | Continue `migrateBatch` only mints *new* ids; a wrong owner on an already‑minted id can't be fixed in place → redeploy fresh and re‑run (cheap; do it). |
| Wrong counters at finalize | Redeploy fresh; finalize is one‑shot per deployment. |
| Deployer key compromised mid‑process, before handoff | Redeploy from a clean key; nothing of value is lost (V2 not yet canonical). |
| Safe address wrong in handoff | `Ownable2Step` means it isn't owner until it `accepts`; just call `transferOwnership` again to the correct Safe. |

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
```
