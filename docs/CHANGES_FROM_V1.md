# V1 → V2: exact changes

V2 is a copy of the original `PsyNFT`. Every V1 function keeps its signature and access control.
The changes below are additive or defensive. Sections 7–10 were added by the October 2026 audit
([AUDIT-2026-10.md](AUDIT-2026-10.md)); they change behaviour on purpose, and each is covered by
tests in `test/AuditOct2026.t.sol`.

Reference original: [`reference/PsyNFT.v1.sol`](../reference/PsyNFT.v1.sol).
New contract: [`src/PsyNFTV2.sol`](../src/PsyNFTV2.sol).

## 1. Parameterised owner (the actual fix)

```diff
- constructor() ERC721("PsyNFT", "PSY") Ownable(msg.sender) {
+ constructor(address initialOwner) ERC721("PsyNFT", "PSY") Ownable(initialOwner) {
```

V1 hard‑coded the deployer as owner. V2 accepts an `initialOwner`, so ownership can be handed to a
**Gnosis Safe**. In practice the deploy script passes the *deployer* (so it can run the migration),
then `Handoff.s.sol` transfers ownership to the Safe via `Ownable2Step`.

## 2. One‑shot migration path (new)

Added so the 33 existing holders can be reproduced with their original token ids:

| Function | Access | Notes |
|---|---|---|
| `migrateBatch(address[] holders, uint256[] tokenIds)` | `onlyOwner` | Uses `_mint` (not `_safeMint`) so Safe/contract holders migrate without an `onERC721Received` check. Reverts on duplicate ids. Sets `migrationStarted`, increments `migratedCount`. |
| `finalizeMigration(uint256 nextTokenId, uint256 previousFibonacci_, bool controlledTransfers_, uint256 expectedCount)` | `onlyOwner` | Restores the counters, sets `initialMintCalled = true`, locks migration (`migrationFinalized`). Requires `migratedCount == expectedCount` (completeness guard) and `nextTokenId ≥` highest migrated id + 1. |

New public counter `migratedCount` records how many tokens have been re‑minted.

Guards ensuring the two deployment modes never mix:

- `migrateBatch` reverts if `initialMintCalled` (a fresh mint already ran) or `migrationFinalized`.
- `initialMint` reverts if `migrationStarted` (`"PsyNFT: Migration In Progress"`).
- After `finalizeMigration`, `batchMintInFibonacci` resumes from the restored counters unchanged.

`_migrationCeiling` (private) tracks `max(tokenId)+1` during migration to prevent finalizing below
the minted range (which would let the schedule re‑mint an existing id).

### Completeness guard (review finding MIG‑1)

Because `finalizeMigration` is irreversible, an under‑populated migration (a truncated/hand‑edited
`holders.json`, a dropped chunk, a stale snapshot) would otherwise permanently strand the omitted
holders — no on‑chain path could ever mint their ids again. The `expectedCount` parameter forces the
operator to declare the authoritative live‑token count (V1 `tokenId − totalTokensBurnt` = 33), and
the call reverts with `"PsyNFT: Incomplete Migration"` unless exactly that many tokens were migrated.
`Migrate.s.sol` sources this count from the snapshot's independent `liveCount` field **and**
cross‑checks it against live V1 on‑chain before finalizing.

### `totalTokensBurnt` restarts at 0 (documented deviation)

