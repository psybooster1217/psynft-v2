# Session summary: October 2026 audit (10–11 Oct 2026)

What was done in this working session on PsyNFT V2 (the new PSYC contract), the decisions taken,
where everything is, and what is still open.

## Executive summary

- The contract had last been audited on **6 July 2026**, internally only. This session wrote an
  in-depth audit plan and a testing handbook, then **executed the full audit**.
- **No Critical or High issue in the contract.** The most serious problem found is operational:
  the collection's metadata server no longer exists, so V2 would have launched with no art. It is
  fixed in the repo; only the pinning step remains.
- **Fixed:**
  - 3 Medium issues: transfer approvals not single-use; V1 still mintable after cutover; Safe
    support missing in the admin panel;
  - 12 Low and dev-only issues.
- **Accepted:** 5 informational items, documented.
- **Results:**

  | Measure | July audit | Now |
  |---|---|---|
  | Tests | 45 | **99**, all passing locally and in GitHub CI |
  | Line / branch coverage | 98% / 86% | **100% / 100%** |
  | Mutation score | — | **95.5%** (8 survivors, all proven equivalent) |
  | Invariants | — | **7**, each held over 25,600 random actions |

- **Cutover rehearsed through the real Main Safe** on a mainnet fork, with its real owners, 2-of-4
  threshold and the exact batch bytes. The Safe received exactly **3.110298529411764706 ETH**,
  and money owed to past exiters stayed untouched.
