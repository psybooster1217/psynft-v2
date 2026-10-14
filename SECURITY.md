# Security policy

Please **do not** open public issues for security problems.

**Report privately through GitHub:** on this repository, open the **Security** tab and click
**"Report a vulnerability"**
([direct link](https://github.com/psybooster1217/psynft-v2/security/advisories/new)). This opens a
private advisory that only the maintainer and the people added to it can see. It is the preferred
channel. Keep your proof of concept and write-up private too: don't push them, open a pull request
or post them anywhere public before a fix.

**Backup:** if you can't use GitHub, email **steven@psydao.world**.

**Who decides:** under the proposed bounty rules, the maintainer proposes a severity within 7 days,
at least one Main Safe signer besides the maintainer is added to every advisory, and 2 Main Safe
signers confirm the severity and any reward. Details, including disputes and duplicates, are in
[docs/BUG_BOUNTY.md](docs/BUG_BOUNTY.md).

Scope, rules, safe harbor and rewards: [docs/BUG_BOUNTY.md](docs/BUG_BOUNTY.md). The bounty is a
proposal pending approval by 2 Main Safe signers and is not launched yet.
Review history (internal, AI-assisted; no paid external audit):
[docs/AUDIT-2026-10.md](docs/AUDIT-2026-10.md) (latest), [docs/AUDIT.md](docs/AUDIT.md),
[docs/SECURITY_REVIEW.md](docs/SECURITY_REVIEW.md).

Never test against mainnet. The local sandbox (`./sandbox/start.sh`) and the Foundry fork tests give
you a full copy of the system to work against.
