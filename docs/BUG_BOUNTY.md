# PsyNFT V2 bug bounty (self-hosted)

**Status:** draft, ready to publish once the items under "Before launch" are done. Reward amounts
are a **proposal** for the Main Safe signers or a PSYC vote to approve.

PsyDAO is replacing its frozen V1 membership NFT with **PsyNFT V2**, controlled by the PsyDAO Main
Safe. The 33 existing seats migrate one-to-one, and a one-time Safe transaction winds down the
legacy exit pool (~3.11 ETH). We want independent eyes on it before and after that happens.

## Scope

**In scope**

| Asset | Where | Notes |
|---|---|---|
| `PsyNFTV2` smart contract | `src/PsyNFTV2.sol` at the audited commit; after launch, the mainnet address announced on psydao.world | Primary target |
| Cutover batches | `script/lib/CutoverCalls.sol` (and the generated `safe-batches/`) | Until the §4d batch has executed |
| Deploy / migration scripts | `script/Deploy.s.sol`, `script/Migrate.s.sol`, `script/Handoff.s.sol` | Anything that could mis-migrate a seat or leak ownership |
| Holder snapshot tool | `snapshot/snapshot.mjs` | Anything that could produce a wrong or incomplete `holders.json` |
| Admin panel | `ui/` | Only issues that could make an operator sign something other than what is shown, or leak secrets |

**Impacts we care about** (examples): an attacker can
- move, mint, burn or freeze someone else's seat;
- gain or keep the owner/core/treasury role;
- get around the controlled-transfer rule;
- make the migration drop or mis-assign a seat;
- make the sweep send funds anywhere but the Main Safe, or touch what past exiters are owed;
- make the admin panel produce calldata different from what it displays.

**Out of scope**
- The deployed V1 contracts themselves (they are immutable and their owner key is lost), except as
  used by the §4d batch.
- Anything the trusted roles are allowed to do by design (the Main Safe can mint, distribute,
  approve/revoke, burn any seat, toggle transfer controls, change metadata). See
  [AUDIT-2026-10.md](AUDIT-2026-10.md) §8.
- Known and accepted items in [AUDIT-2026-10.md](AUDIT-2026-10.md), [AUDIT.md](AUDIT.md) and
  [SECURITY_REVIEW.md](SECURITY_REVIEW.md): e.g. the Fibonacci batch gas ceiling (CON‑2), the solc
  0.8.20 notes (SOLC‑1), and token 29's wallet not accepting `safeTransfer` (HOLD‑1).
- Issues that need a compromised Safe signer, leaked keys, or social engineering; phishing; denial
  of service against RPCs, gateways or websites.
- Third-party code: Safe, OpenZeppelin, IPFS gateways, Snapshot.org, wallets.
- Best-practice or gas suggestions without a security impact (welcome as normal GitHub issues).

## Rewards (proposal)

| Severity | Example | Proposed reward |
|---|---|---|
| Critical | Take over a role; mint, steal or burn seats without the role; divert the sweep | up to **2 ETH** |
| High | Bypass the controlled-transfer rule; corrupt or drop a seat during migration; brick a core function permanently | up to **0.75 ETH** |
| Medium | Make an admin action produce a different result than shown, with a realistic path to harm | up to **0.25 ETH** |
| Low | Real but limited issues (e.g. misleading UI state with no direct loss) | up to **0.05 ETH** |

Paid from the PsyDAO Main Safe after a fix is live (or the issue is otherwise resolved). Severity is
assessed on actual impact to PsyDAO and holders. Duplicates: the first valid report wins.

## Rules
1. **Never test on mainnet.** Use the local sandbox (`./sandbox/start.sh`, or `migrated` mode for a
   mainnet fork) or a Foundry fork test. Everything you need is in the repo.
2. Include a proof of concept, ideally a Foundry test. A template is at
   `test/templates/BountyPoC.t.sol.example`.
3. Report privately (below). Give us a reasonable time to fix before any public disclosure: 90 days,
   or sooner by agreement.
4. Don't access other people's data, degrade services, or move funds that aren't yours.
5. One issue per report. Chained issues may be reported together.

**Safe harbor.** PsyDAO will not pursue legal action against researchers who follow these rules in
good faith, and will work with you to understand and fix the issue quickly.

## How to report
- **GitHub:** Security → "Report a vulnerability" on the repository (private advisory).
- **Email:** `[SECURITY CONTACT TO BE SET BEFORE LAUNCH]`

We aim to acknowledge within 72 hours and give a severity assessment within 7 days.

## Before launch (checklist for PsyDAO)
- [ ] Main Safe signers (or a PSYC vote) approve the reward table and budget.
- [ ] Make the repository public, or publish the audited commit.
- [ ] Enable GitHub private vulnerability reporting on the repository.
- [ ] Set the security contact email above, and in [SECURITY.md](../SECURITY.md).
- [ ] Publish this page (GitHub + a short page or link on psydao.world) and announce it in Discord.
- [ ] Decide the bounty window before the §4d sweep (recommended: at least 2 weeks of bounty on
      the final deployed V2 before signing §4d).
