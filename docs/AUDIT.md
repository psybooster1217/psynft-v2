# Internal security audit — full stack

> **Note (2026-10-14):** historical report. Its external‑audit gate and its premise about V1's owner key are superseded: there is no external‑audit gate (the public bug bounty is the independent check), and V1 PsyNFT is still owned by a former operator wallet (`0xC3aC…e445`), not by the DAO. See [AUDIT-2026-10.md](AUDIT-2026-10.md).

**Date:** 2026‑07‑06 · **Scope:** everything in this repository · **Status:** all findings fixed or accepted‑documented

This audit covers the four layers of the system end‑to‑end:

1. **Smart contract** — `src/PsyNFTV2.sol` (fresh pass, including re‑verification of the fixes from the earlier adversarial review, `docs/SECURITY_REVIEW.md`)
2. **Operational tooling** — `script/Deploy|Migrate|Handoff.s.sol`, `snapshot/snapshot.mjs`
3. **Admin dApp** — `ui/` (first security review of this layer)
4. **Repo, supply chain & CI** — vendored deps, npm deps, secrets, workflow

**Methodology:** line‑by‑line manual review; PoC/regression tests for every substantive claim
([test/Audit.t.sol](../test/Audit.t.sol)); `forge lint`; `npm audit`; byte‑level integrity diff of
vendored OpenZeppelin against upstream; GitHub Security Advisory database queries for every
dependency; live browser verification of UI fixes. **42/42 Foundry tests pass** (including the
live‑mainnet fork migration) and the UI builds clean after all changes.

> This is a rigorous internal, AI-assisted audit (the author working with Claude), not a substitute
> for an independent external firm before real value moves. The runbook's external‑audit gate stands.

---

## Findings

| ID | Severity | Layer | Title | Status |
|---|---|---|---|---|
| CON‑1 | **Low / high‑relevance** | Contract | `renounceOwnership` could recreate the V1 disaster | **Fixed** |
| UI‑1 | **Medium (operational)** | UI | holders.json loader could strand V1‑held tokens | **Fixed** |
| SCR‑1 | **Medium (operational)** | Scripts | Scripts forced a raw `PRIVATE_KEY` for mainnet | **Fixed** |
| SNAP‑2 | **Low→Medium** | Snapshot | Migration's root of trust rested on a single RPC | **Fixed** |
| DEP‑1 | **Moderate (dev‑only)** | Supply chain | esbuild/vite dev‑server advisory (GHSA‑67mh‑4wv8‑2f99) | **Fixed** |
| UI‑2 | **Low** | UI | `VITE_*` env vars ship in the public bundle | **Fixed (docs)** |
| CON‑2 | Info | Contract | Fibonacci batch gas ceiling (~10 batches out) | Accepted, documented + PoC |
| CON‑3 | Info | Contract | `transferNFTs` receiver callback reentrancy is inert | Verified by PoC, no change |
| CON‑4/5 | Info | Contract | Burnt‑id approvals inert; core can set unbounded approval windows | Accepted (V1 parity, trusted role) |
| UI‑3/5/6 | Info | UI | Single‑RPC reads; no chain‑mismatch guard; pasted‑address trust | Accepted, mitigations noted |
| CI‑1 | Info | CI | Actions pinned by tag, not SHA | Recommendation |

---

### CON‑1 (Low, high relevance) — `renounceOwnership` was live · **FIXED**

OZ `Ownable` ships a public `renounceOwnership()` that sets the owner to `address(0)` forever.
This entire project exists because V1's admin surface sits with a single wallet outside DAO control —
and one mistaken Safe transaction could have done worse: left V2 with no owner at all, permanently.

**Fix:** overridden to revert (`"PsyNFT: Ownership Cannot Be Renounced"`). Combined with
`Ownable2Step`, ownership is now *indestructible by construction*: it can only move to an address
that actively calls `acceptOwnership()`, and can never be renounced into the void.
This is a deliberate, documented deviation from V1 parity (V1 had the same footgun).
Test: `test_RenounceOwnership_Blocked`.

### UI‑1 (Medium, operational) — holders.json loader could strand tokens · **FIXED**

