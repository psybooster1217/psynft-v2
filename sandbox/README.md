# Sandbox — test the admin UI against a real local deployment

A throwaway local blockchain (**anvil**, chainId 31337) with **PsyNFTV2 deployed on it** and the
**UI auto-pointed at it**. Nothing here touches mainnet, Sepolia, or any real key — it's a
disposable environment for clicking through every button safely.

```
 ┌─ anvil (localhost:8545) ── PsyNFTV2 deployed, owner=core=treasury=acct#0 ─┐
 │                                                                           │
 └─ UI (localhost:5173) ── reads via local RPC · writes via your wallet ─────┘
```

## Prerequisites

- **Foundry** (`anvil`, `forge`) and **Node** — the repo's toolchain.
- A browser wallet (**MetaMask** or Rabby) to test the *write* buttons. Reads work without one.

## One command

```bash
./sandbox/start.sh            # fresh chain (default) — clean slate, no external RPC
./sandbox/start.sh migrated   # fork mainnet + run the real 33-holder migration
```

Run it from **Git Bash** (Windows), WSL, macOS, or Linux. It will:

1. start anvil on `localhost:8545` (chainId 31337),
2. deploy `PsyNFTV2` with **owner = core = treasury = anvil account #0** (one wallet drives everything),
3. write `ui/.env.local` so the UI opens with the address pre-filled,
4. start the UI at **http://localhost:5173**.

Press **Ctrl-C** to stop everything (or run `./sandbox/stop.sh`).

> Windows without Git Bash? Use the 3-terminal manual steps at the bottom — they work in any shell.

## Connect a wallet (to test writes)

The dashboard reads without a wallet. To *send* transactions, add the local chain to MetaMask:

1. **Add network** → Custom:
   - Network name: `PsyNFT Sandbox`
   - RPC URL: `http://localhost:8545`
   - Chain ID: `31337`
   - Currency symbol: `ETH`
2. **Import account** → paste anvil account #0's private key (public dev key, **test-only**):
   ```
   0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
   ```
   This account is **owner + core + treasury**, so it can execute every action in the UI.
3. In the app, click **Connect wallet**. You should see the `owner · core · treasury` badges.

> If MetaMask complains about the nonce after you restart the sandbox, do
> *Settings → Advanced → Clear activity tab data* (the chain reset; MetaMask cached the old nonce).

## Suggested click-through (fresh mode) — the full lifecycle

Do these in order and watch the dashboard update after each (it auto-refreshes on success):

1. **Core · Initial mint** → mints ids 0,1,2 to the contract. Dashboard `tokenId` → 3.
2. **Core · Mint next Fibonacci batch** → mints 2 more (ids 3,4). `tokenId` → 5, `previousFibonacci` → 3.
   Repeat a few times to watch the schedule (2, 3, 5, 8 …).
3. **Core · Distribute NFTs** → e.g. tokenIds `0` to your address → that token leaves the contract.
4. Try to move it in MetaMask/etherscan — it's blocked (controlled transfers). Now
   **Core · Approve a member transfer** (`_tokenId 0`, `_to` your other address, `86400`), then the
   transfer succeeds within the window. This is the soulbound-style gate in action.
5. **Owner · Set base URI** → change it and re-check `baseUri` on the dashboard.
6. **Treasury · Burn token** → burn id `1`; `totalTokensBurnt` → 1 and `ownerOf(1)` reverts.
7. **Owner · Disable controlled transfers** → now member tokens move freely. Re-enable to restore.
8. **Owner · Transfer ownership** to anvil account #1, import that key, and **Accept ownership** —
   watch `owner` change and the old account lose its badge (two-step handoff, exactly like mainnet).

## Migration mode

`./sandbox/start.sh migrated` forks mainnet (so the real V1 exists), deploys V2, and runs
`Migrate.s.sol` — re-minting the **33 real holders** with their exact token ids and finalizing.
The dashboard opens showing `tokenId 34`, `previousFibonacci 21`, `migrationFinalized true`,
`migratedCount 33`. Use it to rehearse post-migration operations (the next `batchMintInFibonacci`
mints 21 tokens to the contract for the new core to distribute).

## Reset

Restarting `start.sh` gives a brand-new chain (fresh mode is fully deterministic — the contract
always deploys to `0x5FbD…0aa3`). `./sandbox/stop.sh` kills stragglers and removes `ui/.env.local`.

## Manual steps (any shell, no bash script)

```bash
# Terminal 1 — chain
anvil --chain-id 31337

# Terminal 2 — deploy (PowerShell: use $env:VAR = "..." instead of export)
export PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
export NEW_CORE=0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
export NEW_TREASURY=0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
forge script script/Deploy.s.sol --rpc-url http://localhost:8545 --broadcast
# note the deployed address, then:
#   echo "VITE_CONTRACT_ADDRESS=<address>"  >  ui/.env.local
#   echo "VITE_RPC_URL=http://localhost:8545" >> ui/.env.local

# Terminal 3 — UI
npm --prefix ui run dev
```
