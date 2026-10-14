# Design

## The problem

`PsyNFT` V1 concentrates all administration (`core`, `treasury`, `baseUri`, controlled transfers,
ownership) in a single `owner` address. V1 PsyNFT is still owned by a former operator wallet
(0xC3aC…e445), not by the DAO. Step 0 of the cutover hands it to the Main Safe (together with
CoreLogic and PsycSale, see the [runbook](DEPLOYMENT_RUNBOOK.md)); until then, V1's admin functions
are outside DAO control.

Moving V1 under the Safe does not change the contract itself. V1 still emits no events for admin
actions, allows ownership to be renounced, keeps a used transfer approval alive until it expires,
has no way to withdraw a mistaken approval, and has no guards on irreversible inputs
([CHANGES_FROM_V1.md](CHANGES_FROM_V1.md) §3, §5, §7–9). So the plan is to deploy a hardened V2
under Safe control from day one and move the community onto it.

## The system (unchanged from V1)

PsyNFT is a **treasury/governance NFT**, not a user‑mint collection:

```
            owner (admin)                 core (distribution)          treasury
        ┌───────────────────┐        ┌────────────────────────┐    ┌─────────────┐
        │ setCoreContract   │        │ initialMint            │    │ burn        │
        │ setTreasury       │        │ batchMintInFibonacci   │    └─────────────┘
        │ setBaseUri        │        │ transferNFTs           │
        │ enable/disable    │        │ approveTransfer        │
        │   controlled xfer │        │ revokeTransfer (V2)    │
        └───────────────────┘        └────────────────────────┘
```

- New tokens are minted **to the contract itself** on a Fibonacci schedule (`3, then 2, 3, 5, 8,
  13, 21…`) and handed out by `core` via `transferNFTs`.
- Member‑held tokens are effectively **soulbound**: while `controlledTransfers` is on, a member can
  only transfer a token after `core` grants a time‑boxed `approveTransfer`. In V2 that approval is
  single‑use, and `core` can cancel it with `revokeTransfer`.
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

The root cause was single‑key administration outside DAO control. In V2 no single lost key can
freeze the contract; it would take losing 3 of the 4 Safe keys:

- **owner → Gnosis Safe multisig.** Deploy with the deployer (to script the migration), then
  `Handoff.s.sol` initiates an `Ownable2Step` transfer to the Safe; the Safe calls
  `acceptOwnership()`. Two‑step transfer means a wrong address can't brick ownership.
- **core / treasury** should also be addresses/contracts the DAO controls (a Safe, or the new
  governance/distribution contract). Set them via `setCoreContract` / `setTreasury`.

## Testing strategy

**99 tests** (91 deterministic + 8 mainnet‑fork), all passing locally and in CI. Coverage is 100%
of lines and branches of the contract (`src/PsyNFTV2.sol`). The fork suites skip unless
`MAINNET_RPC_URL` is set. Details and results: [AUDIT-2026-10.md](AUDIT-2026-10.md).

- **Unit** (`PsyNFTV2.t.sol`): every function, access‑control revert, the full Fibonacci schedule
  (asserted to reproduce V1's `tokenId=34 / prevFib=21`), controlled‑transfer approval/expiry,
  migration guards, ownership handoff, and rescue helpers.
- **Audit regressions** (`Audit.t.sol`, `AuditOct2026.t.sol`): PoCs for the July 2026 internal
  audit's findings ([AUDIT.md](AUDIT.md)), and tests for the October 2026 changes (single‑use
  approvals, `revokeTransfer`, the Fibonacci finalize guard, the base‑URI guard and ERC‑4906) plus
  every branch the baseline suite never hit. Includes the **4 fuzz tests**.
- **Invariants** (`test/invariant/`): **7 invariants** checked against a random‑action handler in
  which every role acts in random order with random inputs. 256 sequences × 100 calls per
  invariant, about 1,800 sequences and 179,000 calls in total.
- **Mutation kills** (`MutationKills.t.sol`): tests written to kill the mutants that survived the
  first mutation run. Mutation score 95.5% (170/178; the 8 survivors are proven equivalent), see
  [`audit/2026-10/mutation/`](../audit/2026-10/mutation/results.md).
- **Deterministic snapshot replay** (`HoldersJson.t.sol`): parses the committed `holders.json` with
  the same cheatcodes the deploy script uses and asserts holder parity — no RPC required.
- **Live fork, migration** (`Migration.fork.t.sol`): forks mainnet, snapshots real `ownerOf`,
  replays the migration, and asserts every live V1 token maps to the same owner in V2, then that
  the schedule resumes.
- **Live fork, cutover** (`CutoverSweep.fork.t.sol`): replays the cutover and the exit‑pool
  wind‑down against live mainnet state.
- **Real‑Safe rehearsal** (`SafeRehearsal.fork.t.sol`): the whole cutover run through the real Main
  Safe contract on a mainnet fork, with its 2‑of‑4 threshold and its owners' addresses
  (approved‑hash signatures), using the exact calldata the signers will import. It is a
  simulation: no signer actually signed anything. This is the closest rehearsal of the mainnet run.
