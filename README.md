# PsyNFT V2 — controlled redeployment & holder migration

The original **PsyNFT** (`PSY`, ERC‑721) at
[`0x6c6Ab7b3215374dE4A65De63eAC9BC7A0c7f402d`](https://etherscan.io/token/0x6c6Ab7b3215374dE4A65De63eAC9BC7A0c7f402d)
is administratively frozen: its `owner` key is unreachable, so no one can call
`setCoreContract`, `setTreasury`, `setBaseUri`, or toggle transfers. Ownership lives on‑chain
and cannot be recovered without the key.

This repo deploys a **hardened, behaviour‑identical V2 that PsyDAO controls**, and migrates the
existing **33 live holders** into it — preserving every token id and owner — then resumes the
Fibonacci mint schedule exactly where V1 stopped.

> You can't reclaim the old contract. You *can* stand up an equivalent one you own and move the
> community across. That's what this does.

## What's here

| Path | Purpose |
|---|---|
| [`src/PsyNFTV2.sol`](src/PsyNFTV2.sol) | Hardened copy of PsyNFT + migration, events, rescue helpers, single-use/revocable approvals, ERC‑4906 |
| [`reference/PsyNFT.v1.sol`](reference/PsyNFT.v1.sol) | The verified original, for diffing (identical to the on-chain source) |
| [`reference/v1-live/`](reference/v1-live/) | Verified V1 Treasury + CoreLogic sources (called by the cutover) |
| [`snapshot/snapshot.mjs`](snapshot/snapshot.mjs) | Pulls the live V1 holder set → `holders.json` (no deps, dual-RPC verified) |
| [`snapshot/holders.json`](snapshot/holders.json) | The committed snapshot (33 holders; re-verified unchanged at block 26,164,941) |
| [`metadata/`](metadata/README.md) | The collection metadata re-pointed to `ipfs://` (V1's gateway is dead), CAR + CID + verifier |
| [`script/Deploy.s.sol`](script/Deploy.s.sol) · [`Migrate`](script/Migrate.s.sol) · [`Handoff`](script/Handoff.s.sol) | Deploy V2 (deployer = temporary owner), re‑mint the snapshot, hand off to the Safe |
| [`script/lib/CutoverCalls.sol`](script/lib/CutoverCalls.sol) | The exact Main Safe batches for the cutover (single source of truth) |
| [`script/SafeBatches.s.sol`](script/SafeBatches.s.sol) → [`safe-batches/`](safe-batches/CHECKLIST.md) | Safe Transaction Builder files + signer checklist with expected safeTxHash |
| [`test/`](test/) | 99 tests: unit, audit PoCs, fuzz, 7 invariants, mutation kills, snapshot replay, and 3 live-mainnet fork suites incl. the **real-Safe cutover rehearsal** |
| [`ui/`](ui/README.md) | Admin panel: live dashboard, every action simulated first, **Export for Safe** / Safe batch |
| [`sandbox/`](sandbox/README.md) | One-command local chain + contract + UI, with built-in test accounts (no wallet needed) |
| [`audit/2026-10/`](audit/2026-10/) | Raw audit artefacts: tool outputs, coverage, mutation testing |
| [`docs/HOLDER_BRIEF.md`](docs/HOLDER_BRIEF.md) | **Plain-language brief for PSYC holders** |
| [`docs/AUDIT-2026-10.md`](docs/AUDIT-2026-10.md) | **Latest audit report** (plan: [AUDIT_PLAN_2026-10.md](docs/AUDIT_PLAN_2026-10.md)) |
| [`docs/TESTING_HANDBOOK.md`](docs/TESTING_HANDBOOK.md) | Step‑by‑step manual test of every function in the sandbox UI |
| [`docs/BUG_BOUNTY.md`](docs/BUG_BOUNTY.md) · [`SECURITY.md`](SECURITY.md) | Bug bounty program and reporting |
| [`docs/`](docs/) | Design, [V1→V2 diff](docs/CHANGES_FROM_V1.md), [runbook](docs/DEPLOYMENT_RUNBOOK.md), [metadata/art ops](docs/METADATA.md), [governance](docs/GOVERNANCE.md), earlier audits |

## Key decisions (as agreed)

- **Target:** the ERC‑721 `PsyNFT` (the address given resolves to the NFT, not an ERC‑20).
- **Migration:** snapshot + owner‑gated re‑mint. Holders do nothing; ids and owners are preserved.
- **Admin model:** a **Gnosis Safe multisig** becomes owner — no single lost key can ever freeze it again.
- **Fidelity:** a **hardened** copy: V1 behaviour plus events, the migration path, and rescue helpers.
  The October 2026 audit added deliberate safety changes, listed in [CHANGES_FROM_V1.md](docs/CHANGES_FROM_V1.md) §7–10.

## Quickstart

```bash
# 0. Toolchain (Foundry) + deps are vendored under lib/. To rebuild:
forge build

# 1. Run the deterministic suite (no RPC needed): unit, fuzz, invariants
forge test --no-match-path "test/*.fork.t.sol"

# 2. Validate migration, sweep and the real-Safe cutover against LIVE mainnet state
export MAINNET_RPC_URL=https://eth.drpc.org      # needs an archive-capable RPC
forge test --match-path "test/*.fork.t.sol" -vv

# 3. Refresh the holder snapshot (optional; one is committed)
MAINNET_RPC_URL=$MAINNET_RPC_URL node snapshot/snapshot.mjs
```

Then follow **[docs/DEPLOYMENT_RUNBOOK.md](docs/DEPLOYMENT_RUNBOOK.md)** for the testnet → mainnet
→ Safe‑handoff sequence.

### Control panel (admin dApp)

```bash
cd ui && npm install && npm run dev   # http://localhost:5173
```

Paste the deployed address and drive every owner/core/treasury function from a UI with a live state
dashboard. Every action is simulated first. Owner actions belong on the Safe: **Export for Safe** /
**+ Safe batch** simulate the call as the Safe and produce a Transaction Builder file. See
[ui/README.md](ui/README.md).

### Try it locally (sandbox)

```bash
./sandbox/start.sh          # local chain + PsyNFTV2 + the UI wired to it
./sandbox/start.sh roles    # owner, core and treasury on different accounts
./sandbox/start.sh migrated # mainnet fork with the real 33 holders migrated
```

A disposable local chain with the contract deployed and the UI pointed at it. Pick a **Sandbox
account** in the UI (no browser wallet, no keys) and click through the whole lifecycle. In fork
mode you can even "act as" the real Main Safe. Step by step: [docs/TESTING_HANDBOOK.md](docs/TESTING_HANDBOOK.md).

## Live V1 state (snapshot block 25,473,885)

| Field | Value |
|---|---|
| `tokenId` (counter) | 34 (ids 0–33 minted) |
| burnt | 1 (id 0) → **33 live tokens** |
| `previousFibonacci` | 21 (next batch mints 21: ids 34–54) |
| `controlledTransfers` | true |
| `owner` / `core` / `treasury` | `0xc3ac…e445` (lost) / `0xdaaa…d4f6` / `0xb452…3d61` |
| `baseUri` | `https://red-literary-tiglon-645.mypinata.cloud/ipfs/bafybeia5k2…/`. **That host no longer exists**; V2 uses the re-pinned `ipfs://bafybeib2aqk…/` ([metadata/README.md](metadata/README.md)) |

## Status

**Audited 2026‑10 ([report](docs/AUDIT-2026-10.md)). Ready for the PSYC vote and the bug bounty.**

- **Tests:** 99 pass (91 deterministic + 8 live-mainnet fork).
- **Coverage:** 100% of lines and branches.
- **Mutation testing:** 95.5% (170/178; the 8 survivors are proven equivalent).
- **Fuzzing:** 7 invariants hold over 25,600 random role actions each.
- **Cutover rehearsal:** executed through the real Main Safe (real owners, threshold 2, the exact
  batch bytes).

Build settings mirror V1: `solc 0.8.20`, EVM `paris`, optimizer at 1,000,000 runs, and OpenZeppelin
v5.0.2 (vendored copy verified byte-identical to the npm release).

**Before mainnet:**
1. Pin the re-pointed metadata ([metadata/README.md](metadata/README.md)).
2. Run the 21-day bug bounty ([docs/BUG_BOUNTY.md](docs/BUG_BOUNTY.md)).
3. Pass the PSYC vote ([docs/HOLDER_BRIEF.md](docs/HOLDER_BRIEF.md)).
4. Follow the [runbook](docs/DEPLOYMENT_RUNBOOK.md).

Earlier reviews: [SECURITY_REVIEW.md](docs/SECURITY_REVIEW.md), [AUDIT.md](docs/AUDIT.md) (2026‑07‑06).
