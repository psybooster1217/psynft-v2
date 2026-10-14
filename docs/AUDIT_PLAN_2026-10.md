# In‑depth audit plan — October 2026

> **Status: EXECUTED 2026‑10‑10/11.** Results: **[AUDIT-2026-10.md](AUDIT-2026-10.md)**.
> - W0–W9 are done, except two W6 items deferred to the mainnet deployment (nothing is deployed
>   yet): the keystore/Ledger flow end to end, and `--verify` to Exact Match. There is no Sepolia run.
> - W10 (external audit) is replaced by the bug bounty ([BUG_BOUNTY.md](BUG_BOUNTY.md)), plus an
>   optional external review. There is no external-audit gate, so the §8 criterion "External audit
>   received" no longer applies.
> - Tier 3 (Sepolia) is replaced by a fork rehearsal through the real Main Safe; the Safe-app
>   click-through stays with the signers. The §8 Sepolia criterion no longer applies.
> - Exit criteria still open are the human steps: pin the metadata, launch the bounty, the PSYC
>   vote, and re-run `CutoverSweep.fork.t.sol` at the latest block within 24 h of the §4d execution.
>   The Step 0 / §0a / §0b handovers to the Main Safe come first (added 2026-10-14; see the
>   report's [addendum](AUDIT-2026-10.md#addendum-final-review-2026-10-14)).
>
> The text below is the original plan, kept as written (except a reference to an unpublished
> internal draft in W4, removed 2026-10-14).

**Drafted:** 2026‑10‑10 · **Target:** PsyNFT V2 (`src/PsyNFTV2.sol`), its scripts, snapshot tool, admin
UI, and the new cutover / exit‑pool sweep in [DEPLOYMENT_RUNBOOK.md](DEPLOYMENT_RUNBOOK.md) §0b–§4d ·
**Companion:** [TESTING_HANDBOOK.md](TESTING_HANDBOOK.md) (how to run every function by hand)

---

## 1. Where things stand

**Last audit: 2026‑07‑06.** Two internal passes that day:
[SECURITY_REVIEW.md](SECURITY_REVIEW.md) (adversarial multi‑agent review, 3 confirmed findings, all
fixed) and [AUDIT.md](AUDIT.md) (full stack, 11 items fixed or accepted). **No external audit yet.**

What changed after it, and was never reviewed:

| Date | Change | Risk |
|---|---|---|
| 07‑11 | UI: wallet disconnect/switch + wrong‑wallet warning (`App.tsx`), `Dashboard.tsx`, new `MetadataPanel.tsx` | Low–Med |
| 07‑11 | `Deploy.s.sol`: BASE_URI warnings | Low |
| 09‑23 | Runbook §0b, §1, §4d: CoreLogic → Main Safe, Safe fallback handler, exit window, **one Safe batch that sweeps the ~3.11 ETH V1 exit pool** through V1 Treasury code | **High.** It moves money and relies on V1 contracts this repo never reviewed |
| 09‑23 | `test/CutoverSweep.fork.t.sol`, CI glob change | **uncommitted** |

AUDIT.md's own re‑audit trigger ("any change to … the scripts") has fired.

**Unchanged since the audit:** `src/PsyNFTV2.sol` (sha256 `05186f74…`), `Migrate.s.sol`,
`Handoff.s.sol`, `snapshot.mjs`, `holders.json`.

**Baseline measured 2026‑10‑10**

- `forge test` deterministic: **41/41 pass**. Fork tests against live mainnet (`eth.drpc.org`):
  **4/4 pass**. The sweep rehearsal sends 3.110298529411764706 ETH to the Safe and leaves
  0.094251470588235294 ETH claimable by the token‑0 exiter. README still says "42 tests"; the real count
  is 45.
- Live mainnet matches the snapshot: V1 `tokenId` 34, burnt 1, `rageQuitAllowed` **true**, pool
  3.11 ETH, CoreLogic owner still `0x00c1…6061` (§0b not executed yet).
- Every function was exercised in the local sandbox (results are in the handbook). Each one behaved
  as specified, including every wrong‑role and bad‑input revert.

**New finding during the baseline (fix before any deploy):**

> **META‑1 (High, operational): the collection's metadata gateway no longer exists.**
> `red-literary-tiglon-645.mypinata.cloud` returns NXDOMAIN from Google and Cloudflare DNS. V1's
> `baseUri` points at it. So do the `image` field inside every metadata JSON, the runbook's
> `BASE_URI`, `.env.example` and `sandbox/start.sh`. The content itself is intact on IPFS: metadata
> 0–33 and the PNGs load through `gateway.pinata.cloud`. Deploying V2 as documented would ship
> broken art from block 0. The admin UI's art preview also fails, because it reuses the baseUri host.
> **Fix:** re‑publish the metadata folder with gateway‑independent `image: "ipfs://<imgCID>/NNN.png"`.
> Pin it on Pinata **and** a second pinning service, then deploy with `BASE_URI=ipfs://<newCID>/`.
> Confirm V1 tokens on OpenSea are only showing cached art. Update [METADATA.md](METADATA.md).

---

## 2. What's at stake

| Asset | Where |
|---|---|
| 33 member seats (PSYC votes via Snapshot) + 20 new seats from batch 7 | PsyNFT V2 |
| ~3.11 ETH exit pool, swept to the Main Safe in §4d | V1 Treasury `0xB452…3d61` |
| 0.0943 ETH owed to the token‑0 exiter. **Must stay claimable** | V1 Treasury `pendingBalances` |
| Art / metadata integrity | IPFS + `baseUri` |
| Admin control | Main Safe `0xB253…50e5` (2‑of‑4, v1.3.0) |

**Roles after cutover:** owner = Main Safe. core = Main Safe. treasury = V1 Treasury during the
sweep, then the Main Safe.

**Trust properties to put in front of the DAO** (all V1 parity, all confirmed in the sandbox):

- treasury can **burn any member's seat without their consent**;
- core **cannot revoke or shorten** a transfer approval once granted (`Transfer Request Currently Active`);
- owner can switch transfer controls off and replace the metadata at any time.

---

## 3. Scope

**In:**

- `src/PsyNFTV2.sol` and its diff against `reference/PsyNFT.v1.sol`
- `script/Deploy|Migrate|Handoff.s.sol`
- `snapshot/snapshot.mjs` + `holders.json`
- `ui/src/**`
- runbook §0b–§5
- `.github/workflows/ci.yml`
- **New:** the verified Etherscan source of the V1 functions the cutover calls:
  - Treasury: `exit`, `withdrawUserFunds`, `updatePsyNftContract`, `setCoreContract`, and the
    `rageQuitBalance` / `pendingBalances` / `userBalances` accounting
  - CoreLogic: `switchRageQuit`, `rageQuit`, `transferOwnership` / `acceptOwnership`

**Out:** OpenZeppelin internals (re‑verify byte‑identity only), the canonical Safe contracts, and the
Snapshot.org platform.

---

## 4. Workstreams

### W0 — Freeze and baseline (½ day)
- Commit the uncommitted runbook, CI and `CutoverSweep` changes plus this plan. Tag
  `audit-2026-10-base`, record the file hashes, and audit against that tag only.
- `forge build --sizes`, both test suites, `forge coverage --report summary` (record line and branch
  numbers), `forge snapshot` (gas baseline).
- Regenerate the ABI (`forge inspect PsyNFTV2 abi`) and diff it against `ui/src/abi.ts`.

### W1 — Automated analysis (½ day)
- Slither (`pip install slither-analyzer`, then `slither . --filter-paths lib`), Aderyn and
  `forge lint`. None are installed yet. Triage every hit as a true positive or a false positive with
  a reason.
- Check the solc 0.8.20 known‑bugs list against the language features the contract uses.
- `npm audit` in `ui/`.

### W2 — Manual contract review (1–1.5 days)
Line by line, plus the V1 diff. Each question ends as a finding, or as "verified clean" with a test.

1. **Approval lifecycle.** Grants are never cleared after use and cannot be revoked while active.
   Can a stale grant be abused, e.g. when a token comes back to an earlier holder, or for ids that
   were burnt on V1 and re‑minted by migration? What is the recovery if core grants a 10‑year window
   to the wrong address? Decide: accept (V1 parity) or add `revokeTransfer` (breaks parity, needs a
   re‑audit).
2. **Burn without consent.** Document it as a trust property in the PSYC proposal. Check that events
   are correct for both contract‑held and member‑held burns.
3. **`finalizeMigration` input trust.** `previousFibonacci_` is unchecked. A typo (210 for 21) would
   permanently distort or gas‑brick the schedule. An oversized `nextTokenId` skips ids forever.
   Confirm the script sources both from the snapshot plus live V1. Decide whether to add
   `require(previousFibonacci_ < nextTokenId)`.
4. **Gate completeness.** Check every path that moves a token: `transferFrom`, both
   `safeTransferFrom` overloads, the contract‑side `_safeTransfer`, and burn. Confirm members'
   `approve` / `setApprovalForAll` cannot route around the gate. UX note: marketplace listings will
   succeed and then the sale reverts.
5. **Contract‑held tokens.** These are ungated. Confirm nobody can ever become an approved operator
   for tokens the contract holds.
6. **Fibonacci gas ceiling (CON‑2).** Re‑measure against the current mainnet block gas limit.
7. **Rescue functions.** ETH (no `receive`, so only force‑sent ETH can arrive), non‑standard ERC‑20s,
   and foreign ERC‑721s. Seen in the sandbox: rescuing a foreign NFT that has its own transfer gate
   reverts inside the foreign contract. That is expected; document it.
8. **Ownership.** Ownable2Step, renounce blocked, `pendingOwner` overwrite, Safe as owner from
   block 0.
9. **Events and indexers.** Every admin action emits. Migration mints appear as `Transfer` from
   `0x0`. Check how Snapshot's erc721 strategy counts the contract's own balance.
10. **Metadata.** `tokenURI` for burnt and unminted ids, the trailing `/` requirement, and gateway
    centralisation (see META‑1).
11. **Build reproducibility.** `paris` EVM, optimizer at 1M runs. The Etherscan "Exact Match" must
    be reproducible from the tagged commit.

### W3 — Property‑based testing (1–1.5 days). This is the biggest gap: there are 0 fuzz and 0 invariant tests today.
- **Fuzz:** `approveTransfer(id, to, window)` × `transferFrom(to', t)`. A transfer must succeed
  **iff** `to' == to` and `t ≤ expiry`, or controls are off, or the token is contract‑held. Also
  fuzz arbitrary `migrateBatch` arrays and `finalizeMigration` parameters.
- **Invariants** (handler‑based `invariant_*`):
  - I1: live tokens = minted − `totalTokensBurnt`
  - I2: `tokenId` never decreases
  - I3: `owner() != 0`, always
  - I4: after finalize, `migratedCount` is frozen and `migrateBatch` always reverts
  - I5: with controls on, a member‑held token changes owner only through a live grant to exactly
    that recipient, or through burn
  - I6: each piece of role state changes only through its own role
  - I7: `initialMint` and migration are mutually exclusive
- **Symbolic (optional):** Halmos on I5 and on access control.
- **Mutation testing:** Gambit (or `vertigo-rs`) on `PsyNFTV2.sol`. Every surviving mutant gets
  either a new test that kills it or a written justification. This shows whether the 45 existing
  tests would actually catch a regression.

### W4 — Cutover / exit‑pool sweep (1 day). This is where the money is.
- Save the verified V1 Treasury and CoreLogic (proxy + implementation) sources into `reference/` and
  review the functions in scope.
- Questions to answer:
  - Is `exit(id, n, user)` exactly `rageQuitBalance ÷ (n − burnt)`? Does rounding leave dust that is
    stuck forever?
  - Does `withdrawUserFunds` pay the Safe and leave `pendingBalances` exactly equal to what past
    exiters are owed?
  - Is there reentrancy when ETH goes to a Safe that has a fallback handler?
  - Does `updatePsyNftContract` have side effects?
  - Is `0xf48f…e5e4` the canonical CompatibilityFallbackHandler for the Main Safe's exact version?
    Check it against the safe‑deployments registry.
  - Does the Transaction Builder batch go through MultiSendCallOnly (CALL, never DELEGATECALL)?
- Produce the **exact Transaction Builder JSON** for §4d. Decode every calldata entry with `cast`.
  Replay it on a fork with the Safe impersonated, then rehearse the real signing path on Sepolia (W7).
- Re‑run `CutoverSweep.fork.t.sol` at the latest block **within 24 h before execution**. Exits during
  the window change the numbers.
- Governance: the PSYC proposal must name the exit‑window dates and the sweep.

### W5 — Snapshot and migration data (½ day)
- The committed snapshot is from block 25,473,885 (July). Regenerate it at the freeze block after
  the exit window closes, with `--verify-rpc`. A dry run now should produce an identical file while
  the state is unchanged.
- Some holders are contracts (e.g. Safes). `_mint` skips the receiver check. Confirm each such holder
  can actually use its seat later, for example whether it can receive a `safeTransfer` without a
  fallback handler.

### W6 — Scripts and deploy path (½ day)
- Re‑review the 07‑11 `Deploy.s.sol` change.
- Run the keystore/Ledger flow end to end on Sepolia.
- Get `--verify` to Exact Match.
- Point `BASE_URI` at the new `ipfs://` CID from META‑1.

### W7 — Admin UI (1 day)
- Review the 07‑11 diffs (`App.tsx`, `Dashboard.tsx`, `MetadataPanel.tsx`).
- Gaps to decide on:
  - **UI‑7, Safe support is claimed but not built.** The README says to connect the Safe via
    WalletConnect, but the app only supports an injected wallet (`window.ethereum`). There is no
    WalletConnect and no Safe Apps SDK. Today, owner actions have to go through the Safe Transaction
    Builder. Either add a Safe App manifest so the panel opens inside app.safe.global, or correct the
    README.
  - **UI‑8, wrong chain label without a wallet.** With no wallet connected, the app assumes chain 1
    (label and Etherscan link) while it actually reads from `VITE_RPC_URL`. Seen in the sandbox: an
    "Etherscan ↗" link for a local contract. Add a chain‑mismatch banner.
  - **UI‑9, art preview depends on the baseUri host.** `MetadataPanel` builds its gateway from the
    baseUri host, so it breaks with META‑1. Fall back to a working public gateway. Also confirm the
    `ipfsToHttp` scheme filter covers every `src` and `href`.
- `npm audit`, a clean `npm run build`, and `abi.ts` matching `forge inspect`.
- Do the full click‑through from [TESTING_HANDBOOK.md](TESTING_HANDBOOK.md), including every wrong‑role
  attempt. Simulation should show the revert reason before the wallet ever opens.

### W8 — Supply chain and CI (¼ day)
- SHA‑pin the GitHub Actions (CI‑1) and pin the Foundry version.
- Re‑verify that `lib/` OpenZeppelin is byte‑identical to v5.0.2.
- Add a `MAINNET_RPC_URL` secret (archive‑capable, e.g. drpc) so the fork tests run in CI.

### W9 — Report and fixes (½–1 day)
- Write `docs/AUDIT-2026-10.md` in AUDIT.md's format (ID · severity · layer · status).
- Fix, add a test, re‑run everything.
- Update the README test count.

### W10 — External audit (gate before mainnet value moves)
The runbook already requires one. The scope is small: about 390 lines of contract, three scripts, the
§4d batch, and the V1 functions it calls. That suits a solo auditor or a small firm. Get two or three
quotes. Hand over the audit tag, this plan, and the internal reports.

---

## 5. Severity rubric

| Level | Meaning |
|---|---|
| Critical | Loss or lock of ETH or seats, or an admin takeover |
| High | Permanent brick of a core function, a wrong migration, or broken art at launch |
| Medium | Recoverable operational failure, or one that forces a redeploy |
| Low | Hardening, or UX that invites operator mistakes |
| Info | Documentation, parity notes |

---

## 6. Test environments

| Tier | What | Command | Status |
|---|---|---|---|
| 1 | Local fresh chain + contract + UI | `./sandbox/start.sh` | **Verified 2026‑10‑10** |
| 2 | Local mainnet fork with the real 33‑holder migration | `MAINNET_RPC_URL=https://eth.drpc.org ./sandbox/start.sh migrated` | **Verified 2026‑10‑10** (owners and URIs match V1) |
| 3 | Sepolia + a real test Safe: Transaction Builder signing, Etherscan verify, keystore deploy | runbook §2 + handbook Part F | To do. This is the only tier that tests the Safe path |

**Fixed today:** `sandbox/stop.sh` used to kill any process with a connection to port 5173, which
includes the browser tab looking at the UI. It now kills only the process listening on 5173.

**Proposed upgrades, highest value first:**

1. **Role‑separated mode** (`start.sh roles`): owner #0, core #1, treasury #2, members #3–#5.
   Wrong‑role behaviour becomes visible in the UI without any re‑configuration.
2. **Cutover rehearsal mode** (`start.sh cutover`): mainnet fork plus `anvil --auto-impersonate`, so
   the Main Safe can be driven directly. Runs §0b → §1 → §4d step by step and prints balances after
   each step.
3. **Built‑in sandbox wallet in the UI.** Only on chainId 31337 behind a dev flag, stripped from
   production builds. Pick an anvil account from a dropdown: no MetaMask setup and no stale‑nonce
   resets.
4. **One‑click start on Windows:** a `.claude/launch.json` entry or `start.cmd` that wraps Git Bash.

---

## 7. Schedule

| Phase | Work | Effort |
|---|---|---|
| 0 | W0 freeze/baseline + META‑1 re‑pin | ½–1 day |
| 1 | W1 automated + W8 supply chain | ¾ day |
| 2 | W2 manual contract + W4 sweep review | 2–2.5 days |
| 3 | W3 fuzz / invariants / mutation | 1–1.5 days |
| 4 | W5–W7 data, scripts, UI + Sepolia Safe rehearsal | 2 days |
| 5 | W9 report, fixes, re‑test | ½–1 day |
| 6 | W10 external audit | external |

About 7–9 working days internal, then the external audit.

---

## 8. Exit criteria (all must hold before the mainnet deploy)

- [ ] META‑1 resolved: new metadata CID pinned on two services, `tokenURI` + image resolve through
      at least two independent gateways.
- [ ] All Critical and High findings fixed. Each Medium is fixed or accepted in writing by the Safe
      signers.
- [ ] Invariant suite merged. Mutation testing has no unexplained survivors.
- [ ] Sepolia rehearsal complete through a real Safe (Part F of the handbook).
- [ ] External audit received, findings closed.
- [ ] `CutoverSweep.fork.t.sol` passes at the latest block within 24 h of the §4d execution.
- [ ] PSYC proposal passed, naming the exit window and the sweep.