- **Delivered on PR [psybooster1217/psynft-v2#1](https://github.com/psybooster1217/psynft-v2/pull/1)**
  (CI green):
  - audit report;
  - holder brief, plus a private presentation page;
  - bug bounty program;
  - rewritten testing handbook;
  - generated Safe batches with a signer checklist;
  - re-pointed metadata;
  - a brief for outside AI auditors such as Grok Build.
- **Open (your steps):** pin the metadata, merge PR #1, make the repo public and enable private
  vulnerability reporting, get the bounty rewards approved, and hold the PSYC vote.

## Timeline

| # | Phase | Outcome |
|---|---|---|
| 1 | Find the contract | Located in `Desktop\SMARTC`. Last audit 2026‑07‑06 (`AUDIT.md`, `SECURITY_REVIEW.md`), internal only |
| 2 | Plan + handbook | `docs/AUDIT_PLAN_2026-10.md`, `docs/TESTING_HANDBOOK.md`. Every function exercised on the local sandbox; dead metadata gateway discovered |
| 3 | Decisions (asked up front) | Fix issues in code; self-hosted bounty; I prepare the metadata, you pin it; fork rehearsal instead of Sepolia |
| 4 | W0 freeze + baseline | Branch `audit-2026-10`, tag `audit-2026-10-base`, hashes, coverage, ABI parity |
| 5 | W1 tooling | Slither (0 high/medium), forge lint, solc bug list (none applies), npm audit, OZ byte-check (identical to 5.0.2), wrong OZ lock entry fixed, line endings fixed |
| 6 | W2 manual review | V1 source verified against the chain; 4 contract findings fixed in code |
| 7 | W3 property testing | 29 regression/fuzz tests, 7-property invariant suite, mutation testing (86.5% → 94.4% → **95.5%**), 14 kill tests |
| 8 | W4 cutover review | V1 Treasury/CoreLogic sources reviewed; Main Safe confirmed canonical v1.3.0, 2-of-4; real-Safe rehearsal suite; step 8 added; generated batches + checklist |
| 9 | W5 snapshot | Dual-RPC dry run: holder set unchanged since July; 10 holders are 7702-delegated wallets, one can't receive `safeTransfer` |
| 10 | META-1 | 34 metadata files rebuilt with `ipfs://` image links; CAR + CID + verifier; all 34 images confirmed reachable |
| 11 | W7 UI | Safe export/batch, sandbox wallet (no keys), network guards, gateway fallback, revoke + member cards; verified in the browser on a fresh chain and a mainnet fork |
| 12 | W8 CI | Actions SHA-pinned, Foundry pinned, Slither/Aderyn/lint and UI jobs |
| 13 | W9 docs | Audit report, bounty, `SECURITY.md`, holder brief, runbook/metadata/changes updates |
| 14 | Publish (your answers) | Branch pushed (repo stays private), PR #1 opened, CI green; Aderyn run in CI and triaged (its one High is a false positive); `MAINNET_RPC_URL` secret added, so CI runs all 99 tests |
| 15 | Extras | Holder presentation page; `AGENTS.md` brief and paste-in prompt for Grok Build |

## Findings (full detail: [AUDIT-2026-10.md](AUDIT-2026-10.md))

| ID | Severity | What | Status |
|---|---|---|---|
| META‑1 | High (operational) | Metadata/art host no longer exists | Fixed in repo; **pin pending** |
| PNFT‑01 | Medium | Transfer approvals weren't consumed (blocked corrections, could revive) | Fixed |
| OPS‑02 | Medium | Safe could still mint and sell V1 seats after cutover | Fixed (batch step 8) |
| UI‑7 | Medium (operational) | Safe support claimed but not built | Fixed |
| PNFT‑02/03/04 | Low | No revoke; unchecked finalize counters; base-URI slash footgun | Fixed (+ ERC‑4906) |
| OPS‑03/04 | Low | Freeze is a toggle; hand-typed Safe batches | Mitigated / fixed |
| TEST‑1, UI‑8/9, SUP‑1, CI‑1, ENV‑1, DEP‑2 | Low / dev | Test gaps, network/preview issues, lock entry, CI, stop script, npm | Fixed |
| HOLD‑1, CON‑2, SOLC‑1, SUP‑2, UI‑10 | Info | One holder can't receive `safeTransfer`; gas ceiling (now at batch 17); compiler notes; line endings; testing UX | Documented / accepted |

## Decisions you made

| When | Decision |
|---|---|
| Before the audit | Fix weaknesses in code (strict V1 parity is nice-to-have) · self-hosted bounty · I prep the metadata, you pin · fork rehearsal instead of Sepolia |
| Publishing | Repo stays private for now (you flip it) · reports via GitHub private reporting only, no email · rewards stay a proposal · PR, not a direct merge |
| CI | Add `MAINNET_RPC_URL=https://eth.drpc.org` as a repo secret (done) |

## Where everything is

| Path | What |
|---|---|
| `docs/AUDIT-2026-10.md` | The audit report (findings, cutover review, testing, tooling, residual risks, hashes) |
| `docs/HOLDER_BRIEF.md` | Plain-language brief for PSYC holders (page version: https://claude.ai/artifact/YUNKtEWFDNHLEhrbfmhHEb, private until shared) |
| `docs/BUG_BOUNTY.md`, `SECURITY.md`, `test/templates/BountyPoC.t.sol.example` | Bounty program, reporting policy, PoC template |
| `docs/TESTING_HANDBOOK.md` | Step-by-step manual test of every function |
| `docs/DEPLOYMENT_RUNBOOK.md` | Updated deploy + cutover sequence |
| `script/lib/CutoverCalls.sol`, `script/SafeBatches.s.sol`, `safe-batches/` | Cutover batches, generator, Transaction Builder files + signer checklist |
| `test/AuditOct2026.t.sol`, `test/MutationKills.t.sol`, `test/invariant/`, `test/SafeRehearsal.fork.t.sol` | New tests |
| `metadata/` | Original and re-pointed metadata, CAR, CID, verifier, pinning guide |
| `audit/2026-10/` | Raw tool outputs, coverage, mutation script + results, CI static-analysis log |
| `reference/v1-live/` | Verified V1 Treasury/CoreLogic sources |
| `AGENTS.md` | Brief for outside AI auditors (Grok Build, etc.) |

**Git:** branch `audit-2026-10` (pushed); tags `audit-2026-10-base` (before) and `audit-2026-10`
(audited code); PR #1 → `main`, CI green.

## Still open (all yours)

1. **Pin the metadata.** Upload `metadata/psyc-metadata-v2.car` and pin the 6 image folders on two
   services, then run `node metadata/verify-pinned.mjs` through two gateways. Needs the PsyDAO
   Pinata login.
2. **Merge PR #1** into `main`.
3. **Make the repo public**, then enable GitHub private vulnerability reporting (the sole
   reporting channel).
4. **Get the bounty rewards approved** by the Safe signers or a PSYC vote (proposal: Critical up to
   2 ETH).
5. **PSYC vote** on the exit window, the sweep and the Safe's powers. Then run the runbook,
   re-running the fork tests within 24 h before the §4d sweep.
6. Optional: **run Grok Build** in a separate worktree with the prompt from this session, and send
   its report back for verification.
