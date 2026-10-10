# Testing handbook: every PsyNFT V2 function, step by step

A hands‑on guide for testing the contract and the admin UI on a **throwaway local blockchain**. No
real money, no real keys, nothing can break. Every "Expected" below was observed on the sandbox on
2026‑10‑10.

> Part of the [October 2026 audit plan](AUDIT_PLAN_2026-10.md). Time needed: about 15 min setup,
> 60–90 min for Parts B–D.

**Legend:** ✅ should succeed · ❌ should fail with the quoted message (that's a pass) · 🖱 do it in
the UI · ⌨ do it in the terminal

---

## Part A — One‑time setup

### A1. Open a terminal
Use **Git Bash** (Start menu → "Git Bash"). Then:

```bash
cd ~/Desktop/SMARTC
export PATH="$HOME/.foundry/bin:$PATH"
forge --version && node --version
```

Expected: `forge Version: 1.7.x` and `v22.x`.

### A2. Start the sandbox

```bash
./sandbox/start.sh
```

Wait for **`SANDBOX READY · mode: fresh`**. Leave this window open: closing it (or Ctrl‑C) stops
everything. The contract is always at **`0x5FbDB2315678afecb367f032d93F642f64180aa3`** in fresh mode.

### A3. Add the sandbox network to MetaMask
Use a separate browser profile for MetaMask if you can, so test accounts never sit next to real ones.

MetaMask → network menu → **Add network → Add manually**:

| Field | Value |
|---|---|
| Network name | `PsyNFT Sandbox` |
| RPC URL | `http://127.0.0.1:8545` |
| Chain ID | `31337` |
| Currency | `ETH` |

### A4. Import four test accounts
MetaMask → account menu → **Add account → Import account**, once for each key below.

> ⚠️ These are anvil's **public** development keys. Everyone on the internet knows them. Use them
> only on the sandbox network, and never send real funds to these addresses on any real chain.

| Name it | Address | Private key | Role in the sandbox |
|---|---|---|---|
| `#0 Admin` | `0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266` | `0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80` | owner + core + treasury |
| `#1 Member A` | `0x70997970C51812dc3A010C7d01b50e0d17dc79C8` | `0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d` | member / wrong‑role tester |
| `#2 Member B` | `0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC` | `0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a` | member |
| `#3 Outsider` | `0x90F79bf6EB2c4f870365E785982E1f101E93b906` | `0x7c852118294e51e653712a81e05800f419141751be58f605c371e15141b007a6` | outsider / future owner |

### A5. Open the UI
Go to **http://localhost:5173**. The contract address is pre‑filled. Click **Connect wallet** while
`#0 Admin` is selected in MetaMask. You should see the badges **owner · core · treasury**.

**How a failure looks.** Every button **simulates first**. When a call would fail, the red reason
appears on the card *before* MetaMask opens. That is the ❌ pass condition. If MetaMask does open for
a ❌ step, reject it and write that down as a failed test.

**Switching accounts:** pick another account in MetaMask. The UI re‑detects your roles. If it asks,
connect the new account too.

### A6. Second terminal for the "member" side
The admin UI has no "send my NFT" button, because members don't use it. Member transfers are done
with one‑line commands. Open a **second** Git Bash window and paste:

```bash
cd ~/Desktop/SMARTC; export PATH="$HOME/.foundry/bin:$PATH"
export R=http://127.0.0.1:8545 C=0x5FbDB2315678afecb367f032d93F642f64180aa3
export A0=0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 K0=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
export A1=0x70997970C51812dc3A010C7d01b50e0d17dc79C8 K1=0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d
export A2=0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC K2=0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a
export A3=0x90F79bf6EB2c4f870365E785982E1f101E93b906 K3=0x7c852118294e51e653712a81e05800f419141751be58f605c371e15141b007a6
```

### Reset at any time
Press Ctrl‑C in the sandbox window and run `./sandbox/start.sh` again for a brand‑new chain. Then in
MetaMask: **Settings → Advanced → Clear activity tab data**. Otherwise it remembers old nonces and
transactions get stuck.

---

## Part B — Read‑only checks (dashboard, no wallet needed)

| Field | Expected on a fresh sandbox |
|---|---|
| name / symbol | `PsyNFT (PSY)` |
| owner / core / treasury | all `0xf39F…2266` |
| pendingOwner | unset (0x0) |
| tokenId (next) | `0` |
| previousFibonacci | `2` |
| totalTokensBurnt · migratedCount | `0` · `0` |
| initialMintCalled · migrationStarted · migrationFinalized | `false` · `false` · `false` |
| controlledTransfers | `true` |
| baseUri | the V1 Pinata URL (that gateway is currently dead: audit plan META‑1) |

---

## Part C — Lifecycle tests, in order (fresh sandbox)

Do the steps top to bottom. Each one builds on the previous.

### C1. Initial mint (core)
| # | Account | Action | Expected |
|---|---|---|---|
| 1 | `#1` | 🖱 Core · Initial mint → Execute | ❌ `PsyNFT: Caller Not Core Contract` |
| 2 | `#0` | 🖱 same | ✅ tokenId → **3** (ids 0, 1, 2 held by the contract) |
| 3 | `#0` | 🖱 same again | ❌ `PsyNFT: Initial Mint Complete` |

Check: dashboard **ownerOf** lookup for `0` shows the contract address `0x5FbD…0aa3`.

### C2. Fibonacci batches (core)
| # | Account | Action | Expected |
|---|---|---|---|
| 1 | `#1` | 🖱 Mint next Fibonacci batch | ❌ `PsyNFT: Caller Not Core Contract` |
| 2 | `#0` | 🖱 Mint next Fibonacci batch, **4 times**, checking the dashboard after each | ✅ tokenId 5 → 8 → 13 → 21; previousFibonacci 3 → 5 → 8 → 13 |

### C3. Distribute to a member (core)
| # | Account | Inputs (Distribute NFTs) | Expected |
|---|---|---|---|
| 1 | `#1` | `0` · `#1 address` | ❌ `PsyNFT: Caller Not Core Contract` |
| 2 | `#0` | *(empty)* · `#1 address` | ❌ `PsyNFT: Token Array Empty` (or the UI's own input error) |
| 3 | `#0` | `0` · `0x0000000000000000000000000000000000000000` | ❌ `PsyNFT: Recipient Cannot Be Zero Address` |
| 4 | `#0` | `0, 1` · `#1 address` | ✅ ownerOf(0) = `#1`; balanceOf(`#1`) = **2** |

### C4. Members can't move seats freely (controlled transfers)
⌨ In terminal 2:

```bash
cast send $C "transferFrom(address,address,uint256)" $A1 $A2 0 --private-key $K1 --rpc-url $R
cast send $C "safeTransferFrom(address,address,uint256)" $A1 $A2 0 --private-key $K1 --rpc-url $R
```

Expected: both ❌ `PsyNFT: Incorrect Receiver`.

### C5. Core approves one specific transfer
| # | Account | Inputs (Approve a member transfer) | Expected |
|---|---|---|---|
| 1 | `#1` | `0` · `#2` · `3600` | ❌ `PsyNFT: Caller Not Core Contract` |
| 2 | `#0` | `999` · `#2` · `3600` | ❌ `PsyNFT: Non Existent Token` |
| 3 | `#0` | `0` · `#2` · `3600` | ✅ dashboard approval lookup for `0`: to = `#2`, expiry ≈ now + 1 h |
| 4 | `#0` | `0` · `#3` · `3600` | ❌ `PsyNFT: Transfer Request Currently Active` (a live grant can't be changed or revoked: an audit question) |

⌨ Then:

```bash
cast send $C "transferFrom(address,address,uint256)" $A1 $A3 0 --private-key $K1 --rpc-url $R   # wrong recipient
cast send $C "transferFrom(address,address,uint256)" $A1 $A2 0 --private-key $K1 --rpc-url $R   # approved recipient
cast call $C "ownerOf(uint256)(address)" 0 --rpc-url $R
```

Expected: the first ❌ `PsyNFT: Incorrect Receiver`, the second ✅, then ownerOf(0) = `0x3C44…93BC` (`#2`).

### C6. Approvals expire
🖱 `#0`: Approve a member transfer `1` · `#2` · `60`. ✅

⌨ Fast‑forward the sandbox clock by 61 seconds, then try:

```bash
cast rpc evm_increaseTime 61 --rpc-url $R && cast rpc evm_mine --rpc-url $R
cast send $C "transferFrom(address,address,uint256)" $A1 $A2 1 --private-key $K1 --rpc-url $R
```

Expected: ❌ `PsyNFT: Approval Expired`.

### C7. Metadata (owner)
| # | Account | Action | Expected |
|---|---|---|---|
| 1 | `#1` | 🖱 Set base URI `ipfs://X/` | ❌ `OwnableUnauthorizedAccount(0x7099…79C8)` |
| 2 | `#0` | 🖱 Set base URI `ipfs://bafyTEST/` | ✅ dashboard baseUri updates |
| 3 | any | ⌨ `cast call $C "tokenURI(uint256)(string)" 5 --rpc-url $R` | `"ipfs://bafyTEST/5"` |
| 4 | `#0` | 🖱 Set base URI `https://gateway.pinata.cloud/ipfs/bafybeia5k2sgu3fkeyqodrmg43b7tbhd5fsmdgf7e4b34hiwrbeaybovcy/` then **Art / metadata preview** id `5` | ✅ metadata JSON loads ("PSYC", "Shipibo kené"). **The image will not load**: the JSON's `image` points at the dead gateway (META‑1). Record this. Retest after the re‑pin. |

### C8. Switching transfer controls (owner)
| # | Account | Action | Expected |
|---|---|---|---|
| 1 | `#1` | 🖱 Disable controlled transfers | ❌ `OwnableUnauthorizedAccount(…)` |
| 2 | `#0` | 🖱 Enable controlled transfers | ❌ `PsyNFT: Controlled Transfers Already Enabled` |
| 3 | `#0` | 🖱 Disable controlled transfers (confirm the dialog) | ✅ dashboard controlledTransfers = **false** |
| 4 | `#0` | 🖱 Disable again | ❌ `PsyNFT: Controlled Transfers Already Disabled` |
| 5 | `#1` | ⌨ `cast send $C "transferFrom(address,address,uint256)" $A1 $A3 1 --private-key $K1 --rpc-url $R` | ✅ moves freely; ownerOf(1) = `#3` |
| 6 | `#0` | 🖱 Enable controlled transfers | ✅ back to **true** |

### C9. Burning (treasury)
| # | Account | Action | Expected |
|---|---|---|---|
| 1 | `#1` | 🖱 Treasury · Burn token `2` | ❌ `PsyNFT: Caller Is Not Treasury` |
| 2 | `#0` | 🖱 Burn token `2` (confirm) | ✅ totalTokensBurnt = **1**; ownerOf(2) lookup now errors (`ERC721NonexistentToken`) |
| 3 | `#0` | 🖱 Burn token `1`. **It belongs to `#3`, not the treasury** | ✅ succeeds. The treasury can burn any member's seat without consent. This is by design (as in V1) and must be disclosed |

### C10. Role separation (owner hands roles to different accounts)
| # | Account | Action | Expected |
|---|---|---|---|
| 1 | `#1` | 🖱 Set core contract `#1` | ❌ `OwnableUnauthorizedAccount(…)` |
| 2 | `#0` | 🖱 Set core contract `0x0000000000000000000000000000000000000000` | ❌ `PsyNFT: Core Cannot Be Zero Address` |
| 3 | `#0` | 🖱 Set core contract `#1 address`, then Set treasury `#2 address` | ✅ dashboard core = `0x7099…`, treasury = `0x3C44…`; `#0` keeps only the **owner** badge |
| 4 | `#0` | 🖱 Mint next Fibonacci batch | ❌ `PsyNFT: Caller Not Core Contract` |
| 5 | `#1` | 🖱 Mint next Fibonacci batch | ✅ tokenId 21 → **34** (`#1` now shows the core badge) |
| 6 | `#0` | 🖱 Burn token `3` | ❌ `PsyNFT: Caller Is Not Treasury` |
| 7 | `#2` | 🖱 Burn token `3` | ✅ totalTokensBurnt = **3** |

### C11. Rescue ETH (owner)
⌨ Force 1 ETH into the contract (it has no way to receive ETH normally):

```bash
cast rpc anvil_setBalance $C 0xDE0B6B3A7640000 --rpc-url $R && cast balance $C --rpc-url $R
```

| # | Account | Inputs (Rescue ETH) | Expected |
|---|---|---|---|
| 1 | `#1` | `#3` · `1000000000000000000` | ❌ `OwnableUnauthorizedAccount(…)` |
| 2 | `#0` | `#3` · `1000000000000000000` | ✅ `cast balance $C --rpc-url $R` → `0` |

### C12. Rescue ERC‑20 (owner)
⌨ Deploy a test token and send 5000 units to the contract:

```bash
T=$(forge create lib/openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol:ERC20Mock --private-key $K0 --rpc-url $R --broadcast | grep -o 'Deployed to: 0x[0-9a-fA-F]*' | awk '{print $3}'); echo $T
cast send $T "mint(address,uint256)" $C 5000 --private-key $K0 --rpc-url $R
```

🖱 `#0`: Rescue ERC‑20 with token `<printed address>`, to `#3`, amount `5000`. ✅

⌨ `cast call $T "balanceOf(address)(uint256)" $A3 --rpc-url $R` → `5000`.

### C13. Rescue ERC‑721 (owner)
| # | Account | Inputs (Rescue ERC‑721) | Expected |
|---|---|---|---|
| 1 | `#0` | token = **the contract's own address** · `#3` · `4` | ❌ `PsyNFT: Cannot Rescue Self` (it can never take members' seats) |

A rescue of a *foreign* NFT is covered by the unit test `test_RescueERC721_ForeignOnly`. It was also
done by hand on 2026‑10‑10 with a second PsyNFTV2 deployment. Note: rescuing a foreign NFT that has
its own transfer gate reverts inside that foreign contract, which is expected.

### C14. Ownership handover (owner → new owner, two steps)
⌨ First confirm that ownership can never be thrown away:

```bash
cast send $C "renounceOwnership()" --private-key $K0 --rpc-url $R
```

Expected: ❌ `PsyNFT: Ownership Cannot Be Renounced`.

| # | Account | Action | Expected |
|---|---|---|---|
| 1 | `#1` | 🖱 Transfer ownership → `#3` | ❌ `OwnableUnauthorizedAccount(…)` |
| 2 | `#0` | 🖱 Transfer ownership → `#3` (confirm) | ✅ owner still `#0`, **pendingOwner = `#3`** |
| 3 | `#1` | 🖱 Pending owner · Accept ownership | ❌ `OwnableUnauthorizedAccount(…)` |
| 4 | `#3` | 🖱 Accept ownership | ✅ owner = `0x90F7…b906`, pendingOwner = 0x0 |
| 5 | `#0` | 🖱 Set base URI `ipfs://Y/` | ❌ `OwnableUnauthorizedAccount(0xf39F…)`: the old owner has lost control |

### C15. Migration is closed on a deployment that already did its initial mint
🖱 `#3` (now owner): Migrate batch, holders `#1 address`, tokenIds `100`. ❌ `PsyNFT: Initial Mint Done`.

---

## Part D — The migration path (restart for a fresh chain)

Ctrl‑C the sandbox, run `./sandbox/start.sh`, and clear MetaMask activity. **Do not** press Initial
mint this time. Use `#0` throughout.

| # | Action (Owner · Migration) | Inputs | Expected |
|---|---|---|---|
| 1 | Finalize migration | `34` · `21` · `true` · `3` | ❌ `PsyNFT: Migration Not Started` |
| 2 | Migrate batch | holders `#1, #2` · ids `1` | ❌ `PsyNFT: Length Mismatch` |
| 3 | Migrate batch | holders `0x0000000000000000000000000000000000000000` · ids `1` | ❌ `PsyNFT: Zero Holder` |
| 4 | Migrate batch | holders `#1, #2, 0x5FbDB2315678afecb367f032d93F642f64180aa3` · ids `1, 2, 33` | ✅ migratedCount = **3**; ownerOf(33) = the contract (an undistributed seat) |
| 5 | Migrate batch | holders `#3` · ids `2` | ❌ `ERC721InvalidSender(0x0…)` (id already exists, so no double mint) |
| 6 | Core · Initial mint | — | ❌ `PsyNFT: Migration In Progress` |
| 7 | Finalize migration | `34` · `21` · `true` · `4` | ❌ `PsyNFT: Incomplete Migration` (the completeness guard) |
| 8 | Finalize migration | `30` · `21` · `true` · `3` | ❌ `PsyNFT: nextTokenId Too Low` |
| 9 | Finalize migration (confirm) | `34` · `21` · `true` · `3` | ✅ tokenId **34**, previousFibonacci **21**, migrationFinalized **true** |
| 10 | Migrate batch | holders `#3` · ids `5` | ❌ `PsyNFT: Migration Finalized` |
| 11 | Core · Initial mint | — | ❌ `PsyNFT: Initial Mint Complete` |
| 12 | Core · Mint next Fibonacci batch | — | ✅ tokenId **55**: 21 new seats (ids 34–54), exactly what the real batch 7 will mint |

**JSON loader check (don't execute).** On another fresh restart, open `snapshot/holders.json` in a
text editor, copy everything, and paste it into **"Paste holders.json to fill fields"** (on the
Migrate batch card). Expected: both fields fill and the card says **`Loaded 33 entries`**, with no
"re‑pointed" note because the current snapshot has no V1‑held tokens. The real migration should still
use `Migrate.s.sol` (it cross‑checks live V1).

---

## Part E — Real‑holder rehearsal on a mainnet fork

```bash
MAINNET_RPC_URL=https://eth.drpc.org ./sandbox/start.sh migrated
```

The contract address is **different** in this mode. Copy it from the banner (it was `0x17d9…aa95` on
2026‑10‑10) and use it in place of `$C` in terminal 2.

| # | Check | Expected |
|---|---|---|
| 1 | Dashboard | tokenId **34**, previousFibonacci **21**, migratedCount **33**, migrationFinalized **true** |
| 2 | ⌨ `V1=0x6c6Ab7b3215374dE4A65De63eAC9BC7A0c7f402d; for id in 1 5 20 33; do echo $id $(cast call $V1 "ownerOf(uint256)(address)" $id --rpc-url $R) $(cast call $C "ownerOf(uint256)(address)" $id --rpc-url $R); done` | the two addresses on each line are **identical** |
| 3 | 🖱 ownerOf lookup `0` | errors: token 0 was burnt on V1 and correctly not migrated |
| 4 | 🖱 `#0` Mint next Fibonacci batch | ✅ tokenId **55** |

**Cutover and exit‑pool sweep rehearsal** (runbook §4d; one command):

```bash
MAINNET_RPC_URL=https://eth.drpc.org forge test --match-path "test/*.fork.t.sol" -vv
```

Expected: **4 passed**. Logs on 2026‑10‑10: `swept to Main Safe (ETH): 3.110298529411764706` and
`left for past exiters (ETH): 0.094251470588235294`. If these numbers change, someone exited during
the window. That's fine, but re‑check before the real execution.

---

## Part F — Sepolia + a real Safe (the actual signing path)

This is the only part that tests how the multisig will really operate. You need about 0.2 Sepolia
ETH from a faucet, split across your test wallets.

1. **Create a test Safe.** On https://app.safe.global switch to Sepolia and create a 2‑of‑3 Safe
   from three test wallets you control.
2. **Deploy with a keystore** (no raw key in the environment):
   ```bash
   cast wallet import psynft-test --interactive
   forge script script/Deploy.s.sol --rpc-url $SEPOLIA_RPC_URL --account psynft-test --broadcast --verify
   ```
   Expected: Etherscan shows a green "Verified" checkmark.
3. **Migrate and hand off** per runbook §2 (`PSYNFT_V2=<address>`, `SAFE_OWNER=<test Safe>`). Same
   `--account psynft-test` flag.
4. **Accept ownership from the Safe.** Safe → Apps → **Transaction Builder** → paste the contract
   address (the ABI loads automatically once verified) → `acceptOwnership` → Create batch → sign with
   2 owners → Execute. On Etherscan "Read Contract": `owner` = the Safe, `pendingOwner` = 0x0.
5. **Owner actions through the Safe.** Same flow for `setCoreContract(Safe)`,
   `setTreasury(Safe)`, `setBaseUri(…)`, disable then enable controls. Each needs 2 signatures.
   Confirm each on Etherscan.
6. **Rehearse the fallback‑handler blocker** (runbook §0b):
   - Through the Transaction Builder, call the Safe itself with
     `setFallbackHandler(0x0000000000000000000000000000000000000000)`.
   - Then batch‑mint and run `transferNFTs([34], Safe)`. ❌ It should fail.
   - Set the handler back to the canonical CompatibilityFallbackHandler for that Safe version
     (shown under Safe → Settings → Advanced). Retry. ✅
7. **The admin UI against a Safe‑owned contract.** Run `npm --prefix ui run dev`, put MetaMask on
   Sepolia, and paste the address. The dashboard reads fine. Try any owner action from a normal
   wallet: ❌ `OwnableUnauthorizedAccount`. That is expected, and it confirms that owner actions must
   go through the Safe (audit item UI‑7).

---

## Part G — Automated suites (one command each)

```bash
forge test --no-match-path "test/*.fork.t.sol"
```

Expected: **41 passed**.

```bash
MAINNET_RPC_URL=https://eth.drpc.org forge test --match-path "test/*.fork.t.sol" -vv
```

Expected: **4 passed**.

```bash
forge test --match-test test_FibonacciBatch_GasCeiling -vv
```

This prints the gas cost of future batch sizes.

---

## Part H — Results log

Copy this table into the audit report and fill it in as you go.

| Test | Expected | Result ✓/✗ | Notes | Tester | Date |
|---|---|---|---|---|---|
| B | dashboard values | | | | |
| C1 | 1❌ 2✅ 3❌ | | | | |
| C2 | 1❌ 2✅ | | | | |
| C3 | 1–3❌ 4✅ | | | | |
| C4 | both ❌ | | | | |
| C5 | 1,2,4❌ 3✅ + cast ❌/✅ | | | | |
| C6 | ❌ expired | | | | |
| C7 | 1❌ 2–3✅ 4 image fails (META‑1) | | | | |
| C8 | 1,2,4❌ 3,5,6✅ | | | | |
| C9 | 1❌ 2,3✅ | | | | |
| C10 | 1,2,4,6❌ 3,5,7✅ | | | | |
| C11 | 1❌ 2✅ | | | | |
| C12 | ✅ | | | | |
| C13 | ❌ self | | | | |
| C14 | renounce❌ 1,3,5❌ 2,4✅ | | | | |
| C15 | ❌ | | | | |
| D1–D12 | per table | | | | |
| E1–E4 + fork tests | per table | | | | |
| F1–F7 | per steps | | | | |
| G | 41 + 4 pass | | | | |

---

## Error decoder

| Message | Meaning |
|---|---|
| `OwnableUnauthorizedAccount(0x…)` | The address shown is not the owner (or not the pendingOwner, for accept) |
| `PsyNFT: Caller Not Core Contract` | Only the `core` address may do this |
| `PsyNFT: Caller Is Not Treasury` | Only the `treasury` address may burn |
| `PsyNFT: Incorrect Receiver` | Controlled transfers are on and there is no live approval to this recipient |
| `PsyNFT: Approval Expired` | The approval window has passed |
| `PsyNFT: Transfer Request Currently Active` | An approval for this token is still live; it can't be replaced until it expires |
| `ERC721NonexistentToken(id)` | Burnt, or never minted |
| `ERC721InvalidSender(0x0…)` | Minting an id that already exists (double migration blocked) |
| `PsyNFT: Incomplete Migration` | `expectedCount` ≠ number of tokens actually migrated |

## Troubleshooting

| Symptom | Fix |
|---|---|
| MetaMask transaction stuck or "nonce too high" after a restart | Settings → Advanced → **Clear activity tab data** |
| "address already in use" / port 8545 or 5173 busy | `./sandbox/stop.sh`, then start again |
| `forge: command not found` | `export PATH="$HOME/.foundry/bin:$PATH"` |
| UI shows an old contract address | `ui/.env.local` (written by start.sh) wins; restart the sandbox |
| Fork mode fails or hangs | Use `MAINNET_RPC_URL=https://eth.drpc.org`. Fork tests need an archive‑capable RPC |
| Art preview blank | Known: audit plan META‑1 (dead gateway) |
