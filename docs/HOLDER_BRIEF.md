# PSYC V2: what's changing, and how it was checked

*A plain-language brief for PSYC holders. Technical detail is linked at the end.*

## In one minute

- **The problem.** The original PSYC contract (V1) is still owned by a former operator wallet
  (0xC3aC…e445), not by the DAO, and its art links point to a web address that has stopped working.
  Step 0 hands V1 to the Main Safe; until then, V1's admin functions are outside DAO control.
- **The fix.** A new contract, **PSYC V2**, controlled by the **PsyDAO Main Safe** (a 2-of-4
  multisig) instead of one person's key. Its ownership cannot be renounced, and no single lost key
  can freeze it (that would take losing 3 of the 4 Safe keys).
- **Your seat moves automatically.** Every seat still held at the freeze is re-created in V2 with
  the **same token number** in the **same wallet**. You don't need to do anything, sign anything,
  or pay gas. (A seat that exits before the freeze is burned and does not move to V2.)
- **Same art, same schedule.** The art is the same Shipibo kené artwork, prepared for re-publishing
  on IPFS (the pinning step is pending) so it no longer depends on a web address that has stopped
  working. New seats continue the same Fibonacci schedule: the switch-over mints the next batch
  (21 seats, numbers 34–54) and uses one of them (#34) to release the pool, so **20 new seats
  (35–54)** are available.
- **How it was checked.** 99 automated tests and a simulated rehearsal of the switch-over through
  the real PsyDAO Safe on a copy of Ethereum. The review was internal and AI-assisted; there has
  been no paid external audit. A public bug bounty will run before any money moves.

## What changes for you

| | V1 (today) | V2 |
|---|---|---|
| Who controls the contract | A former operator wallet, not the DAO (moves to the Main Safe at Step 0) | PsyDAO Main Safe, 2-of-4 multisig |
| Your seat | Token #N in your wallet | Token #N in the same wallet |
| Moving your seat to a new wallet of yours | Needs an approval from the DAO | Same. The approval is now single-use, and the DAO can cancel a mistaken one. Seats are not for sale |
| Voting on Snapshot | Counts V1 | Switched to V2 at launch |
| Art | Links to a server that no longer works | The same art, linked directly via IPFS (pinning pending) |
| Leaving with a share of the pool ("ego death") | Available today and through the exit window; your seat is burned | Not available: the remaining pool moves to the DAO treasury (see below) |

## The exit window and the pool

V1 has an exit pool of about **3.11 ETH**. Today, any holder can "ego death" a seat and take an
equal share: the pool divided by the seats still live, which is about **0.094 ETH per seat**
(3.11 ÷ 33).

What exiting means for you:
- **Exiting burns your seat.** You will not get a V2 seat.
- **It takes two transactions** (rage quit, then withdraw), and you pay the gas for both.
- **If you do nothing,** you keep your seat and give up your claim on the pool.

The proposal works like this:
1. **Exit window.** After the PSYC vote passes, ego death stays open for a set period. Anyone who
   wants to leave can, at the fair share.
2. **Freeze.** The window closes and the holder list is captured.
3. **Switch-over.** In one atomic Safe transaction (all-or-nothing), which only goes ahead if no
   Critical or High bug bounty report is open:
   - V2 takes over;
   - the next V2 batch (seats 34–54) is minted; the Safe uses seat #34 to release the pool, which
     burns it, leaving 20 new seats (35–54);
   - the remaining pool moves to the Main Safe treasury;
   - V1 minting is switched off. Turning it back on would take a deliberate 2-of-4 Safe
     transaction.

   Money already owed to someone who exited earlier (0.094 ETH, from seat #0) stays theirs to
   claim.

After the switch there is no automatic on-chain exit. The pool becomes DAO treasury, governed by
PSYC votes. This is the main thing to weigh when you vote.

## What the Main Safe can do (please read)

In V2 the Safe holds all the powers that were split between V1's owner, its core contract and its
treasury. They are now held by a multisig instead of one person:
- create new seat batches on the Fibonacci schedule, and hand out seats;
- approve or cancel a holder's request to move a seat;
- **remove a seat** (the "kick" power, a DAO decision), even without the holder's consent;
- switch transfer restrictions on or off, and update the art links;
- **hand any role** (minting, handing out seats, burning) to another address, including a single
  wallet, or move ownership to another address (for example another Safe);
- recover tokens or ETH sent to the contract by mistake;
- control the old V1 contracts: the Safe already owns the V1 Treasury (the exit pool), and after
  Step 0 it also owns V1 PsyNFT, CoreLogic and PsycSale.

Each of these takes 2 of the 4 Safe signers. Two signers can, however, hand a power to a single
address, and the Safe's signers can change the Safe's own signers and threshold. The October 2026
review suggests considering a higher threshold than 2-of-4. The contract cannot be left ownerless,
and ownership can only move to an address that actively accepts it.

## New seats

One door, the same for everyone (a discussion draft; the PSYC vote decides):

- **Apply** on psydao.world. You need at least **10,420 PSY** in your wallet.
- **Rounds** happen every two months and last **14 days**. Support is counted when the round ends.
- **You're in** with at least **3 PSYC backers**, **more PSYC backers than objectors**, and at least
  **5 PSY backers**. Anyone who objects gives a one-line reason.
- **Backing:** each person can back up to 3 applicants per round.
- **Not in this time?** Skip one round, then apply again.
- **Pay within 14 days:** 0.1 ETH for a random seat, or 0.2 ETH to choose yours, paid to
  PsyDAO (collected outside the contract); the Main Safe then sends you the seat. The contract itself does not take payment.
- **One seat per person.** Seats are personal and not for sale: they only move to a new wallet of
  yours, with a DAO approval.
- **Pace of new seats:** seats come in Fibonacci batches: 20 available after the switch-over
  (35–54), then 34.

These are DAO rules, not limits enforced by the contract: the contract does not cap seats per
person or decide when a new batch is minted.

Removing seats for inactivity is not part of this proposal; it may come later, as a separate one.
Full rules: [governance](GOVERNANCE.md) §5.

## How it was checked

An internal review (October 2026), carried out by the proposer with substantial AI assistance
(Claude). There has been no paid external audit; the public bug bounty is the independent check.
The review covered the contract, the migration, the switch-over transaction, the admin panel and
the tooling. Its main checks:
- **The switch-over through the real Safe.** The full sequence was simulated on a copy of today's
  Ethereum using the real PsyDAO Safe contract, its 2-of-4 threshold and its signers' addresses
  (a simulation: no signer actually signed anything). The whole pool (**3.1103 ETH**) reached the
  Safe; every holder kept their seat; the money owed to past exiters was untouched; and V1 minting
  was switched off.
- **All-or-nothing.** When one step was deliberately made to fail, *nothing* happened at all.
- **Random-attack testing.** About 1,800 random sequences (roughly 179,000 actions) by every role,
  including outsiders trying admin functions, checked against seven safety rules.
- **"Plant a bug" testing.** 178 deliberate bugs were planted in the code; the tests caught 170.
  The other 8 change nothing observable.
- **Findings were fixed.** The review found and fixed several issues. The biggest: the art's web
  address had died (new links are prepared; pinning them on IPFS is pending), and old V1 could
  still have been used to create extra seats after the switch (the switch-over now switches V1
  minting off).

A **bug bounty** will invite independent security researchers to try to break it for 21 days,
before the PSYC vote and before the pool moves. The **proposed** rewards are up to $2,500 per issue ($5,000
in total), paid in ETH or USDC from the Main Safe; they are pending approval by two Main Safe
signers, and the program has not launched yet. The switch-over only goes ahead if no serious
(Critical or High) report is still open.

## Check it yourself

- **Try it safely.** The project includes a one-command practice environment: a private copy of
  the blockchain with the contract and an admin panel. You can click through every action without
  touching real money. See the [testing handbook](TESTING_HANDBOOK.md).
- **After launch,** look up your seat on the V2 contract (the address will be announced on
  psydao.world): same number, same wallet. In wallets it appears as **PsyNFT (PSY)**, like V1.
- **Stay safe.** Use only the address published on psydao.world. Nobody will ask you to sign
  anything for the migration.

## Timeline

1. Step 0: the old V1 contracts (V1 PsyNFT, CoreLogic, PsycSale) move from individual wallets to
   the Main Safe, so the exit-pool machinery is no longer controlled by individual keys.
2. Bug bounty runs (21 days) on the reviewed code.
3. PSYC vote on this proposal (exit window dates, the switch-over, the Safe's powers).
4. Exit window (V1 ego death stays on).
5. Freeze and holder snapshot.
6. V2 deployed and seats migrated, then the Safe takes ownership. The art is pinned and verified
   before deployment.
7. Switch-over transaction, only if no Critical or High bug bounty report is open.
8. Snapshot voting and marketplaces switch to V2 (marketplaces only display the collection; seats
   are not for sale).

## Questions

- **Do I need to do anything?** No. If you keep your seat until the freeze, it appears in V2
  automatically.
- **Will my seat number change?** No.
- **Can I move my seat to a new wallet?** Yes: ask the DAO for a wallet-rotation approval (both
  wallets verified as yours), then move it within the approved window. Seats are not for sale.
- **What if I want my share of the pool?** Exit during the exit window (V1 ego death), before the
  freeze. Exiting burns your seat, so you will not get a V2 seat. It takes two transactions (rage
  quit, then withdraw), and you pay the gas.
- **What happens to V1 tokens?** They stay in your wallet as a historical record, but V1 is retired:
  voting moves to V2 and V1 minting is switched off (turning it back on would take a deliberate
  2-of-4 Safe transaction).

---
Technical detail: [internal review report](AUDIT-2026-10.md) · [changes from V1](CHANGES_FROM_V1.md) ·
[deployment runbook](DEPLOYMENT_RUNBOOK.md) · [bug bounty](BUG_BOUNTY.md) · [governance](GOVERNANCE.md)