`Migrate.s.sol` re‑points snapshot entries owned by the V1 contract (undistributed tokens) to the
new contract; the UI's "paste holders.json" loader filled owners **verbatim**. A future snapshot
containing V1‑held tokens, migrated via the UI, would have minted them to the dead V1 address —
irrecoverably (nothing can move a V2 token out of the V1 contract). Today's snapshot has 0 such
tokens, but the loader was a loaded gun for any regenerated snapshot.

**Fix:** the loader now mirrors the script — V1‑owned entries are re‑pointed to the connected
contract (with an explicit "N re‑pointed" message), zero‑address owners abort the load, and
re‑pointing without a contract address entered is rejected. **Verified live in the browser**: a
pasted snapshot containing `0x6c6A…402d` produced the re‑pointed field + message; a zero‑address
snapshot refused to load.

### SCR‑1 (Medium, operational) — raw `PRIVATE_KEY` was mandatory · **FIXED**

All three scripts did `vm.envUint("PRIVATE_KEY")` (revert if unset), so the runbook's
hardware‑wallet guidance was impossible to follow — operators were forced to put a mainnet key
into an environment variable (shell history, process env, `.env` on disk).

**Fix:** `PRIVATE_KEY` is now optional. When unset, scripts call `vm.startBroadcast()` and the
signer comes from Foundry's `--account <keystore>` / `--ledger` / `--trezor`. `Deploy.s.sol`
additionally refuses to run if the effective deployer is Foundry's *default sender* (which would
mean no signer was configured and an unusable address would become the temporary owner).

### SNAP‑2 (Low→Medium) — single‑RPC root of trust · **FIXED**

`holders.json` is the input to an **irreversible** migration, and it was derived from one RPC
provider. A compromised or lying provider could have rewritten holder addresses wholesale; the
only backstop was the runbook's manual Etherscan spot‑check.

**Fix:** `snapshot.mjs --verify-rpc <url>` re‑reads the counter, every live owner, and every burnt
id from an **independent second provider** at the same pinned block and aborts on any mismatch;
the output records `crossVerified: true`. Provider error pages (HTML/rate‑limits) are now clean,
retryable failures that can never be misread as data — the tool fails closed (observed in testing:
a rate‑limited provider aborted the run without writing the file). The committed snapshot was
regenerated with cross‑verification: **33 owners + 1 burnt id confirmed by two providers**
(publicnode × drpc, block 25,473,885). The runbook now requires `--verify-rpc` for the production
snapshot.

### DEP‑1 (Moderate, dev‑only) — esbuild/vite dev‑server advisory · **FIXED**

