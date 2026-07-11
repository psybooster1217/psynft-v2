# Design

## The problem

`PsyNFT` V1 concentrates all administration in a single `owner` EOA. That key is unreachable, so:

- `core` and `treasury` can't be rotated,
- `baseUri` can't be updated,
- controlled transfers can't be toggled,
- ownership can't be moved to a safer custody model.

Nothing on the existing contract can restore access — ownership is enforced on‑chain by the lost
key. The only remedy is to deploy a new contract under known‑good control and move the community
onto it.

## The system (unchanged from V1)

PsyNFT is a **treasury/governance NFT**, not a user‑mint collection:

```
            owner (admin)                 core (distribution)          treasury
        ┌───────────────────┐        ┌────────────────────────┐    ┌─────────────┐
        │ setCoreContract   │        │ initialMint            │    │ burn        │
        │ setTreasury       │        │ batchMintInFibonacci   │    └─────────────┘
        │ setBaseUri        │        │ transferNFTs           │
        │ enable/disable    │        │ approveTransfer        │
        │   controlled xfer │        └────────────────────────┘
        └───────────────────┘
```

- New tokens are minted **to the contract itself** on a Fibonacci schedule (`3, then 2, 3, 5, 8,
  13, 21…`) and handed out by `core` via `transferNFTs`.
- Member‑held tokens are effectively **soulbound**: while `controlledTransfers` is on, a member can
  only transfer a token after `core` grants a time‑boxed `approveTransfer`.
- `treasury` may `burn`.

## Migration strategy: snapshot + owner re‑mint

Chosen over a trustless swap or a fresh start because it is the least‑effort, least‑risk option for
a small, fully‑distributed holder set (33) and requires **nothing from holders**.

```
  mainnet V1                      snapshot/holders.json                 new V2
  ──────────                      ─────────────────────                 ──────
  ownerOf(0..33) ── snapshot ──▶  { tokenIds[], owners[],   ── replay ──▶ migrateBatch(...)
  (1 burnt id 0)                    counter, prevFib,                     finalizeMigration(34,21,true)
                                    controlled }                          → schedule resumes at id 34
```

1. **Snapshot** (`snapshot.mjs`): read `tokenId` (34) and `ownerOf(id)` for every id. Burnt ids
   (ownerOf reverts) are omitted. Tokens still held by the V1 contract are recorded as such.
2. **Deploy** V2 with the deployer as temporary owner.
3. **Re‑mint** each snapshot entry to its owner via `migrateBatch` (chunked). Tokens that were
   undistributed in V1 (held by the V1 contract) are re‑pointed to the **V2 contract** so the new
   `core` can distribute them. In the current snapshot there are 0 of these — all 33 are held by
   distinct member addresses.
4. **Finalize** at the exact V1 counters (`tokenId = 34`, `previousFibonacci = 21`,
   `controlledTransfers = true`) and the authoritative `expectedCount = 33`. This locks the
   migration and lets `batchMintInFibonacci` resume: the next batch mints 21 tokens (ids 34–54),
   identical to what V1 would have done.

### Completeness is enforced, not assumed

`finalizeMigration` is one‑shot and irreversible, so a short/lossy migration must fail loudly rather
than silently strand a holder. Three layers guard this:

- **On‑chain:** the contract tracks `migratedCount` and reverts unless it equals the `expectedCount`
  the operator declares at finalize.
- **Script:** `Migrate.s.sol` requires the snapshot arrays to match the independent `liveCount`
  field, and cross‑checks `counter`/`liveCount` against **live V1** (`tokenId − totalTokensBurnt`)
  before it will finalize — on any chain where V1 is reachable.
- **Snapshot tool:** a transient RPC error is never read as a burn. Ambiguous `ownerOf` results are
  retried; a persistent non‑revert error aborts the run; and the omitted‑token count must equal V1's
  `totalTokensBurnt` exactly (in this contract `ownerOf` reverts iff the token was burned) or the
  tool refuses to write the file.

### Why `_mint`, not `_safeMint`, for migration

Some current holders may be smart contracts (Gnosis Safes, other contracts) that don't implement
`onERC721Received`. `_safeMint` would revert for them. Since every holder already custodies the
equivalent V1 token in exactly the same way, `_mint` is correct and safe here. The normal
`initialMint`/`batchMintInFibonacci` paths still use `_safeMint` to the contract (which implements
the receiver hook), unchanged from V1.

### Burnt tokens

V1 burnt id 0. Burnt ids are simply not re‑minted, so they don't exist in V2 — matching V1 exactly.
`finalizeMigration` sets `tokenId = 34` explicitly (not `maxLiveId+1`), so the counter is preserved
even though the top/bottom of the range may be burnt.

## Admin model: Gnosis Safe

The root cause was a single lost key. V2 fixes the class of failure, not just the instance:

- **owner → Gnosis Safe multisig.** Deploy with the deployer (to script the migration), then
  `Handoff.s.sol` initiates an `Ownable2Step` transfer to the Safe; the Safe calls
  `acceptOwnership()`. Two‑step transfer means a wrong address can't brick ownership.
- **core / treasury** should also be addresses/contracts the DAO controls (a Safe, or the new
  governance/distribution contract). Set them via `setCoreContract` / `setTreasury`.

## Testing strategy

- **Unit** (`PsyNFTV2.t.sol`): every function, access‑control revert, the full Fibonacci schedule
  (asserted to reproduce V1's `tokenId=34 / prevFib=21`), controlled‑transfer approval/expiry,
  migration guards, ownership handoff, and rescue helpers.
- **Deterministic snapshot replay** (`HoldersJson.t.sol`): parses the committed `holders.json` with
  the same cheatcodes the deploy script uses and asserts holder parity — no RPC required.
- **Live fork** (`Migration.fork.t.sol`): forks mainnet, snapshots real `ownerOf`, replays the
  migration, and asserts every live V1 token maps to the same owner in V2, then that the schedule
  resumes. This is the closest possible rehearsal of the mainnet run.
