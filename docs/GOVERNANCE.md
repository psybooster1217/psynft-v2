# PSYC Governance — the PsyNFT V2 instrument

**Status:** Draft for PSYC review · **Author:** Steven Fülle (Operations Lead, PDP-23)
**Applies to:** the redeployed PsyNFT V2 contract (this repository)
**Companion documents:** *PSY-PSYC Governance Amendment v3* (constitutional layer), *PDP-24* (treasury signers), *PDP-25 — Funding & Governance Process* (voting process), [`docs/METADATA.md`](METADATA.md) (kené/art operations), [`docs/DEPLOYMENT_RUNBOOK.md`](DEPLOYMENT_RUNBOOK.md) (migration)

---

## 1. Purpose

PSYC is PsyDAO's **steward credential**: a non-transferable ERC-721 held by the elected delegates
who carry a duty of care for the DAO (delegated democracy — PSY ratifies, PSYC stewards). The
original contract's admin key was lost, freezing membership: nobody could be onboarded, removed,
or recovered. This document defines how the **redeployed instrument (PsyNFT V2)** is governed so
that failure class is closed permanently — and so membership becomes a living cycle again.

It covers: who controls the contract, how each governance action maps to a contract call, how new
members are onboarded, and how membership lapses — the **Renewal cycle**.

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
per Renewal cycle). Routing everything through the treasury signers maximizes multi-party control
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

Every membership decision follows the **PDP-25 membership track** (bi-monthly batch; 10-day
comment phase; 4-day Snapshot; threshold: ≥5 PSYC yes, simple majority), then the Safe executes:

| Governance decision | Decided by | Executed on-chain as |
|---|---|---|
| Onboard new member(s) | PSYC membership vote | `transferNFTs([ids], member)` — one contract-held token per new member |
| Replenish the seat pool | Implicit in an onboarding vote when the pool is empty | `batchMintInFibonacci()` — mints the next Fibonacci batch to the contract |
| Remove / recall a member | PSYC membership vote | `burn(tokenId)` |
| Lapse for inactivity | Renewal cycle (see §6) | `burn(tokenId)` |
| Member wallet rotation | Request + Safe verification of both wallets | `approveTransfer(tokenId, newWallet, 259200)` (72h window), member executes the transfer |
| Lost wallet recovery | PSYC membership vote | `burn(strandedId)` + `transferNFTs([freshId], newWallet)` |
| Attach kené to new tokens | Operational (owner) | pin superset metadata folder → `setBaseUri(newCid)` — process in [METADATA.md](METADATA.md) |
| Change these rules / roles | PSYC vote (+ PSY ratification where the Amendment requires) | `setCoreContract` / `setTreasury` / governance-doc amendment |

Two hard rules carried from the contract design:

1. **The migration is not a pruning.** All 33 current holders are re-minted 1:1, active or not.
   Legitimacy of the redeploy depends on perfect fidelity; lifecycle management happens *after*
   migration, through the processes below — never during it.
2. **Burns are governance acts.** The Safe never burns without a passed membership vote or a
   Renewal cycle outcome (§6). The capability is unrestricted on-chain; its use is restricted by
   this document.

## 5. Onboarding: Contribute → Nominate → Vote → Mint

The path to a PSYC seat is **earned through work, confirmed by peers**:

**Stage 1 — Contribute.** The candidate has visible, delivered contribution to PsyDAO: a ratified
steward/domain role (PDP-25 Stewardship track), or delivered work within a funded initiative,
sustained for at least one governance cycle. Contribution is the *only* entry currency — there is
no purchase path to PSYC.

**Stage 2 — Nominate.** A sitting PSYC member nominates the candidate in the membership channel,
with a short public rationale: what they built, why they can carry a duty of care. Self-nomination
is not valid. The nomination includes the candidate's wallet address.

**Stage 3 — Vote.** The nomination enters the next bi-monthly membership batch (PDP-25): 10-day
comment phase, then a 4-day Snapshot vote of PSYC holders (≥5 PSYC participating, simple
majority). The candidate is expected to be present and answer questions during the comment phase.

**Stage 4 — Pledge & mint.** On passage the candidate signs the **Steward Pledge** (duty of care,
conflict-of-interest disclosure, token-sale disclosure — per the Rebirth accountability
requirements). The Safe then distributes a contract-held token to their wallet
(`transferNFTs`). If the pool is empty, the same Safe session first mints the next Fibonacci
batch. A kené is attached to the token per the metadata process.

The seat is personal and non-transferable. It confers: participation in PSYC votes (membership,
review-panel duty under PDP-25 guardrail 3), steward eligibility, and the duty of care described
in the Amendment.

## 6. The Renewal cycle — death and rebirth in one act

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
census evidence and outreach record), and (b) candidates proposed to join (each having passed
Stages 1–2). It runs on the standard membership track. Voters see the full picture — who leaves,
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

The Fibonacci schedule is generous (next batch alone mints 21 seats). To keep PSYC a working
council rather than a diluted badge:

- New batches are minted **only when the contract-held pool is empty** and an approved onboarding
  needs a token — never speculatively.
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
