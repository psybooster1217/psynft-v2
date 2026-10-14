# Internal security & correctness review

> **Note (2026-10-14):** historical review. Its external‑audit gate and its premise about V1's owner key are superseded: there is no external‑audit gate (the public bug bounty is the independent check), and V1 PsyNFT is still owned by a former operator wallet (`0xC3aC…e445`), not by the DAO. See [AUDIT-2026-10.md](AUDIT-2026-10.md).

> **Internal, AI-assisted review.** The reviewers below were AI agents (Claude) run by the author;
> this is not a paid external audit. The public bug bounty ([BUG_BOUNTY.md](BUG_BOUNTY.md)) is the
> independent check.

> **See also:** [AUDIT.md](AUDIT.md) — the later full‑stack security audit (contract re‑pass,
> scripts, snapshot tool, admin UI, supply chain), which supersedes this document where they
> overlap.

An adversarial multi‑agent review was run over `src/PsyNFTV2.sol`, the three deploy scripts, the
snapshot tool, and the tests. Five independent reviewers (behaviour‑parity vs V1, access control,
migration correctness, ERC‑721/OZ‑v5 integration, script/snapshot safety) produced findings; each
finding was then adversarially verified by a separate agent instructed to **refute** it against the
actual code. Only findings that survived verification are listed.

**Result:** 3 confirmed (2 high, 1 low), 2 rejected. Parity, ERC‑721 integration, and access‑control
lenses returned no defects. **All confirmed findings are fixed** and covered by tests.

> This is an internal, AI-assisted review, not a substitute for an independent external audit before
> real value moves. See the runbook's audit gate.

## Confirmed & fixed

### MIG‑1 (High) — irreversible finalize with no completeness check
`finalizeMigration` locked the migration forever with no guarantee the full holder set had been
re‑minted. A truncated/stale/hand‑edited snapshot would permanently strand omitted holders (no
on‑chain path can mint ids below the resume counter).

**Fix:** contract now tracks `migratedCount` and `finalizeMigration` takes an `expectedCount` it must
equal (`"PsyNFT: Incomplete Migration"`). `Migrate.s.sol` sources `expectedCount` from the snapshot's
independent `liveCount` and cross‑checks it against live V1 (`tokenId − totalTokensBurnt`) pre‑finalize.
Tests: `test_Finalize_RejectsIncompleteMigration`, plus the fork/snapshot‑replay tests assert the count.

### SNAP‑1 (High) — transient RPC error misclassified as "burnt"
The snapshot batch call treated any per‑element error as a burn, so a rate‑limit/timeout on a live
token would silently drop that holder from an irreversible migration, warning only benignly.

**Fix:** `snapshot.mjs` now distinguishes a genuine revert (`ERC721NonexistentToken` / execution
reverted) from a transient error; ambiguous elements are retried individually; a persistent
non‑revert error **aborts** the run; and the omitted‑count must equal V1 `totalTokensBurnt` exactly
(in this contract `ownerOf` reverts iff burned) or the tool refuses to write `holders.json`.

### DEPLOY‑1 (Low) — silent zero core/treasury
`Deploy.s.sol` used `vm.envOr(..., address(0))`, so a missing/misspelled `NEW_CORE`/`NEW_TREASURY`
deployed with a zero role and only a summary line as signal.

**Fix:** loud, explicit `!! WARNING` lines when either is unset (kept non‑fatal because the Safe owner
can set them post‑deploy and neither is required by the migration itself).

## Rejected (verified not to be defects)

- **AC‑1** — "no access‑control defects" claim; the refuter could not construct any privilege‑boundary
  break. Every privileged function is correctly gated.
- **MIG‑2** — claimed the ceiling check should be `==`; rejected because a burnt top id legitimately
  leaves `nextTokenId (34) > maxLiveId+1`, so `≥` is correct and matches V1's monotonic counter.

## Non‑findings worth stating

- The `transferFrom` override correctly gates `safeTransferFrom` in OZ v5.0.2 (verified against
  `lib/openzeppelin-contracts/.../ERC721.sol`, and by `test_ControlledTransfer_GatesSafeTransferFrom`).
- Centralised `owner`/`core`/`treasury` are intentional (trust model); the Safe + `Ownable2Step`
  handoff puts ownership with the DAO's multisig instead of a single wallet, the problem that
  motivated the redeploy.
