# Sandbox: test the contract and admin UI against a real local deployment

A throwaway local blockchain (**anvil**, chainId 31337) with **PsyNFTV2 deployed on it** and the
**admin UI pointed at it**. Nothing here touches mainnet, Sepolia, or any real key.

```
 ┌─ anvil (localhost:8545) ── PsyNFTV2 deployed ──────────────────────────────┐
 │                                                                            │
 └─ UI (localhost:5173) ── reads + writes via the local node (no wallet) ─────┘
```

## Prerequisites

**Foundry** (`anvil`, `forge`) and **Node**. On Windows, run from **Git Bash**.

## One command

```bash
./sandbox/start.sh            # fresh chain: owner = core = treasury = account #0
./sandbox/start.sh roles      # fresh chain: owner #0, core #1, treasury #2
MAINNET_RPC_URL=https://eth.drpc.org ./sandbox/start.sh migrated   # mainnet fork + real 33-holder migration
```

The script:
1. starts anvil;
2. deploys PsyNFTV2 (the address is always `0x5FbD…0aa3` in fresh/roles mode);
3. writes `ui/.env.local` (contract address, RPC, chain id);
4. starts the UI at **http://localhost:5173**.

Ctrl‑C stops everything (or run `./sandbox/stop.sh`).

## Writing without a wallet

Top right in the UI, **Sandbox account…** lists anvil's 10 dev accounts. anvil keeps them unlocked
and signs for them itself, so **no private key ever enters the app** and no browser wallet is needed.

**Act as** impersonates any address on the local chain. On a mainnet fork that includes the real
PsyDAO Main Safe or a real holder, which lets you rehearse Safe-owned actions and holder transfers
from the UI.

(MetaMask still works if you prefer: add RPC `http://127.0.0.1:8545`, chain 31337, and import the
anvil dev key printed by `start.sh`. It is a public test key: never use it on a real network.)

## What to test

Follow **[docs/TESTING_HANDBOOK.md](../docs/TESTING_HANDBOOK.md)**: every function, the expected result,
and every expected failure.

## Reset

Restarting `start.sh` gives a brand-new chain. `./sandbox/stop.sh` stops anvil and the UI (only the
process listening on :5173, never your browser) and removes `ui/.env.local`.
