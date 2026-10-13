# PsyNFT V2: admin panel

A lightweight control panel for `PsyNFTV2`: a read-only state dashboard, an art/metadata preview, and
guarded action forms for every **owner**, **core**, **treasury**, migration, rescue and member
function. Built with Vite + React + [viem](https://viem.sh); no backend.

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

Easiest way to try it: `./sandbox/start.sh` from the repo root (see [sandbox/README.md](../sandbox/README.md)).

## Use

1. Paste the **deployed PsyNFTV2 address**. It is saved to `localStorage`; `VITE_CONTRACT_ADDRESS`
   presets it.
2. The **dashboard** shows live state (owner/core/treasury, counters, flags, baseURI) and looks up
   `ownerOf`, `balanceOf`, `approvedTransfers`, plus the art for any id.
3. **Signing.** Use a browser wallet (MetaMask/Rabby), or on the local sandbox the built-in
   **Sandbox account** picker and **Act as**. Your roles are detected and badged.
4. **Owner/core/treasury actions belong on the Safe.** On any role-gated card:
   - **Export for Safe** simulates the call *as the address holding that role* (e.g. the Safe) and
     downloads a Safe Transaction Builder file;
   - **+ Safe batch** collects several calls into one batch file (bar at the bottom).

   Import the file in Safe → Apps → Transaction Builder and check the decoded calls before signing.

## Safety

- **Every action is simulated first** (`simulateContract`). A revert (wrong role, bad input) shows
  its reason *before* your wallet prompts, or before an export.
- Sensitive actions (`disableControlledTransfers`, `transferOwnership`, `finalizeMigration`, `burn`)
  ask for an extra confirmation.
- **Network checks.** The chain label comes from the RPC actually being read. Set `VITE_CHAIN_ID` to
  get a red banner when a connected wallet is on a different network.
- **Art preview.** On-chain and metadata URIs are untrusted. Only `ipfs://` and `http(s)` are
  followed, through the collection gateway first and then public gateways, with an 8-second timeout
  each.
- **No keys.** The sandbox wallet relies on anvil's unlocked accounts and impersonation, so no key
  is bundled. The production build was checked to contain none.
- The `migrateBatch` card has a **"paste holders.json"** loader, but for the real migration prefer
  `script/Migrate.s.sol`: it adds the live-V1 completeness cross-checks the UI can't.

## Notes

- `src/abi.ts` is generated from the contract with `forge inspect PsyNFTV2 abi --json`. Regenerate it
  after any contract change.
- Supported networks: Ethereum mainnet, Sepolia, and the local sandbox (chainId 31337).
- Every `VITE_*` variable is compiled into the public bundle. Use keyless RPC URLs for hosted builds.