`npm audit` flagged [GHSA‑67mh‑4wv8‑2f99](https://github.com/advisories/GHSA-67mh-4wv8-2f99):
esbuild ≤0.24.2 lets **any website open in your browser** send requests to a running local dev
server (`npm run dev`) and read the responses (source exposure; no production impact — the
`dist/` bundle contains none of these tools).

**Fix:** upgraded `vite` 5.4→8.1.3 and `@vitejs/plugin-react` →6.0.3. `npm audit`: **0
vulnerabilities**. Build and app behaviour verified unchanged.

### UI‑2 (Low) — env vars ship in the bundle · **FIXED (docs)**

Every `VITE_*` variable is compiled into the public JS bundle. A keyed RPC URL
(`VITE_RPC_URL=https://…/v2/SECRET_KEY`) in a hosted build hands the key to every visitor.
**Fix:** explicit warnings in `ui/.env.example`; recommendation to use keyless public endpoints or
domain‑restricted keys for hosted builds.

---

### Accepted / informational

**CON‑2 — Fibonacci batch gas ceiling (PoC‑measured).** Batch sizes after the migration resume
point: 21, 34, 55, 89, 144, 233, 377, 610, 987, 1597… Measured costs
(`test_FibonacciBatch_GasCeiling`): **610 → 16.5M gas · 987 → 26.7M · 1597 → 43.2M**. Whichever
batch first exceeds the prevailing block gas limit makes `batchMintInFibonacci` permanently
uncallable (the tx cannot fit; it reverts cleanly; existing tokens and transfers are unaffected).
At a 30M limit that is the **10th batch** (≈4,100 total supply); the 987 batch already needs a
nearly‑empty block. This is V1's own design carried over 1:1 — changing it would break parity.
The DAO has years of runway and can address it in a future version if the schedule ever gets there.

**CON‑3 — distribution callback reentrancy is inert (PoC‑verified).** `transferNFTs` performs an
`onERC721Received` callback (no `nonReentrant`, matching V1). A hostile recipient re‑entering
during the callback was tested against every state‑changing function
(`test_ReentrantReceiver_CannotEscalate`): all six escalation attempts revert (role gates +
controlled‑transfer gate; OZ v5 fully updates ownership before the callback). **0 escalations.**

**CON‑4/5 — trusted‑role latitude (V1 parity).** `approveTransfer` accepts burnt ids (inert:
the transfer itself reverts) and unbounded approval windows (core is a trusted role). Unchanged
by design.

**Rescue surface (PoC‑verified).** `rescueERC721(self)` is blocked by require;
`rescueERC20(self)` cannot move NFTs (no `transfer(address,uint256)` exists on the contract —
the call reverts; pinned by `test_Rescue_CannotMovePsyNFTs`).

**UI‑3/5/6 — informational.** Dashboard reads trust one RPC (writes are still guarded by wallet
+ simulation); no explicit chain‑mismatch banner (simulation fails loudly on the wrong chain);
the contract‑address field trusts the operator (Etherscan link provided for verification —
always confirm the address against the announcement before signing).

**CI‑1 — recommendation.** `actions/checkout@v4` / `foundry-rs/foundry-toolchain@v1` are mutable
tags; SHA‑pinning is stricter supply‑chain hygiene. Low impact here (CI holds only a read‑only
RPC secret; `pull_request` runs from forks don't receive secrets).

---

## Verified‑clean (checked, no finding)

- **Access control matrix** — every state‑changing function gated correctly (owner / core /
  treasury / pendingOwner); no privilege‑escalation path found (re‑confirmed after the earlier
  adversarial review).
- **Prior fixes intact** — `migratedCount`/`expectedCount` completeness guard, snapshot
  burnt‑vs‑transient classification, migrate/finalize state machine: re‑reviewed, all sound.
- **Controlled‑transfer gate** covers `safeTransferFrom` (routes through the override in OZ
  v5.0.2) and cannot be bypassed via `approve`/`setApprovalForAll` (the gate checks the
  *destination*, not the caller).
- **Vendored OpenZeppelin v5.0.2 is byte‑identical to upstream** (full recursive diff) — no
  tampering, and pinning prevents silent upgrades.
- **Advisory sweep:** OZ 5.0.2 unaffected by all published advisories (Base64 fix landed *in*
  5.0.2; `Bytes.lastIndexOf` affects ≥5.2.0; the rest are 4.x or unused components). viem: no
  published advisories; `npm audit` clean. solc 0.8.20/paris: no known‑issue exposure for this
  code.
- **Secrets hygiene:** no keys/mnemonics/API keys anywhere in the repo; `.env` git‑ignored and
  absent; test keys used during fork rehearsal were anvil's well‑known dev accounts only.
- **No XSS surface in the UI:** no `dangerouslySetInnerHTML`; all dynamic values render as React
  text nodes; external links are built only from checksummed addresses on hardcoded explorer
  hosts.
- **`forge lint`:** only the two expected `block-timestamp` notes (day‑scale approval windows;
  ±15s validator drift immaterial).

## Residual risks (inherent, not fixable in code)

1. **Trusted roles are trusted.** Owner/core/treasury can do everything their role allows; the
   security model is the Safe's signer set. Use a meaningful threshold (e.g. 2/3+), distinct
   devices, and keep signers' keys off hot machines.
2. **The migration is only as correct as its snapshot moment.** Freeze communications around the
   pinned block; anyone receiving a V1 token after it won't carry to V2 (the dual‑RPC +
   completeness guards make the snapshot *faithful*; they can't make it *current*).
3. **The dApp operator must verify the contract address** they paste — the UI operates on
   whatever address it's given.

## Re‑audit triggers

Re‑run this audit (and regenerate `ui/src/abi.ts`) after **any** change to `src/`, the scripts,
or the snapshot tool; re‑run `npm audit` before each UI deploy.
