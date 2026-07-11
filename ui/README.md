# PsyNFT V2 — Admin dApp

A lightweight control panel for `PsyNFTV2`: a read-only state dashboard plus guarded action
forms for every **owner**, **core**, **treasury**, migration, and rescue function. Built with
Vite + React + [viem](https://viem.sh); no backend.

## Run

```bash
cd ui
npm install
npm run dev        # http://localhost:5173
```

Production build (static files in `dist/`, hostable anywhere):

```bash
npm run build && npm run preview
```

## Use

1. **Connect wallet** (MetaMask/Rabby, or your Safe via a WalletConnect-capable wallet).
2. Paste the **deployed PsyNFTV2 address** (persists to `localStorage`; or preset `VITE_CONTRACT_ADDRESS`).
3. The **dashboard** shows live state (owner/core/treasury, counters, flags, baseURI) and lets you
   look up `ownerOf`, `balanceOf`, and `approvedTransfers`.
4. Your wallet's roles are detected and badged. Each action form is grouped by the role it needs;
   toggle **"only actions my wallet can perform"** to filter.

## Safety

- **Every write is simulated first** (`simulateContract`) — a revert (e.g. wrong role, bad input)
  surfaces its reason *before* your wallet prompts, so you never sign a doomed tx.
- Sensitive actions (`disableControlledTransfers`, `transferOwnership`, `finalizeMigration`, `burn`)
  ask for an extra confirmation.
- **Owner actions belong on the Safe.** Connect the Safe (WalletConnect) and this app will build the
  transaction for it to sign; or use the Safe Transaction Builder directly. A plain wallet that isn't
  the owner will simply have its tx revert.
- The `migrateBatch` card has a **"paste holders.json"** loader, but for the real 33-holder migration
  prefer `script/Migrate.s.sol` — it adds the live-V1 completeness cross-checks the UI can't.

## Notes

- `src/abi.ts` is generated from the contract: `forge inspect PsyNFTV2 abi`. Regenerate after any
  contract change so the UI stays in sync.
- Supported networks: mainnet, Sepolia, and a local anvil fork (chainId 31337). The contract address
  is chain-agnostic — the app uses whatever network your wallet is on.
