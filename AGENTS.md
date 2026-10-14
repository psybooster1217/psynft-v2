# Instructions for AI agents auditing this repository

You are reviewing **PsyNFT V2** (PsyDAO's PSYC membership NFT) as an independent security auditor.
Your job is to find real, exploitable problems, prove each one with a test, and report it. Do not
change the code under audit.

## Read first
1. `docs/AUDIT-2026-10.md` — the latest internal, AI-assisted review. Its findings table lists what
   is **already known**; do not re-report those IDs (META-1, PNFT-01..04, OPS-02..04, UI-7..10,
   SUP-1/2, CI-1, ENV-1, DEP-2, HOLD-1, CON-2, SOLC-1, TEST-1) or any ID from the earlier reviews,
   `docs/AUDIT.md` (CON-1..5, UI-1/2/3/5/6, SCR-1, SNAP-2, DEP-1, CI-1) and
   `docs/SECURITY_REVIEW.md` (MIG-1, SNAP-1, DEPLOY-1; rejected: AC-1, MIG-2), unless you show the
   fix is wrong or incomplete.
2. `docs/BUG_BOUNTY.md` — scope, out-of-scope items (trusted-role powers, V1 contracts themselves,
   third-party code), and the severity scale. Use that scale. (The rewards are a proposal pending
   approval by 2 Main Safe signers.)
3. `docs/CHANGES_FROM_V1.md` and `reference/PsyNFT.v1.sol` — what V2 changed from the original.
4. `docs/DEPLOYMENT_RUNBOOK.md` and `safe-batches/CHECKLIST.md` — Step 0 and §0a/§0b (the V1
   contracts handed to the Main Safe), then the one-time cutover §1–§4d executed by the PsyDAO Main
   Safe.

## In scope
| File | What to look for |
|---|---|
| `src/PsyNFTV2.sol` | Anything that lets a non-role address move, mint, burn or freeze a seat; bypass the controlled-transfer gate; gain or keep a role; break the migration or the Fibonacci schedule |
| `script/lib/CutoverCalls.sol` | Any way the §0a/§0b or §4d batches send funds anywhere but the Main Safe, touch what past exiters are owed, or leave V1 usable |
| `script/Deploy.s.sol`, `script/Migrate.s.sol`, `script/Handoff.s.sol` | Mis-migrated seats, ownership leaks |
| `snapshot/snapshot.mjs` | Anything producing a wrong or incomplete `snapshot/holders.json` |
| `ui/src/` | The admin panel producing calldata different from what it displays |

V1 contracts it interacts with (read-only context): `reference/v1-live/`.

## Setup (Windows Git Bash, macOS or Linux)
```bash
export PATH="$HOME/.foundry/bin:$PATH"          # Foundry (forge/anvil/cast) 1.7.x
forge build
forge test --no-match-path "test/*.fork.t.sol"  # 91 tests, ~1 min, no network
MAINNET_RPC_URL=https://eth.drpc.org forge test --match-path "test/*.fork.t.sol" -vv   # 8 fork tests
```
A local copy of the whole system with the admin UI: `./sandbox/start.sh` (or `roles` / `migrated`);
see `docs/TESTING_HANDBOOK.md`.

## Rules
- **Do not modify** anything under `src/`, `script/`, `snapshot/`, `metadata/`, `lib/`, or existing
  tests. Add files only under `test/external/` and `audit/external/`.
- **Keep `test/external/` and `audit/external/` local.** This repository is public. Never commit or
  push them, open a pull request, or file a public issue, discussion or comment containing findings
  or PoCs; any of these discloses the problem before it is fixed.
- **Report through GitHub private vulnerability reporting:** the repository's **Security** tab →
  **"Report a vulnerability"** (see `SECURITY.md`), with your report and PoC attached. If you cannot
  do that yourself, hand both to your operator to submit. The backup channel is the email in
  `SECURITY.md`.
- **Never send transactions to mainnet or any public network.** No `--broadcast` against a real RPC.
  Use plain tests, fork tests (`vm.createSelectFork`), or the local sandbox.
- Do not use, request or store private keys other than anvil's public dev keys.
- Prove every finding with a Foundry test in `test/external/`. Start from
  `test/templates/BountyPoC.t.sol.example`: copy it to `test/external/<File>.t.sol` (it imports
  `src/PsyNFTV2.sol`, so it compiles there). The template fails until you replace its TODO; your test
  must **pass** only when the exploit works.
- A claim you cannot demonstrate with a test goes under "Unproven observations", never as a
  finding.

## Report
Write `audit/external/<your-name>-report.md` (local only; submit it through the private report
above) with:
1. A summary (counts by severity).
2. One section per finding: ID, severity (per `docs/BUG_BOUNTY.md`), affected file and line, impact,
   step-by-step exploit, the PoC test name, and the command to run it:
   `forge test --match-path test/external/<File>.t.sol -vvvv`.
3. Unproven observations and informational notes.
4. What you checked and found sound, so the coverage of your review is visible.
