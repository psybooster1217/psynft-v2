# PSYC Governance — the PsyNFT V2 instrument

> **Discussion draft. The PSYC vote decides.**

**Status:** Discussion draft · **Author:** Steven Fülle (Operations Lead, PDP-23)
**Applies to:** the redeployed PsyNFT V2 contract (this repository)
**Companion documents:** *PSY-PSYC Governance Amendment v3* (constitutional layer), *PDP-24* (treasury signers), *PDP-25 — Funding & Governance Process* (voting process), [`docs/METADATA.md`](METADATA.md) (kené/art operations), [`docs/DEPLOYMENT_RUNBOOK.md`](DEPLOYMENT_RUNBOOK.md) (migration)

---

## 1. Purpose

PSYC is PsyDAO's **steward credential**: a non-transferable ERC-721 held by the elected delegates
who carry a duty of care for the DAO (delegated democracy — PSY ratifies, PSYC stewards). The
original contract's admin key was lost, freezing membership: nobody could be onboarded, removed,
or recovered. This document defines how the **redeployed instrument (PsyNFT V2)** is governed so
that failure class is closed permanently — and so membership becomes a living cycle again.

It covers: who controls the contract, how each governance action maps to a contract call, and how
new members get a seat (the **one-door seat system**, §5). How membership lapses (the **Renewal
cycle**, §6) is sketched for a later proposal.

## 2. The instrument, in plain terms

| Property | On-chain reality |
|---|---|
| Identity | ERC-721 `PsyNFT` (`PSY` symbol), one token = one PSYC seat |
| Uniqueness | Every token carries a unique **kené** (artwork) via `tokenURI` — see [METADATA.md](METADATA.md) |
| Soulbound by default | `controlledTransfers = true`: a member-held token **cannot move** unless governance grants a time-boxed transfer window (`approveTransfer`) |
| Supply | Minted in **Fibonacci batches** to the contract itself (next batch: 21 tokens, ids 34–54); distributed one-by-one to new members |
| Removal | `burn(tokenId)` — **does not require the holder's consent**. Recall and lost-wallet recovery are native capabilities, held by governance |
| Admin safety | Owner is a Gnosis Safe; ownership is 2-step and **cannot be renounced** — the lost-key failure mode is structurally impossible |

## 3. Role architecture: one Safe, all roles

Per the decision adopted with this document, **all three contract roles — `owner`, `core`, and
`treasury` — are held by the Main Treasury Safe** (the PDP-24 signer set).

```
                    Main Treasury Safe (PDP-24 signers, threshold per PDP-24)
                    ────────────────────────────────────────────────────────
   owner:  setCoreContract · setTreasury · setBaseUri · enable/disableControlledTransfers
           · transferOwnership (2-step) · rescue helpers
   core:   batchMintInFibonacci · transferNFTs (distribute) · approveTransfer
   treasury: burn
```

Rationale: PSYC operations are **low-frequency and high-legitimacy** (a handful of transactions
per seat round). Routing everything through the treasury signers maximizes multi-party control
(Rebirth accountability requirement: *no single contributor holds sole administrative access to
any infrastructure*) at negligible operational cost.

**Escape hatch:** if operational cadence ever demands it, the Safe can delegate the `core` role to
a lighter operations Safe with a single `setCoreContract` transaction — a reversible, vote-gated
change. No redeployment needed.

**Execution practice:** owner/core/treasury actions are executed through the Safe UI
(app.safe.global → Transaction Builder → the verified contract). Every executed action emits an
event (V2 addition) and is therefore publicly auditable; material actions are additionally logged
in the Quarterly Treasury Transparency Report (PDP-24 §6).

## 4. Governance actions → contract calls

New seats go through the **seat round** (§5). Every other membership decision follows the
**PDP-25 membership track** (bi-monthly batch; 10-day comment phase; 4-day Snapshot; threshold:
≥5 PSYC yes, simple majority). The Safe then executes:

| Governance decision | Decided by | Executed on-chain as |
|---|---|---|
| Seat a new member | Seat round (§5) | `transferNFTs([id], member)` — one contract-held token per person |
| Replenish the seat pool | Automatic when the pool is empty and a new member needs a seat | `batchMintInFibonacci()` — mints the next Fibonacci batch to the contract |
| Remove / recall a member | PSYC membership vote | `burn(tokenId)` |
| Lapse for inactivity | Renewal cycle (§6, a later proposal) | `burn(tokenId)` |
| Member wallet rotation | Request + Safe verification of both wallets | `approveTransfer(tokenId, newWallet, 259200)` (72h window), member executes the transfer |
| Lost wallet recovery | PSYC membership vote | `burn(strandedId)` + `transferNFTs([freshId], newWallet)` |
| Attach kené to new tokens | Operational (owner) | pin superset metadata folder → `setBaseUri(newCid)` — process in [METADATA.md](METADATA.md) |
| Change these rules / roles | PSYC vote (+ PSY ratification where the Amendment requires) | `setCoreContract` / `setTreasury` / governance-doc amendment |

Two hard rules carried from the contract design:

1. **The migration is not a pruning.** All 33 current holders are re-minted 1:1, active or not.
   Legitimacy of the redeploy depends on perfect fidelity; lifecycle management happens *after*
   migration, through the processes below — never during it.
2. **Burns are governance acts.** The Safe never burns without a passed membership vote (or, once
   a later proposal adopts it, a Renewal cycle outcome, §6). The capability is unrestricted on-chain; its use is restricted by
   this document.

