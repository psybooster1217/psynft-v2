# PSYC V2: what's changing, and why it's safe

*A plain-language brief for PSYC holders. Technical detail is linked at the end.*

## In one minute

- **The problem.** The original PSYC contract (V1) can no longer be administered. The key that
  controlled it is lost, so nobody can update its settings, its art links, or its rules, ever.
- **The fix.** A new contract, **PSYC V2**, controlled by the **PsyDAO Main Safe** (a 2-of-4
  multisig) instead of one person's key. Ownership can never be thrown away by accident again.
- **Your seat moves automatically.** Every one of the 33 seats is re-created in V2 with the **same
  token number** in the **same wallet**. You don't need to do anything, sign anything, or pay gas.
- **Same art, same schedule.** The art is the same Shipibo kené artwork, re-published so it no
  longer depends on a web address that has stopped working. New seats continue the same Fibonacci
  schedule (the next batch is 21 seats, numbers 34–54).
- **It has been tested hard.** 99 automated tests, a full rehearsal of the switch-over through the
  real PsyDAO Safe on a copy of Ethereum, and a public bug bounty before any money moves.

## What changes for you

| | V1 (today) | V2 |
|---|---|---|
| Who controls the contract | One lost key (frozen) | PsyDAO Main Safe, 2-of-4 multisig |
| Your seat | Token #N in your wallet | Token #N in the same wallet |
| Moving a seat to another wallet | Needs an approval from the DAO | Same. The approval is now single-use, and the DAO can cancel a mistaken one |
| Voting on Snapshot | Counts V1 | Switched to V2 at launch |
| Art | Links to a server that no longer works | The same art, linked directly via IPFS |
| Leaving with a share of the pool ("ego death") | Available during the exit window | Ends when the window closes (see below) |

## The exit window and the pool

V1 has an exit pool of about **3.11 ETH**. Today, any holder can "ego death" a seat and take an
equal share, which is about **0.094 ETH per seat** (3.11 ÷ 33).

The proposal works like this:
1. **Exit window.** After the PSYC vote passes, ego death stays open for a set period. Anyone who
   wants to leave can, at the fair share.
2. **Freeze.** The window closes and the holder list is captured.
3. **Switch-over.** In one atomic Safe transaction (all-or-nothing):
   - V2 takes over;
   - the remaining pool moves to the Main Safe treasury;
   - the old V1 contract is permanently prevented from creating new seats.

   Money already owed to someone who exited earlier (0.094 ETH, from seat #0) stays theirs to
   claim.

After the switch there is no automatic on-chain exit. The pool becomes DAO treasury, governed by
PSYC votes. This is the main thing to weigh when you vote.

## What the Main Safe can do (please read)

The Safe has the same powers V1's owner had. They are now held by a multisig instead of one person:
- create new seat batches on the Fibonacci schedule, and hand out seats;
- approve or cancel a holder's request to move a seat;
- **remove a seat** (the "kick" power, a DAO decision), even without the holder's consent;
- switch transfer restrictions on or off, and update the art links.

None of this can be done by one person: it takes 2 of the 4 Safe signers. The contract cannot be
left ownerless, and ownership can only move to an address that actively accepts it.

## New seats

One door, the same for everyone (a discussion draft; the PSYC vote decides):

- **Apply** on psydao.world. You need at least **10,420 PSY** in your wallet.
- **Rounds** happen every two months and last **14 days**. Support is counted when the round ends.
- **You're in** with at least **3 PSYC backers**, **more PSYC backers than objectors**, and at least
  **5 PSY backers**. Anyone who objects gives a one-line reason.
- **Backing:** each person can back up to 3 applicants per round.
- **Not in this time?** Skip one round, then apply again.
- **Mint within 14 days:** 0.1 ETH for a random seat, or 0.2 ETH to choose yours.
- **One seat per person.** Seats are soulbound: they only move with a DAO approval.
- **Limited supply:** seats come in Fibonacci batches, 21 now, then 34.

Removing seats for inactivity is not part of this proposal; it may come later, as a separate one.
Full rules: [governance](GOVERNANCE.md) §5.

## How it was checked

An in-depth audit (October 2026) covered the contract, the migration, the switch-over transaction,
the admin panel and the tooling. Its main checks:
- **The switch-over through the real Safe.** The full sequence was executed on a copy of today's
  Ethereum using the real PsyDAO Safe, its real signers and its real 2-of-4 threshold.
  **Exactly 3.11 ETH** reached the Safe; every holder kept their seat; the money owed to past
  exiters was untouched; and old V1 can no longer mint.
- **All-or-nothing.** When one step was deliberately made to fail, *nothing* happened at all.
- **Random-attack testing.** Thousands of random sequences of actions by every role, including
  outsiders trying admin functions, checked against seven safety rules.
- **"Plant a bug" testing.** 178 deliberate bugs were planted in the code; the tests caught 170.
  The other 8 change nothing observable.
- **Findings were fixed.** The audit found and fixed several issues. The biggest: the art's web
  address had died (now re-published), and old V1 could still have been used to create extra
  seats after the switch (now blocked).

A **bug bounty** invites independent security researchers to try to break it before the pool moves:
21 days, rewards up to $2,500 per issue ($5,000 in total). The switch-over only goes ahead if no
serious (Critical or High) report is still open.

## Check it yourself

- **Try it safely.** The project includes a one-command practice environment: a private copy of
  the blockchain with the contract and an admin panel. You can click through every action without
  touching real money. See the [testing handbook](TESTING_HANDBOOK.md).
- **After launch,** look up your seat on the V2 contract (the address will be announced): same
  number, same wallet.

## Timeline

1. PSYC vote on this proposal (exit window dates, the switch-over, the Safe's powers).
2. Bug bounty runs; art re-published and verified.
3. Exit window, then freeze and snapshot.
4. V2 deployed and seats migrated, then the Safe takes ownership, then the switch-over transaction.
5. Snapshot voting and marketplaces switch to V2.

## Questions

- **Do I need to do anything?** No. Your seat appears in V2 automatically.
- **Will my seat number change?** No.
- **Can I still sell or move my seat?** Same as today: ask the DAO for a transfer approval, then
  move it within the approved window.
- **What if I want my share of the pool?** Exit during the exit window (V1 ego death), before the
  freeze.
- **What happens to V1 tokens?** They stay in your wallet as a historical record, but V1 is retired:
  voting moves to V2 and V1 can no longer create new seats.

---
Technical detail: [audit report](AUDIT-2026-10.md) · [changes from V1](CHANGES_FROM_V1.md) ·
[deployment runbook](DEPLOYMENT_RUNBOOK.md) · [bug bounty](BUG_BOUNTY.md) · [governance](GOVERNANCE.md)
