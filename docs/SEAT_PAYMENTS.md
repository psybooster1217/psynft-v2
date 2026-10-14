# Seat payments: half to the treasury, half to the artists

**Status:** design agreed 2026-10-14. Not set up yet: it needs the partner wallet address, a written
partner agreement, and a Main Safe transaction to create the split (checklist below).

New seats cost **0.1 ETH** (random seat) or **0.2 ETH** (chosen seat); see
[GOVERNANCE.md](GOVERNANCE.md) §5. Every payment is split **50 / 50**:

- **50% to the PsyDAO treasury:** the Main Safe `0xB253a1Ab24B612C2AF37f8fC935b40c7304650e5`.
- **50% to the artists:** paid to a partner wallet, which pays the artist whose kené is on the seat,
  locally and in local currency where needed.

## Why outside the contract

PsyNFT V2 has no payable function. The Main Safe hands seats over with `transferNFTs([id], member)`.
Building payment and splitting into the contract would change audited code. Instead, the split is
done by **Splits** ([splits.org](https://splits.org), formerly 0xSplits), a widely used, open-source,
non-upgradeable split contract. It charges no protocol fee; only an optional distributor fee, which
we set to 0%.

## The setup

**One split address for all seat payments.** Every sale has the same two recipients, so one split is
enough:

| Recipient | Share |
|---|---|
| Main Safe `0xB253…50e5` (PsyDAO treasury) | 50% |
| Partner wallet `[to be confirmed]` (artists) | 50% |

- **Controller: the Main Safe.** The Safe (2 of 4 signers) can update the split, for example if the
  partner wallet changes. Every change is public on-chain and must be announced in the PsyDAO
  Discord and noted at the bottom of this page.
- **Distributor fee:** 0%.
- **Where the address is published:** here, in GOVERNANCE.md §5, and on psydao.world. Members only
  pay the address published there.

## How a sale works

1. **Assign the seat first.** When an applicant is in (GOVERNANCE.md §5), the DAO assigns the seat:
   - a random one, at random from the free ids;
   - or the one they chose.

   The artist is the one named in that seat's metadata.
2. **The member pays the split.** They send exactly 0.1 or 0.2 ETH from the wallet that will hold
   the seat, within 14 days.
3. **The Safe checks, then sends.** The Safe confirms the payment on-chain (sender, amount, split
   address) and only then sends the seat with `transferNFTs([id], member)`. Seats are never sent
   before payment.
4. **The split distributes.** Anyone can trigger distribution on splits.org (or recipients withdraw):
   half arrives in the Main Safe, half in the partner wallet.
5. **The partner pays the artist** for that seat, within the time set in the partner agreement, and
   reports the payout.

## Record of sales (public)

Each sale gets one row in a public ledger, kept at `payments/seat-sales.csv` once sales start:

| seat id | artist (from metadata) | member wallet | payment tx | amount | partner payout reference | date |
|---|---|---|---|---|---|---|

This lets anyone check that each artist received half of every sale of their work.

## Before the first sale (checklist)

- [ ] **Partner** chosen, and its wallet address confirmed in writing.
- [ ] **Written partner agreement**, covering:
  - which artists it pays, and how;
  - payout time after distribution;
  - currency and conversion;
  - fees;
  - reporting to PsyDAO;
  - what happens if an artist can't be reached.
- [ ] **Artists' consent**, for each artist whose work is on a seat that can be sold. That includes
  the art for ids 35–54, which is not created yet; see [METADATA.md](METADATA.md).
- [ ] **Split created** from the Main Safe on splits.org, with:
  - the two recipients above, 50/50;
  - a 0% distributor fee;
  - the Main Safe as controller.

  If the Splits app cannot be used directly from the Safe, a signer creates it and the controller
  is set to the Main Safe in the same step. Check it on splits.org and Etherscan.
- [ ] **Split address published** here, in GOVERNANCE.md §5, and on psydao.world.
- [ ] **Test with a small amount:** send a tiny amount to the split, distribute it, and confirm both
  halves arrive.
- [ ] **Tax and compliance** for paying the partner checked by whoever handles PsyDAO's accounts.

## Risks and how they are handled

| Risk | Handling |
|---|---|
| A member pays the wrong address | Only the address published on psydao.world and here is valid. The Safe never sends a seat without a payment to that address |
| The partner doesn't pass payments on | Written agreement, public sales ledger with payout references, and the Safe can redirect the artists' share to a new partner (a controller change, announced) |
| The partner wallet is lost or compromised | The Safe updates the split to a new partner wallet. Funds already distributed to the old wallet are the partner's responsibility under the agreement |
| A member pays but the seat isn't sent | The Safe sends within the 14-day window after confirming payment; if a seat can't be sent, the Safe refunds from the treasury |
| The Splits contracts | Third-party code, outside this repo's audit and bug bounty scope. It is used only as a payment address, and the seat contract does not depend on it |

## Change log

- 2026-10-14: design agreed: 50/50, one split, partner wallet for the artists, Main Safe as
  controller, seat assigned before payment.
