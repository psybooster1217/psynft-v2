# PsyNFT V2 — controlled redeployment & holder migration

The original **PsyNFT** (`PSY`, ERC‑721) at
[`0x6c6Ab7b3215374dE4A65De63eAC9BC7A0c7f402d`](https://etherscan.io/token/0x6c6Ab7b3215374dE4A65De63eAC9BC7A0c7f402d)
is administratively frozen: its `owner` key is unreachable, so no one can call
`setCoreContract`, `setTreasury`, `setBaseUri`, or toggle transfers. Ownership lives on‑chain
and cannot be recovered without the key.

This repo deploys a **hardened, behaviour‑identical V2 that PsyDAO controls**, and migrates the
existing **33 live holders** into it — preserving every token id and owner — then resumes the
Fibonacci mint schedule exactly where V1 stopped.

> You can't reclaim the old contract. You *can* stand up an equivalent one you own and move the
> community across. That's what this does.

## What's here

| Path | Purpose |
|---|---|
| [`src/PsyNFTV2.sol`](src/PsyNFTV2.sol) | Hardened copy of PsyNFT + migration, events, rescue helpers |
| [`reference/PsyNFT.v1.sol`](reference/PsyNFT.v1.sol) | The verified original, for diffing |
| [`snapshot/snapshot.mjs`](snapshot/snapshot.mjs) | Pulls the live V1 holder set → `holders.json` (no deps) |
| [`snapshot/holders.json`](snapshot/holders.json) | The committed snapshot (33 holders, block 25,473,885, dual-RPC verified) |
| [`script/Deploy.s.sol`](script/Deploy.s.sol) | Deploy V2 (deployer = temporary owner) |
| [`script/Migrate.s.sol`](script/Migrate.s.sol) | Re‑mint the snapshot, finalize, resume schedule |
| [`script/Handoff.s.sol`](script/Handoff.s.sol) | Transfer ownership to the Gnosis Safe |
| [`test/PsyNFTV2.t.sol`](test/PsyNFTV2.t.sol) | 36 unit tests (every behaviour path) |
| [`test/Migration.fork.t.sol`](test/Migration.fork.t.sol) | End‑to‑end migration vs. **live mainnet** |
| [`test/HoldersJson.t.sol`](test/HoldersJson.t.sol) | Replays the committed snapshot deterministically |
| [`ui/`](ui/README.md) | Admin dApp — control panel for owner/core/treasury (Vite + viem) |
| [`sandbox/`](sandbox/README.md) | One-command local devnet (anvil + deploy + UI) to test the interface |
| [`docs/`](docs/) | Design, V1→V2 diff, runbook, [metadata/art ops](docs/METADATA.md), and security audit |

## Key decisions (as agreed)

- **Target:** the ERC‑721 `PsyNFT` (the address given resolves to the NFT, not an ERC‑20).
- **Migration:** snapshot + owner‑gated re‑mint. Holders do nothing; ids and owners are preserved.
- **Admin model:** a **Gnosis Safe multisig** becomes owner — no single lost key can ever freeze it again.
- **Fidelity:** a **hardened** copy — identical behaviour, plus events, the migration path, and rescue helpers.

## Quickstart

```bash
# 0. Toolchain (Foundry) + deps are vendored under lib/. To rebuild:
forge build

# 1. Run the deterministic suite (no RPC needed)
forge test --no-match-path test/Migration.fork.t.sol

# 2. Validate migration against LIVE mainnet state
export MAINNET_RPC_URL=https://your-rpc
forge test --match-path test/Migration.fork.t.sol -vv

# 3. Refresh the holder snapshot (optional; one is committed)
MAINNET_RPC_URL=$MAINNET_RPC_URL node snapshot/snapshot.mjs
```

Then follow **[docs/DEPLOYMENT_RUNBOOK.md](docs/DEPLOYMENT_RUNBOOK.md)** for the testnet → mainnet
→ Safe‑handoff sequence.

### Control panel (admin dApp)

```bash
cd ui && npm install && npm run dev   # http://localhost:5173
```

Connect your wallet (or Safe), paste the deployed address, and drive every owner/core/treasury
function from a UI with a live state dashboard. Every write is simulated before signing. See
[ui/README.md](ui/README.md).

### Try it locally (sandbox)

```bash
./sandbox/start.sh          # anvil + deploys PsyNFTV2 + opens the UI wired to it
```

A disposable local chain with the contract deployed and the UI pointed at it — click through the
whole lifecycle safely (no real keys, no real network). See [sandbox/README.md](sandbox/README.md).

## Live V1 state (snapshot block 25,473,885)

| Field | Value |
|---|---|
| `tokenId` (counter) | 34 (ids 0–33 minted) |
| burnt | 1 (id 0) → **33 live tokens** |
| `previousFibonacci` | 21 (next batch mints 21: ids 34–54) |
| `controlledTransfers` | true |
| `owner` / `core` / `treasury` | `0xc3ac…e445` (lost) / `0xdaaa…d4f6` / `0xb452…3d61` |
| `baseUri` | `https://red-literary-tiglon-645.mypinata.cloud/ipfs/bafybeia5k2sgu3fkeyqodrmg43b7tbhd5fsmdgf7e4b34hiwrbeaybovcy/` |

## Status

**42 tests pass** (unit + audit PoCs + snapshot replay + live‑mainnet fork migration). Build
settings mirror V1 (`solc 0.8.20`, EVM `paris`, optimizer @ 1,000,000 runs, OpenZeppelin v5.0.2 —
vendored copy verified byte‑identical to upstream).

Security: two internal reviews are on record — an adversarial multi‑agent review
([docs/SECURITY_REVIEW.md](docs/SECURITY_REVIEW.md)) and a full‑stack audit covering the
contract, scripts, snapshot tool, UI, and supply chain ([docs/AUDIT.md](docs/AUDIT.md)). All
findings fixed or accepted‑documented.

> ⚠️ Deploy to **Sepolia first** and rehearse the full migration before mainnet. Have the final
> contract independently audited by an external firm before moving real value. See the runbook.
