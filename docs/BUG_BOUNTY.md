# PsyNFT V2 bug bounty (self-hosted)

**Status:** proposal, **not launched**. The reward table, the budget and the rules marked
*(proposal)* below are **pending approval by 2 Main Safe signers**. The PSYC vote comes after the
bounty is announced, so the Safe signers approve the rewards. The approval will be recorded in this
file under [Approval](#approval) (date, plus a link to the Safe message, transaction or signed note)
before the bounty is announced. Until then, no reward is promised.

**In-scope commit:** tag `v2.0.1-review` (proposed; created when the current fix lands, and its full
commit hash is added here then). Its contract, `src/PsyNFTV2.sol`, has the same logic as the earlier
reviewed commit
[`c611ac9c58eab92d146822fd8520275ef5ed5d22`](https://github.com/psybooster1217/psynft-v2/commit/c611ac9c58eab92d146822fd8520275ef5ed5d22)
(tag [`v2.0.0-review`](https://github.com/psybooster1217/psynft-v2/tree/v2.0.0-review)); only two NatSpec comments were
reworded. What changed since then: the cutover, batch and handoff scripts (`script/`) and their tests, the PoC template, two NatSpec comments in `src/PsyNFTV2.sol` (wording only, no logic change), the admin panel's IPFS gateway list and one comment (`ui/src/`), `sandbox/start.sh` (default fork RPC, executable bit), `.github/ISSUE_TEMPLATE/config.yml`, and the docs. Reports should target
`v2.0.1-review`.

PsyDAO is replacing its V1 membership NFT with **PsyNFT V2**, controlled by the PsyDAO Main Safe.
The 33 existing seats migrate one-to-one, and a one-time Safe transaction winds down the legacy exit
pool (about 3.11 ETH). The code has had an internal, AI-assisted review
([AUDIT-2026-10.md](AUDIT-2026-10.md)); there has been no paid external audit, so this bounty is the
independent check. We want independent eyes on it before and after the switch-over.

## Scope

**In scope**

| Asset | Where | Notes |
|---|---|---|
| `PsyNFTV2` smart contract | `src/PsyNFTV2.sol` at the in-scope commit; after launch, the mainnet address listed under [Window and go-live](#window-and-go-live) | Primary target |
| Cutover batches | `script/lib/CutoverCalls.sol` (and the generated `safe-batches/`: the §0a/§0b handover and the §1–§4d cutover) | Until the §4d batch has executed |
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
- The deployed V1 contracts themselves (V1 PsyNFT, CoreLogic, PsycSale, V1 Treasury), except as
  used by the cutover batches above. They are being retired: Step 0 and §0a/§0b hand their
  ownership to the Main Safe, and the §4d switch-over winds them down.
- Anything the trusted roles are allowed to do by design (the Main Safe can mint, distribute,
  approve/revoke, burn any seat, toggle transfer controls, change metadata). See
  [AUDIT-2026-10.md](AUDIT-2026-10.md) §8.
- Known and accepted items in [AUDIT-2026-10.md](AUDIT-2026-10.md), [AUDIT.md](AUDIT.md) and
  [SECURITY_REVIEW.md](SECURITY_REVIEW.md): e.g. the Fibonacci batch gas ceiling (CON-2), the solc
  0.8.20 notes (SOLC-1), and token 29's wallet not accepting `safeTransfer` (HOLD-1).
- Issues that need a compromised Safe signer, leaked keys, or social engineering; phishing; denial
  of service against RPCs, gateways or websites.
- Third-party code: Safe, OpenZeppelin, IPFS gateways, Snapshot.org, wallets, and the Splits
  contracts used as the seat-payment address ([SEAT_PAYMENTS.md](SEAT_PAYMENTS.md)).
- Best-practice or gas suggestions without a security impact (welcome as normal GitHub issues).

## Rewards (proposal)

| Severity | Example | Proposed reward |
|---|---|---|
| Critical | Take over a role; mint, steal or burn seats without the role; divert the sweep | up to **$2,500** |
| High | Bypass the controlled-transfer rule; corrupt or drop a seat during migration; brick a core function permanently | up to **$1,000** |
| Medium | Make an admin action produce a different result than shown, with a realistic path to harm | up to **$400** |
| Low | Real but limited issues (e.g. misleading UI state with no direct loss) | up to **$100** |

Total budget: **$5,000**. Severity is judged on actual impact to PsyDAO and holders.

### Payment (proposal)
- **Payer:** the PsyDAO Main Safe,
  [`0xB253a1Ab24B612C2AF37f8fC935b40c7304650e5`](https://etherscan.io/address/0xB253a1Ab24B612C2AF37f8fC935b40c7304650e5)
  (2-of-4).
- **Asset:** you choose ETH or USDC. USDC is paid 1:1 against the USD reward. For ETH, the USD
  reward is converted at the CoinGecko ETH/USD price at the time the payout transaction is proposed
  in the Safe.
- **When:** within 30 days after the report is resolved. A report is resolved when its fix is merged
  into `main` (before launch) or deployed (after launch), or when the signers confirm that no code
  change is needed. Confirmed rewards are paid even if go-live is later cancelled.
- **Budget:** confirmed rewards are paid in the order the reports were received until the $5,000 is
  used up. PsyDAO will say so on this page when that happens; valid reports after that are credited,
  and paid only if the signers approve more budget.

### Severity and decisions (proposal)
- The maintainer (the repository owner) acknowledges a report within 72 hours and proposes a
  severity and reward within 7 days.
- **2 Main Safe signers confirm** the severity and reward. At least one Main Safe signer besides the
  maintainer is added to every private advisory, so no report is seen by one person only.
- **Disputes:** if you disagree, reply on the advisory (or by email) within 14 days with your
  reasoning. The two Main Safe signers who did not confirm the first rating review it. If they agree
  on a different rating, theirs applies; otherwise the first rating stands.
- **Duplicates:** the earliest valid report wins, decided by the creation time of the GitHub
  advisory or the time the email was received.
- **"Open"** (for the go-live gate): a report rated Critical or High that is not yet fixed or
  disproven. A report still waiting for its first rating counts as open until it is rated.

### Eligibility (proposal)
- Anyone may report, but these people are not eligible for a reward: current PsyDAO contributors,
  Main Safe signers, and anyone who worked on this code (including its author).
- Before paying, PsyDAO may screen the payout wallet against sanctions lists and ask for basic
  identity information. No reward is paid to sanctioned persons or to anyone in a sanctioned
  jurisdiction.
- You are responsible for any taxes on your reward.
- PsyDAO may change or end the program at any time. Changes are published on this page and do not
  affect reports filed before they were published.

## Window and go-live

**Window:** **21 days**. Day 1 is the day the bounty is announced, from 00:00 UTC; the window ends
at 23:59 UTC on day 21. The rules in this section on dates, late reports, fix commits and
post-launch scope are part of the proposal.
- Start (UTC): *set when the bounty is announced*
- End (UTC): *set when the bounty is announced*

Order of events: the V1 contracts move to the Main Safe first (Step 0, §0a/§0b), then the bounty
runs, then come the PSYC vote, the exit window, the freeze and holder snapshot, and the V2
deployment and migration. The §4d switch-over goes ahead only if **no Critical or High report is
open** (see "Open" above). This is checked before the V2 deployment and again immediately before the
§4d transaction is signed.

- **Between day 21 and go-live:** reports are still accepted and rewarded on the same terms, and an
  open Critical or High still blocks go-live.
- **Fix commits:** if a report leads to a change in `src/` or `script/`, the fixed commit becomes
  the new in-scope commit (tagged and listed at the top of this page), and the window is extended to
  at least 7 days after the fix is published, so the fix itself gets reviewed.
- **After launch:** the deployed V2 contract stays in scope for 90 days after the §4d switch-over,
  or until the budget is used up, whichever comes first. Its details are added here at deployment
  (the bytecode hash must match [AUDIT-2026-10.md](AUDIT-2026-10.md) Appendix A):
  - V2 address: *added at deployment*
  - Etherscan verification: *added at deployment*
  - Runtime bytecode hash: *added at deployment*

## Rules
1. **Never test on mainnet.** Use the local sandbox (`./sandbox/start.sh`, or `migrated` mode for a
   mainnet fork) or a Foundry fork test. Everything you need is in the repo.
2. Include a proof of concept, ideally a Foundry test. Start from the template at
   `test/templates/BountyPoC.t.sol.example`: copy it to `test/external/BountyPoC.t.sol`. It fails
   until you replace its TODO with your exploit and assertions.
3. Report privately (below). Keep your PoC and write-up local: don't push them, open a pull request,
   or file a public issue with them. Give us a reasonable time to fix before any public disclosure:
   90 days, or sooner by agreement.
4. Don't access other people's data, degrade services, or move funds that aren't yours.
5. One issue per report. Chained issues may be reported together.

**Safe harbor.** If you make a good-faith effort to follow these rules:
- PsyDAO considers your research authorized and will not pursue or support legal action against you
  for it;
- if a third party takes legal action against you for research that followed these rules, PsyDAO
  will make it known that your research was authorized;
- PsyDAO will work with you to understand and fix the issue quickly.

This covers only the PsyDAO code and systems listed in scope; PsyDAO cannot authorize testing of
third-party systems. If you are unsure whether something is allowed, ask in a private report before
doing it.

**Credit.** Once an issue is fixed (or the bounty ends), valid findings are published as a GitHub
security advisory and credited to you by the name or handle you choose, or anonymously if you
prefer.

## How to report
Use GitHub: **Security → "Report a vulnerability"** on the repository. This opens a private
advisory visible only to the maintainer and the people added to it (see
[Severity and decisions](#severity-and-decisions-proposal)). It is the preferred channel. If you
can't use GitHub, email **steven@psydao.world** as a backup.

We aim to acknowledge within 72 hours and propose a severity within 7 days.

## Approval
*Pending.* When 2 Main Safe signers approve the reward table, the budget and the rules marked
*(proposal)*, this section records the date, the approving signers' addresses, and a link to the
Safe message, transaction or signed note.

## Before launch (checklist for PsyDAO)
- [ ] Step 0 and §0a/§0b executed: V1 PsyNFT, CoreLogic and PsycSale owned by the Main Safe.
- [ ] Tag `v2.0.1-review` created when the fix lands, and its full commit hash added at the top of
      this page.
- [ ] 2 Main Safe signers approve the reward table, the budget and the rules marked *(proposal)*;
      record it under [Approval](#approval), then remove "(proposal)" and "Proposed" from this page.
- [ ] Legal check of the eligibility and safe-harbor terms.
- [ ] At least one Main Safe signer besides the maintainer is ready to be added to private
      advisories.
- [x] Make the repository public (2026-10-13). The reviewed commit at that time was tag
      `v2.0.0-review` (`c611ac9`).
- [x] Enable GitHub private vulnerability reporting, the preferred reporting channel (2026-10-13).
- [x] Reporting channel decided: GitHub private reports, with steven@psydao.world as the backup
      email (2026-10-13).
- [ ] Set the start and end dates (UTC) under [Window and go-live](#window-and-go-live).
- [ ] Publish this page (GitHub + a short page or link on psydao.world) and announce it in Discord.
- [x] Bounty window decided: 21 days; go-live only with no open Critical or High (2026-10-13).