`finalizeMigration` restores `tokenId` and `previousFibonacci` but **not** `totalTokensBurnt`:
V2 starts at 0 and counts only V2 burns, while V1 ended at 1 (id 0). Consequence: immediately
after migration, `tokenId − totalTokensBurnt` = 34 − 0 = **34**, but only **33** tokens exist —
the V1 invariant `liveSupply == tokenId − totalTokensBurnt` does **not** hold across the version
boundary (it is off by exactly V1's burn count, 1). Nothing in this contract or the scripts relies
on that invariant post‑migration (the Migrate pre‑flight applies it to *V1's own* counters), but
any future Core contract, subgraph, or analytics that computes supply this way on V2 must use
`tokenId − totalTokensBurnt − 1` or count `ownerOf` directly. Accepted rather than patched:
the counter is informational only, and adding a restore parameter to `finalizeMigration` would
grow the trusted surface for a cosmetic number.

## 3. Events on every state change (new)

V1 emitted **no** events for admin actions. V2 adds:
`CoreUpdated`, `TreasuryUpdated`, `BaseUriUpdated`, `ControlledTransfersSet`, `TransferApproved`,
`TokenBurnt`, `Migrated`, `MigrationFinalized`, `ERC20Rescued`, `ERC721Rescued`, `ETHRescued`, and
(audit 2026-10) `TransferApprovalRevoked` plus ERC-4906 `BatchMetadataUpdate`.
(ERC‑721 `Transfer`/`Approval` were and are emitted by OpenZeppelin.)

## 4. Owner rescue helpers (new)

`rescueERC20`, `rescueERC721` (reverts on `address(this)` so it can't touch PsyNFT's own tokens),
and `rescueETH`. All `onlyOwner` + `nonReentrant`. For assets mistakenly sent to the contract.

## 5. `renounceOwnership` disabled (audit finding CON‑1)

```solidity
function renounceOwnership() public view override onlyOwner {
    revert("PsyNFT: Ownership Cannot Be Renounced");
}
```

V1 (via OZ `Ownable`) allowed the owner to renounce into `address(0)` — one transaction away from
recreating the exact lost‑owner disaster this redeploy fixes. V2 blocks it; combined with
`Ownable2Step`, ownership can only ever move to an address that actively accepts it. This is a
**deliberate deviation from V1 parity** (see [AUDIT.md](AUDIT.md)).

## 6. Minor hardening

- `onERC721Received` marked `pure` (was implicitly non‑view) — no behavioural change.
- `burn` reads the owner before burning and emits `TokenBurnt(tokenId, from)`.
- `IERC20` rescue uses OpenZeppelin `SafeERC20`.

## 7. Transfer approvals are single-use (audit 2026-10, PNFT-01)

```solidity
function _update(address to, uint256 tokenId_, address auth) internal override returns (address from) {
    from = super._update(to, tokenId_, auth);
    if (from != address(0) && approvedTransfers[tokenId_].transferExpiryDate != 0) {
        delete approvedTransfers[tokenId_];
    }
}
```

In V1 a `core` approval stayed live until its expiry even after it had been used. Two consequences:
core could not approve the *next* move of that token until the old window lapsed
(`"Transfer Request Currently Active"`), and a used approval could come back to life. Example:
owner disables controls, the token moves on, owner re-enables controls; the old approval then
authorises a transfer again without any new core decision. V2 clears the approval whenever the
token changes hands or is burnt. Mints are skipped, so batch-mint gas is unchanged.

## 8. `revokeTransfer(uint256)` (audit 2026-10, PNFT-02)

`onlyCoreContract`. Deletes a live approval and emits `TransferApprovalRevoked(tokenId)`. V1 had
no way to withdraw a mistaken approval (e.g. a 1-year window to the wrong address): it stayed
usable, and blocked a corrected one, until it expired.

## 9. Guards on irreversible / owner-typed inputs (audit 2026-10, PNFT-03, PNFT-04)

- `finalizeMigration` requires `(previousFibonacci_, nextTokenId)` to be **consecutive terms of the
  schedule's Fibonacci sequence** (2/3, 3/5 … 21/34 …), reverting `"PsyNFT: Counters Not On
  Schedule"`. V1's history only ever produces such pairs. A typo (210/34, 20/34, swapped values)
  would otherwise be locked in forever by the one-shot finalize.
- `setBaseUri` requires a non-empty URI to end with `/` (`"PsyNFT: Base URI Must End With
  Slash"`), because `tokenURI = baseUri + id` and one missing character breaks every token's art.
  An empty string is still accepted (to clear).

## 10. ERC-4906 metadata refresh (audit 2026-10)

V2 implements ERC-4906: `supportsInterface(0x49064906)` returns true, and `setBaseUri` emits
`BatchMetadataUpdate(0, type(uint256).max)`, so marketplaces re-fetch art for all tokens after a
metadata change (relevant for the META-1 re-pin and for every future Fibonacci batch).

## What did NOT change

- The Fibonacci mint schedule (`initialMint` → 3 tokens; `batchMintInFibonacci`).
- `onlyCoreContract` gating on mint/distribute/approve.
- The controlled‑transfer rule in the `transferFrom` override (and therefore `safeTransferFrom`):
  a member-held token moves only to the approved recipient before expiry (§7 only makes the
  approval single-use).
- `transferNFTs`, `approveTransfer`, `setCoreContract`, `setTreasury`, enable/disable toggles,
  `burn` (treasury‑only), `_baseURI`. (`setBaseUri` gained the slash guard, §9.)
- Storage layout of all V1 fields is preserved and kept in the same order (V2 appends new fields
  after them). Layout parity is not required for a fresh deploy, but it keeps the diff auditable.

## Carried‑over V1 quirks (documented, intentionally preserved)

- `initialMint` is gated by `onlyCoreContract`, **not** `onlyOwner`, despite its NatSpec saying
  "owner". Preserved as‑is; irrelevant to the migration path (which never calls it).
- `approveTransfer` allows `_to == address(0)` (the original intent was burn approvals). The actual
  `burn` is treasury‑gated and independent, so this is inert but preserved.
- `controlledTransfers` restricts member‑held tokens only; contract‑held tokens are freely moved by
  `core`. Unchanged.