## 5. New seats: the one-door seat system

There is one way in, the same for everyone: **apply, gather backing in a round, mint.**

**Apply.** Apply on psydao.world from a wallet holding **at least 10,420 PSY**.

**The round.** Applications are decided in seat rounds, held **every two months**. Each round runs
for **14 days**, and support is counted **at the end of the round**. Each person can back **up to 3
applicants per round**. An objection needs a one-line reason.

**Who gets in.** At the end of the round, an applicant is in when all three hold:

1. at least **3 PSYC backers**;
2. **more PSYC backers than objectors**;
3. at least **5 PSY backers**.

**Not in this time.** An applicant who is not in skips one round, then can apply again.

**Mint.** An applicant who is in mints their seat **within 14 days**: **0.1 ETH** for a random seat,
or **0.2 ETH** for a chosen one.

**One seat per person.** A seat is soulbound (`controlledTransfers`), and each person holds at most
one.

**Supply cap.** The Fibonacci batches cap supply: **21 seats now** (ids 34–54), **then 34**
(ids 55–88). A new batch is minted only when the current one is used up (§7).

**On-chain.** The Safe hands the seat over with `transferNFTs([id], member)`; if the contract-held
pool is empty, the same Safe session first runs `batchMintInFibonacci()`. A kené is attached to the
token per the metadata process. PsyNFT V2 itself has no payable function, so the mint price is
collected outside this contract.

The seat is personal and non-transferable. It confers: participation in PSYC votes (membership,
review-panel duty under PDP-25 guardrail 3), steward eligibility, and the duty of care described
in the Amendment.

## 6. The Renewal cycle — death and rebirth in one act

> **Not part of this proposal, a later one.** Burns for inactivity are sketched here for
> discussion only. Nothing in this section applies until a separate proposal adopts it.

Rather than a standing bureaucratic timer, PSYC renews itself in **batches**: lapses and new
mints are handled together, in the same governance act, so the council contracts and grows in one
motion.

**Trigger.** A Renewal cycle is opened as part of a membership batch — typically whenever there
are candidates to onboard, and at minimum once per year.

**Census.** When a Renewal opens, the Operations Lead (or a designated steward) publishes an
activity census: each seat's participation over the recent period (votes, forum/Discord activity,
delivered work). The standard is deliberately simple: **a seat lapses when it has shown no
activity for a sustained period** — assessed in the round, not by a rigid formula.

**Outreach first.** Every seat flagged as lapsing receives direct outreach and a minimum of **30
days** to respond before any burn is proposed. Any genuine sign of life resets the seat. This is
the Rebirth principle: positive action first; burning is the last step, never the first.

**The vote.** The Renewal proposal lists, in one document: (a) seats proposed to lapse (with the
census evidence and outreach record), and (b) the applicants who got in through the seat round
(§5). It runs on the standard membership track. Voters see the full picture — who leaves,
who arrives — as a single act of renewal.

**Execution — one Safe session:**

```
burn(lapsedId_1) … burn(lapsedId_n)          # death
batchMintInFibonacci()                        # rebirth (only if the pool is empty)
transferNFTs([id], newMember_1) … (each)      # new seats
setBaseUri(newCid)                            # kenés for the new tokens (if new ids minted)
```

All of it is publicly verifiable on-chain through the V2 events (`TokenBurnt`, `Migrated`/
`Transfer`, `BaseUriUpdated`).

**Voluntary exit** is honoured at any time without a vote: the member states the intent publicly,
and the Safe burns the seat in the next session.

## 7. Supply discipline

The Fibonacci batches are the supply cap: 21 seats now (ids 34–54), then 34 (ids 55–88). To keep
PSYC a working council rather than a diluted badge:

- New batches are minted **only when the contract-held pool is empty** and a new member from a
  seat round needs a token — never speculatively.
- Undistributed tokens sit in the contract (custody = the contract itself, spendable only by
  `core` = the Safe) and carry no vote: **Snapshot strategies must count only member-held
  tokens**, excluding the contract's own balance and, where feasible, seats flagged in an open
  Renewal.
- The far-future gas ceiling on very large batches (documented in [AUDIT.md](AUDIT.md), CON-2) is
  acknowledged and irrelevant at council scale — decades of headroom.

## 8. Amendments

This document is operational policy under the *PSY-PSYC Governance Amendment*. Changes to it
follow the PSYC membership track (with PSY ratification where the Amendment requires it).
On-chain role changes (`setCoreContract`, `setTreasury`, ownership transfer) additionally require
the explicit call to be named in the proposal that authorizes them.

---

*Appendix — canonical call reference for the Safe Transaction Builder:*

| Action | Function | Notes |
|---|---|---|
| Distribute seat | `transferNFTs(uint256[] _tokenIds, address _recipient)` | one recipient per call; batch per member |
| Mint next batch | `batchMintInFibonacci()` | no args; mints to the contract |
| Remove seat | `burn(uint256 _tokenId)` | governance-gated by §4 |
| Wallet rotation | `approveTransfer(uint256 _tokenId, address _to, uint256 _seconds)` | use 259200 (72h); member then calls `transferFrom` |
| Kené update | `setBaseUri(string _uri)` | must end with `/` — see METADATA.md |
| Delegate ops | `setCoreContract(address)` | reversible; vote-gated |
