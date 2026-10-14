# PsyNFT V2 — controlled redeployment & holder migration

## Start here

| You are | Read |
|---|---|
| A PSYC holder (non-technical) | [docs/HOLDER_BRIEF.md](docs/HOLDER_BRIEF.md): what changes and why, in plain language |
| Reviewing the code | [docs/AUDIT-2026-10.md](docs/AUDIT-2026-10.md): the latest audit report (internal and AI-assisted) |
| Looking for bugs | [docs/BUG_BOUNTY.md](docs/BUG_BOUNTY.md): scope, rules and proposed rewards (pending approval; not launched yet) ([SECURITY.md](SECURITY.md) to report) |

Run it ([Foundry](https://book.getfoundry.sh) required):

```bash
forge test            # all tests; the mainnet fork suites skip unless MAINNET_RPC_URL is set
./sandbox/start.sh    # local chain + contract + admin UI, with test accounts (no wallet needed)
```

The original **PsyNFT** (`PSY`, ERC‑721) at
[`0x6c6Ab7b3215374dE4A65De63eAC9BC7A0c7f402d`](https://etherscan.io/token/0x6c6Ab7b3215374dE4A65De63eAC9BC7A0c7f402d)
is still owned by a former operator wallet (`0xC3aC…e445`), not by the DAO. Step 0 of the
cutover ([signer checklist](safe-batches/CHECKLIST.md)) hands it to the Main Safe; until then,
V1's admin functions (`setCoreContract`, `setTreasury`, `setBaseUri`, the transfer toggles) are
outside DAO control.

This repo deploys a **hardened V2 that PsyDAO controls**. V2 keeps V1's behaviour except for the
documented safety changes ([CHANGES_FROM_V1.md](docs/CHANGES_FROM_V1.md) §7–10). It migrates the
existing **33 live holders** into V2, preserving every token id and owner, then resumes the
Fibonacci mint schedule where V1 stopped.

> V1 stays on-chain. V2 is an equivalent contract that the DAO's Main Safe owns, and the community
> moves across to it. That's what this does.

## What's here

| Path | Purpose |
|---|---|
| [`src/PsyNFTV2.sol`](src/PsyNFTV2.sol) | Hardened copy of PsyNFT + migration, events, rescue helpers, single-use/revocable approvals, ERC‑4906 |
| [`reference/PsyNFT.v1.sol`](reference/PsyNFT.v1.sol) | The verified original, for diffing (identical to the on-chain source) |
| [`reference/v1-live/`](reference/v1-live/) | Verified V1 Treasury + CoreLogic sources (called by the cutover) |
| [`snapshot/snapshot.mjs`](snapshot/snapshot.mjs) | Pulls the live V1 holder set → `holders.json` (no deps, dual-RPC verified) |
| [`snapshot/holders.json`](snapshot/holders.json) | The committed snapshot (33 holders; re-verified unchanged at block 26,164,941) |
| [`metadata/`](metadata/README.md) | The collection metadata re-pointed to `ipfs://` (V1's gateway host no longer exists), CAR + CID + verifier; prepared, pinning pending |
| [`script/Deploy.s.sol`](script/Deploy.s.sol) · [`Migrate`](script/Migrate.s.sol) · [`Handoff`](script/Handoff.s.sol) | Deploy V2 (deployer = temporary owner), re‑mint the snapshot, hand off to the Safe |
| [`script/lib/CutoverCalls.sol`](script/lib/CutoverCalls.sol) | The exact Main Safe batches for the cutover (single source of truth) |
| [`script/SafeBatches.s.sol`](script/SafeBatches.s.sol) → [`safe-batches/`](safe-batches/CHECKLIST.md) | Safe Transaction Builder files + signer checklist with expected safeTxHash |
| [`test/`](test/) | 99 tests: unit, audit PoCs, fuzz, 7 invariants, mutation kills, snapshot replay, and 3 live-mainnet fork suites incl. the **real-Safe cutover rehearsal** |
| [`ui/`](ui/README.md) | Admin panel: live dashboard, every action simulated first, **Export for Safe** / Safe batch |
| [`sandbox/`](sandbox/README.md) | One-command local chain + contract + UI, with built-in test accounts (no wallet needed) |
| [`audit/2026-10/`](audit/2026-10/) | Raw audit artefacts: tool outputs, coverage, mutation testing |
| [`docs/HOLDER_BRIEF.md`](docs/HOLDER_BRIEF.md) | **Plain-language brief for PSYC holders** |
| [`docs/AUDIT-2026-10.md`](docs/AUDIT-2026-10.md) | **Latest audit report** (internal and AI-assisted; plan: [AUDIT_PLAN_2026-10.md](docs/AUDIT_PLAN_2026-10.md)) |
| [`docs/TESTING_HANDBOOK.md`](docs/TESTING_HANDBOOK.md) | Step‑by‑step manual test of every function in the sandbox UI |
| [`docs/SEAT_PAYMENTS.md`](docs/SEAT_PAYMENTS.md) | How new-seat payments are split: half to the PsyDAO treasury, half to the artists |
| [`docs/BUG_BOUNTY.md`](docs/BUG_BOUNTY.md) · [`SECURITY.md`](SECURITY.md) | Bug bounty program (proposed, pending approval) and reporting |
| [`docs/`](docs/) | Design, [V1→V2 diff](docs/CHANGES_FROM_V1.md), [runbook](docs/DEPLOYMENT_RUNBOOK.md), [metadata/art ops](docs/METADATA.md), [governance](docs/GOVERNANCE.md), earlier audits |

## Key decisions (as agreed)

- **Target:** the ERC‑721 `PsyNFT` (the address given resolves to the NFT, not an ERC‑20).
- **Migration:** snapshot + owner‑gated re‑mint. Holders do nothing; ids and owners are preserved.
- **Admin model:** a **Gnosis Safe multisig** becomes owner: no single lost key can freeze it; it would take losing 3 of the 4 Safe keys.
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

# 3. Refresh the holder snapshot (optional; one is committed).
#    WARNING: this OVERWRITES the committed snapshot/holders.json, whose sha256 is pinned in
#    the audit report (Appendix A). Restore it with `git checkout snapshot/holders.json`.
#    --verify-rpc re-reads every owner from a second, independent provider.
MAINNET_RPC_URL=$MAINNET_RPC_URL node snapshot/snapshot.mjs --verify-rpc https://ethereum-rpc.publicnode.com
```

Then follow **[docs/DEPLOYMENT_RUNBOOK.md](docs/DEPLOYMENT_RUNBOOK.md)** for the handover →
mainnet deploy → Safe‑handoff sequence.

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
MAINNET_RPC_URL=https://eth.drpc.org ./sandbox/start.sh migrated   # mainnet fork with the real 33 holders migrated
```

A disposable local chain with the contract deployed and the UI pointed at it. Pick a **Sandbox
account** in the UI (no browser wallet, no keys) and click through the whole lifecycle. In fork
mode you can even "act as" the real Main Safe. Step by step: [docs/TESTING_HANDBOOK.md](docs/TESTING_HANDBOOK.md).

## Live V1 state (snapshot block 25,473,885)

| Field | Value |
|---|---|
| `tokenId` (counter) | 34 (ids 0–33 minted) |
| burnt | 1 (id 0) → **33 live tokens** |
| `previousFibonacci` | 21 (next batch mints 21: ids 34–54; the switch-over burns #34, so 20 new seats, ids 35–54, are allocated) |
| `controlledTransfers` | true |
| `owner` / `core` / `treasury` | `0xc3ac…e445` (former operator wallet, not the DAO; Step 0 hands it to the Main Safe) / `0xdaaa…d4f6` / `0xb452…3d61` |
| `baseUri` | `https://red-literary-tiglon-645.mypinata.cloud/ipfs/bafybeia5k2…/`. **That host no longer exists**; V2 will use the re-pointed `ipfs://bafybeib2aqk…/` (prepared, pinning pending; [metadata/README.md](metadata/README.md)) |

## Status

**Internally audited 2026‑10 ([report](docs/AUDIT-2026-10.md); internal and AI-assisted, see
below). Not deployed. The bug bounty and the PSYC vote have not started.**

Done:
- The reviewed code is merged (PR #1, `c611ac9`, tag `v2.0.0-review`, code-identical to the
  audited commit `1c0ab58`). Later changes touch the cutover scripts and tests, two contract
  comments (no logic change) and docs; the bounty target is tag `v2.0.1-review`
  (`ddd30cb`, PR #2).
- The repo is public, and GitHub private vulnerability reporting is on ([SECURITY.md](SECURITY.md)).

Still open:
- Step 0 handovers: V1 PsyNFT, CoreLogic and PsycSale move to the Main Safe
  ([checklist](safe-batches/CHECKLIST.md)).
- Pinning the re-pointed metadata (prepared, pinning pending).
- Approval of the bounty rewards: proposed, pending approval by 2 Main Safe signers.
- The 21-day bug bounty (not launched yet).
- The PSYC vote.

Testing:
- **Tests:** 99 pass (91 deterministic + 8 live-mainnet fork), locally and in CI.
- **Coverage:** 100% of lines and branches of the contract (`src/PsyNFTV2.sol`).
- **Mutation testing:** 95.5% (170/178; the 8 survivors are proven equivalent).
- **Fuzzing:** 4 fuzz tests, and 7 invariants that each hold over 25,600 random role actions
  (256 sequences × 100 calls).
- **Cutover rehearsal:** a simulation on a mainnet fork using the real Main Safe contract, its
  2-of-4 threshold and its owners' addresses (approved-hash signatures) with the exact batch
  bytes; no signer actually signed anything.

Build settings mirror V1: `solc 0.8.20`, EVM `paris`, optimizer at 1,000,000 runs, and OpenZeppelin
v5.0.2 (vendored copy verified byte-identical to the npm release).

**Road to mainnet** (the same sequence in every doc; details in the
[runbook](docs/DEPLOYMENT_RUNBOOK.md)):
1. Step 0 + §0a/§0b: the V1 contracts (V1 PsyNFT, CoreLogic, PsycSale) move to the Main Safe
   ([checklist](safe-batches/CHECKLIST.md)).
2. Bug bounty runs (21 days) on the reviewed code ([docs/BUG_BOUNTY.md](docs/BUG_BOUNTY.md)).
3. PSYC vote: exit window dates, the switch-over, the Safe's powers
   ([docs/HOLDER_BRIEF.md](docs/HOLDER_BRIEF.md)).
4. Exit window (V1 ego death stays on).
5. Freeze (§1) and holder snapshot.
6. V2 deployed, seats migrated, Safe accepts ownership (§4a–§4c). The re-pointed metadata
   ([metadata/README.md](metadata/README.md)) must be pinned before this step.
7. Switch-over transaction §4d, only if no Critical/High bounty report is open.
8. Snapshot voting and marketplaces switch to V2.

Earlier reviews: [SECURITY_REVIEW.md](docs/SECURITY_REVIEW.md), [AUDIT.md](docs/AUDIT.md) (2026‑07‑06).

## How this was built

Written by Steven Fülle with substantial AI assistance (Claude) for the code, the tests, the
security reviews and the docs. The reviews ([AUDIT-2026-10.md](docs/AUDIT-2026-10.md),
[AUDIT.md](docs/AUDIT.md), [SECURITY_REVIEW.md](docs/SECURITY_REVIEW.md)) are internal and
AI-assisted; there has been no paid external audit. The public
[bug bounty](docs/BUG_BOUNTY.md) is the independent check.

## License

[MIT](LICENSE). Vendored dependencies under `lib/` and the verified V1 sources under `reference/`
keep their own license headers.
