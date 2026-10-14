# Testing handbook: every PsyNFT V2 function, step by step

A hands-on guide to testing the contract and the admin panel on a **throwaway local blockchain**.
No real money, no real keys, no browser wallet needed, and nothing can break.

Every "Expected" below was observed on the sandbox during the October 2026 internal, AI-assisted
audit ([AUDIT-2026-10.md](AUDIT-2026-10.md)).

> Time needed: about 5 min setup, about 60 min for Parts B–D. Legend: ✅ should succeed ·
> ❌ should fail with the quoted reason (that is a pass) · 🖱 in the admin panel · ⌨ in a terminal

---

## Part A: Setup

### A1. Start the sandbox
Open **Git Bash** (Start menu → "Git Bash") and run:

```bash
cd psynft-v2          # your clone of this repository
./sandbox/start.sh
```

Wait for **`SANDBOX READY`**, then open **http://localhost:5173**. Leave the Git Bash window open:
Ctrl‑C (or closing it) stops everything.

| Mode | Command | Use it for |
|---|---|---|
| fresh (default) | `./sandbox/start.sh` | Parts B–C. One account (#0) is owner + core + treasury |
| roles | `./sandbox/start.sh roles` | Part D. Owner #0, core #1, treasury #2 |
| migrated | `MAINNET_RPC_URL=https://eth.drpc.org ./sandbox/start.sh migrated` | Part F. A copy of mainnet with the real 33 holders migrated |

In fresh and roles mode the contract is always at `0x5FbDB2315678afecb367f032d93F642f64180aa3`.

### A2. Pick an account (no wallet needed)
Top right, **Sandbox account…** lists the local chain's 10 test accounts. The local chain signs for
them itself, so no private key is involved. Pick one, and the panel shows its roles (e.g.
**owner · core · treasury**). **Disconnect** returns to the picker.

| Account | Address | Role in fresh mode |
|---|---|---|
| #0 | `0xf39F…2266` | owner + core + treasury |
| #1 | `0x7099…79C8` | member A / wrong-role tester |
| #2 | `0x3C44…93BC` | member B |
| #3 | `0x90F7…b906` | outsider / future owner |

Full addresses, for pasting into fields:
- #1 `0x70997970C51812dc3A010C7d01b50e0d17dc79C8`
- #2 `0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC`
- #3 `0x90F79bf6EB2c4f870365E785982E1f101E93b906`

**How a failure looks.** Every button **simulates first**. When a call would fail, the card shows
`…reverted with the following reason: <reason>` and nothing is sent. That is the ❌ pass condition.

### A3. A terminal for three steps (C6, C11, C12)
Open a second Git Bash window and paste:

```bash
cd psynft-v2; export PATH="$HOME/.foundry/bin:$PATH"
export R=http://127.0.0.1:8545 C=0x5FbDB2315678afecb367f032d93F642f64180aa3
export K0=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
```

`K0` is the local chain's well-known **public** test key for #0. Never use it on a real network.

### Reset at any time
Ctrl‑C the sandbox and run `./sandbox/start.sh` again for a brand-new chain.

---

## Part B: Read-only checks (dashboard)

| Field | Expected on a fresh sandbox |
|---|---|
| name / symbol | `PsyNFT (PSY)` |
| owner / core / treasury | all `0xf39F…2266` |
| pendingOwner | unset (0x0) |
| tokenId (next) · previousFibonacci | `0` · `2` |
| totalTokensBurnt · migratedCount | `0` · `0` |
| initialMintCalled · migrationStarted · migrationFinalized | `false` · `false` · `false` |
| controlledTransfers | `true` |
| baseUri | `ipfs://bafybeia5k2sgu3fkeyqodrmg43b7tbhd5fsmdgf7e4b34hiwrbeaybovcy/` (V1's art folder) |
| Header | "Sandbox account…" picker. **No** Etherscan link (it's a local chain) |

---

## Part C: Lifecycle tests, in order (fresh sandbox)

### C1. Initial mint (core)
| # | Account | Action | Expected |
|---|---|---|---|
| 1 | #1 | 🖱 Core · Initial mint → Execute | ❌ `PsyNFT: Caller Not Core Contract` |
| 2 | #0 | 🖱 same | ✅ "Confirmed"; tokenId **3** |
| 3 | #0 | 🖱 same again | ❌ `PsyNFT: Initial Mint Complete` |

### C2. Fibonacci batches (core)
| # | Account | Action | Expected |
|---|---|---|---|
| 1 | #1 | 🖱 Mint next Fibonacci batch | ❌ `PsyNFT: Caller Not Core Contract` |
| 2 | #0 | 🖱 same, **4 times** | ✅ tokenId 5 → 8 → 13 → 21; previousFibonacci 3 → 5 → 8 → 13 |

### C3. Distribute (core)
| # | Account | Inputs (Distribute NFTs) | Expected |
|---|---|---|---|
| 1 | #1 | `0` · #1 | ❌ `PsyNFT: Caller Not Core Contract` |
| 2 | #0 | `0` · `0x0000000000000000000000000000000000000000` | ❌ `PsyNFT: Recipient Cannot Be Zero Address` |
| 3 | #0 | `0, 1` · #1 | ✅ ownerOf(0) = #1; balanceOf(#1) = **2** |

### C4. Members can't move seats freely
| # | Account | Inputs (Member · Transfer a seat) | Expected |
|---|---|---|---|
| 1 | #1 | from #1 · to #2 · token `0` | ❌ `PsyNFT: Incorrect Receiver` |

### C5. Approve, single-use, revoke (core)
| # | Account | Action | Expected |
|---|---|---|---|
| 1 | #1 | 🖱 Approve a member transfer `0` · #2 · `3600` | ❌ `PsyNFT: Caller Not Core Contract` |
| 2 | #0 | 🖱 Approve `999` · #2 · `3600` | ❌ `PsyNFT: Non Existent Token` |
| 3 | #0 | 🖱 Approve `0` · #2 · `3600` | ✅ dashboard **approval** lookup for 0: to #2, expiry ≈ now + 1 h |
| 4 | #0 | 🖱 Approve `0` · #3 · `3600` | ❌ `PsyNFT: Transfer Request Currently Active` |
| 5 | #1 | 🖱 Transfer a seat: from #1 · to **#3** · `0` | ❌ `PsyNFT: Incorrect Receiver` (only #2 is approved) |
| 6 | #1 | 🖱 Transfer a seat: from #1 · to **#2** · `0` | ✅ ownerOf(0) = #2 |
| 7 | — | 🖱 approval lookup for `0` | **cleared** (all zero): approvals are single-use |
| 8 | #0 | 🖱 Approve `0` · #3 · `3600` | ✅ immediately possible again (V1 would have blocked this for an hour) |
| 9 | #1 | 🖱 Revoke a transfer approval · `5` | ❌ `PsyNFT: Caller Not Core Contract` |
| 10 | #0 | 🖱 Revoke · `5` | ❌ `PsyNFT: No Approval To Revoke` |
| 11 | #0 | 🖱 Revoke · `0` | ✅ approval for 0 cleared |
| 12 | #2 | 🖱 Transfer a seat: from #2 · to #3 · `0` | ❌ `PsyNFT: Incorrect Receiver` (approval revoked) |

### C6. Approvals expire
🖱 #0: Approve `1` · #2 · `60` ✅. Then ⌨ fast-forward the local clock by 61 seconds:

```bash
cast rpc evm_increaseTime 61 --rpc-url $R && cast rpc evm_mine --rpc-url $R
```

🖱 #1: Transfer a seat from #1 to #2, token `1` → ❌ `PsyNFT: Approval Expired`.

### C7. Metadata and art (owner)
| # | Account | Action | Expected |
|---|---|---|---|
| 1 | #1 | 🖱 Set base URI `ipfs://x/` | ❌ `OwnableUnauthorizedAccount` |
| 2 | #0 | 🖱 Set base URI `ipfs://bafyNoSlash` | ❌ `PsyNFT: Base URI Must End With Slash` |
| 3 | #0 | 🖱 Set base URI `ipfs://bafybeia5k2sgu3fkeyqodrmg43b7tbhd5fsmdgf7e4b34hiwrbeaybovcy/` | ✅ |
| 4 | any | 🖱 **Art / metadata preview**, id `1` | ✅ "ok" plus the artwork (needs internet; a few seconds) |

### C8. Transfer controls (owner)
| # | Account | Action | Expected |
|---|---|---|---|
| 1 | #1 | 🖱 Disable controlled transfers | ❌ `OwnableUnauthorizedAccount` |
| 2 | #0 | 🖱 Enable controlled transfers | ❌ `PsyNFT: Controlled Transfers Already Enabled` |
| 3 | #0 | 🖱 Disable (confirm the dialog) | ✅ controlledTransfers **false** |
| 4 | #0 | 🖱 Disable again | ❌ `PsyNFT: Controlled Transfers Already Disabled` |
| 5 | #1 | 🖱 Transfer a seat: from #1 · to #3 · `1` | ✅ moves freely |
| 6 | #0 | 🖱 Enable controlled transfers | ✅ back to **true** |

### C9. Burning (treasury)
| # | Account | Action | Expected |
|---|---|---|---|
| 1 | #1 | 🖱 Treasury · Burn token `2` | ❌ `PsyNFT: Caller Is Not Treasury` |
| 2 | #0 | 🖱 Burn `2` (confirm) | ✅ totalTokensBurnt **1**; ownerOf(2) lookup errors (`ERC721NonexistentToken`) |
| 3 | #0 | 🖱 Burn `1`, held by **#3** | ✅ succeeds. The treasury can remove any seat (the DAO's "kick" power), by design |

### C10. Rescue ETH (owner)
⌨ Force 1 ETH into the contract (it can't receive ETH normally):

```bash
cast rpc anvil_setBalance $C 0xDE0B6B3A7640000 --rpc-url $R
```

| # | Account | Inputs (Rescue ETH) | Expected |
|---|---|---|---|
| 1 | #1 | #3 · `1000000000000000000` | ❌ `OwnableUnauthorizedAccount` |
| 2 | #0 | #3 · `1000000000000000000` | ✅ ⌨ `cast balance $C --rpc-url $R` → `0` |

### C11. Rescue ERC‑20 (owner)
⌨ Create a test token and send 5000 units to the contract:

```bash
T=$(forge create lib/openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol:ERC20Mock --private-key $K0 --rpc-url $R --broadcast | grep -o 'Deployed to: 0x[0-9a-fA-F]*' | awk '{print $3}'); echo $T
cast send $T "mint(address,uint256)" $C 5000 --private-key $K0 --rpc-url $R
```

🖱 #0: Rescue ERC‑20, token `<printed address>`, to #3, amount `5000` ✅.

⌨ `cast call $T "balanceOf(address)(uint256)" 0x90F79bf6EB2c4f870365E785982E1f101E93b906 --rpc-url $R` → `5000`.

### C12. Rescue ERC‑721 (owner)
🖱 #0: token = **the contract's own address** · #3 · `4` → ❌ `PsyNFT: Cannot Rescue Self` (it can
never take members' seats). Rescuing a *foreign* NFT is covered by the automated tests.

### C13. Safe export (owner actions belong on the Safe)
| # | Account | Action | Expected |
|---|---|---|---|
| 1 | any | 🖱 Set base URI `ipfs://test/` → **+ Safe batch** | "Added to the Safe batch". A bar at the bottom lists `setBaseUri(ipfs://test/)` |
| 2 | any | 🖱 Set base URI `ipfs://bad` → **+ Safe batch** | ❌ `Base URI Must End With Slash`. It is simulated as the owner before anything is added |
| 3 | any | 🖱 **Download for Transaction Builder** | Saves `psynft-safe-batch.json` (import in Safe → Apps → Transaction Builder) |

### C14. Ownership handover (two steps)
⌨ First confirm ownership can never be thrown away:

```bash
cast send $C "renounceOwnership()" --private-key $K0 --rpc-url $R
```

Expected: ❌ `PsyNFT: Ownership Cannot Be Renounced`.

| # | Account | Action | Expected |
|---|---|---|---|
| 1 | #1 | 🖱 Transfer ownership → #3 | ❌ `OwnableUnauthorizedAccount` |
| 2 | #0 | 🖱 Transfer ownership → #3 (confirm) | ✅ owner still #0, **pendingOwner #3** |
| 3 | #1 | 🖱 Accept ownership | ❌ `OwnableUnauthorizedAccount` |
| 4 | #3 | 🖱 Accept ownership | ✅ owner = #3, pendingOwner = 0x0 |
| 5 | #0 | 🖱 Set base URI `ipfs://y/` | ❌ `OwnableUnauthorizedAccount`: the old owner lost control |

### C15. Migration is closed on this deployment
🖱 #3 (now owner): Migrate batch, holders #1, tokenIds `100` → ❌ `PsyNFT: Initial Mint Done`.

---

## Part D: Role separation (`./sandbox/start.sh roles`)

| # | Account | Action | Expected |
|---|---|---|---|
| 1 | #0 | badges | **owner** only |
| 2 | #0 | 🖱 Initial mint | ❌ `Caller Not Core Contract` |
| 3 | #1 | 🖱 Initial mint, then Mint next batch | ✅ (#1 is core) |
| 4 | #1 | 🖱 Distribute `0` → #3 | ✅ |
| 5 | #0 | 🖱 Burn `1` | ❌ `Caller Is Not Treasury` |
| 6 | #2 | 🖱 Burn `1` | ✅ (#2 is treasury) |
| 7 | #1 | 🖱 Set base URI `ipfs://z/` | ❌ `OwnableUnauthorizedAccount` (core is not owner) |

---

## Part E: The migration path (fresh restart; do NOT press Initial mint)

Use #0 throughout.

| # | Action (Owner · Migration) | Inputs | Expected |
|---|---|---|---|
| 1 | Finalize migration | `34` · `21` · `true` · `3` | ❌ `PsyNFT: Migration Not Started` |
| 2 | Migrate batch | holders #1, #2 · ids `1` | ❌ `PsyNFT: Length Mismatch` |
| 3 | Migrate batch | holders `0x0000000000000000000000000000000000000000` · ids `1` | ❌ `PsyNFT: Zero Holder` |
| 4 | Migrate batch | holders #1, #2, `0x5FbDB2315678afecb367f032d93F642f64180aa3` · ids `1, 2, 33` | ✅ migratedCount **3**; ownerOf(33) = the contract |
| 5 | Migrate batch | holders #3 · ids `2` | ❌ `ERC721InvalidSender` (id exists: no double mint) |
| 6 | Core · Initial mint | — | ❌ `PsyNFT: Migration In Progress` |
| 7 | Finalize | `34` · `21` · `true` · `4` | ❌ `PsyNFT: Incomplete Migration` |
| 8 | Finalize | `30` · `21` · `true` · `3` | ❌ `PsyNFT: nextTokenId Too Low` |
| 9 | Finalize | `34` · **`210`** · `true` · `3` | ❌ `PsyNFT: Counters Not On Schedule` (typo guard) |
| 10 | Finalize (confirm) | `34` · `21` · `true` · `3` | ✅ tokenId **34**, previousFibonacci **21**, migrationFinalized **true** |
| 11 | Migrate batch | holders #3 · ids `5` | ❌ `PsyNFT: Migration Finalized` |
| 12 | Core · Mint next batch | — | ✅ tokenId **55** (21 new tokens, ids 34–54, like the real batch 7; at the real switch-over #34 is burned, leaving 20 seats) |

**Snapshot loader (don't execute).** On a fresh restart, paste the contents of
`snapshot/holders.json` into **"Paste holders.json to fill fields"**. Expected: `Loaded 33 entries`.

---

## Part F: Real holders on a mainnet fork

```bash
MAINNET_RPC_URL=https://eth.drpc.org ./sandbox/start.sh migrated
```

The contract address differs in this mode; the banner prints it and the panel is pre-filled.

| # | Check | Expected |
|---|---|---|
| 1 | Dashboard | tokenId **34**, previousFibonacci **21**, migratedCount **33**, migrationFinalized **true** |
| 2 | 🖱 ownerOf lookup `5`, compared with Etherscan's V1 holders | same address |
| 3 | 🖱 ownerOf lookup `0` | errors: token 0 was burnt on V1 and correctly not migrated |
| 4 | 🖱 Art preview `5` | ✅ artwork (fallback gateway) |
| 5 | #0 → 🖱 Transfer ownership → `0xB253a1Ab24B612C2AF37f8fC935b40c7304650e5` (the real Main Safe; confirm) | ✅ pendingOwner = `0xB253…50e5` |
| 6 | 🖱 type the Main Safe address in **Act as** → Act as | header shows `0xB253…50e5` with the **pendingOwner** badge |
| 6b | 🖱 Accept ownership (as the Main Safe) | ✅ "Confirmed": owner = `0xB253…50e5`, exactly like runbook §4c |
| 7 | As Main Safe 🖱 Set base URI `ipfs://bafybeib2aqk4vcfbpgs7aoyk6z6pk5zfcli6qjuvuqohdsdriexeji6m3i/` | ✅ (the re-pinned metadata; the preview works once it has been pinned) |
| 8 | 🖱 Act as a real holder (e.g. the owner of token 5) → Transfer a seat to #3 | ❌ `Incorrect Receiver` until core approves |

---

## Part G: The cutover, through the real Safe (automated)

```bash
MAINNET_RPC_URL=https://eth.drpc.org forge test --match-path "test/*.fork.t.sol" -vv
```

Expected: **8 passed**. Look for these lines:
- `swept to Main Safe through real multisig (ETH): 3.110298529411764706`
- `left for past exiters (ETH): 0.094251470588235294`

`test_FullCutoverThroughRealSafe` runs runbook Step 0 → §0a → §0b → §1 → §4c → §4d with the real
Main Safe contract, 2 of its 4 owners' addresses (a simulation with approved-hash signatures; nobody
signs), and the exact batch files signers will import. After §0a/§0b it checks that the Safe owns
V1 PsyNFT, CoreLogic and PsycSale. `test_SweepBatchIsAtomic` shows that a failure changes nothing.

To produce the signer files and checklist:

```bash
forge script script/SafeBatches.s.sol --rpc-url https://eth.drpc.org
```

---

## Part H: Automated suites

| Command | Expected |
|---|---|
| `forge test --no-match-path "test/*.fork.t.sol"` | **91 passed** (unit, audit, fuzz, 7 invariants × 25,600 calls) |
| `MAINNET_RPC_URL=https://eth.drpc.org forge test --match-path "test/*.fork.t.sol"` | **8 passed** |
| `forge coverage --no-match-path "test/*.fork.t.sol" --report summary` | `src/PsyNFTV2.sol` 100% lines / branches |
| `python -I audit/2026-10/mutation/mutate.py --workers 8` | score **95.5%**; 8 equivalent survivors (≈10 min) |

---

## Results log

| Part | Expected | Result ✓/✗ | Notes | Tester | Date |
|---|---|---|---|---|---|
| B | dashboard values | | | | |
| C1–C15 | per tables | | | | |
| D | role separation | | | | |
| E1–E12 | per table | | | | |
| F1–F8 | per table | | | | |
| G | 8 fork tests | | | | |
| H | 91 + 8, 100% coverage | | | | |

## Error decoder

| Message | Meaning |
|---|---|
| `OwnableUnauthorizedAccount(0x…)` | That address is not the owner (or not the pendingOwner, for accept) |
| `PsyNFT: Caller Not Core Contract` | Only `core` may do this |
| `PsyNFT: Caller Is Not Treasury` | Only `treasury` may burn |
| `PsyNFT: Incorrect Receiver` | Controls are on and there is no live approval to this recipient |
| `PsyNFT: Approval Expired` | The approval window has passed |
| `PsyNFT: Transfer Request Currently Active` | A live approval exists; revoke it or wait for it to expire |
| `PsyNFT: No Approval To Revoke` | There is nothing to revoke for this token |
| `PsyNFT: Counters Not On Schedule` | finalize values aren't consecutive Fibonacci terms (typo guard) |
| `PsyNFT: Base URI Must End With Slash` | Add the trailing `/` |
| `ERC721NonexistentToken(id)` | Burnt, or never minted |
| `ERC721InvalidSender(0x0…)` | That id already exists (double migration blocked) |
| `GS013` | A Safe transaction's inner call failed; the whole batch reverted |

## Troubleshooting

| Symptom | Fix |
|---|---|
| "address already in use" | `./sandbox/stop.sh`, then start again |
| `forge: command not found` | `export PATH="$HOME/.foundry/bin:$PATH"` |
| No "Sandbox account…" picker | The panel isn't pointed at the local chain: restart with `./sandbox/start.sh` |
| Art preview slow | The panel tries `gateway.pinata.cloud`, then `ipfs.filebase.io`; a gateway that doesn't answer within 8 s is skipped |
| Fork mode fails | `start.sh` forks `https://eth.drpc.org` unless `MAINNET_RPC_URL` is set; set it to another mainnet RPC |
| Want MetaMask instead | Add network RPC `http://127.0.0.1:8545`, chain 31337, and import the test key printed by `start.sh` (test only) |
