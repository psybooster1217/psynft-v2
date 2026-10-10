# Metadata & art (the "kene" per token)

Every PsyNFT carries a unique image — the **kene**. This is how that image is attached, how it
**carries over 1:1 during migration**, and how to **attach art to new Fibonacci batches** — all
under the V1 metadata model (kept unchanged in V2).

## The model (unchanged from V1)

PsyNFT stores **no image on-chain**. It uses the standard ERC-721 scheme:

```
tokenURI(id)  ==  baseUri + id
```

- `baseUri` is one owner-settable string ([`setBaseUri`](../src/PsyNFTV2.sol#L335), owner/Safe only).
- Each id resolves to its **own** metadata file in that one folder. That file (JSON) names the id's
  unique image. So the kene lives **off-chain**, in an IPFS folder keyed by token id; the contract
  just concatenates.

```
tokenURI(5)  →  ipfs://<CID>/5  →  { "name": "PsyNFT #5", "image": "ipfs://.../5.png" }  →  the kene
```

### Two rules that bite if ignored

1. **`baseUri` MUST end with a trailing `/`.** OpenZeppelin does a raw string concat, so a baseUri of
   `ipfs://CID` (no slash) makes `tokenURI(5)` = `ipfs://CID5` — broken. The admin UI flags this
   (⚠ next to `baseUri`, and in the Set base URI card).
2. **There is one `baseUri` for the whole collection.** All ids — old and new — must live under the
   same folder/CID. You cannot point individual tokens at different folders (that would need a
   per-token URI override, which we deliberately did **not** add, to stay byte-faithful to V1).

Because IPFS CIDs are **content-addressed**, adding files to a folder yields a **new folder CID**.
So "add new art" always means: build a folder that contains *all* ids so far, pin it, get the new
CID, and `setBaseUri` to it. (An IPNS name or a mutable/dedicated gateway can hide the CID churn —
see [Option B](#option-b--stable-name-ipns--dedicated-gateway) — but the committed model is plain
CIDs.)

---

## A. Carrying the existing 33 kenes over during migration

**You do not copy or re-upload any images.** Migration re-mints the **same token ids**, and
`tokenURI` is purely `baseUri + id` — so if V2's `baseUri` points at the **same folder V1 used**,
every migrated id resolves to the exact same kene automatically.

V1's live `baseUri` (block 25,472,875) is:

```
https://red-literary-tiglon-645.mypinata.cloud/ipfs/bafybeia5k2sgu3fkeyqodrmg43b7tbhd5fsmdgf7e4b34hiwrbeaybovcy/
```

> ⚠️ **Update (audit 2026-10, META-1): that host no longer exists.** `red-literary-tiglon-645.mypinata.cloud`
> returns NXDOMAIN, and every metadata file's `image` field points at the same dead host. The
> content is intact on IPFS, but the links are not. **Do not reuse V1's URL.**
> The metadata has been rebuilt with gateway-independent `ipfs://` image links: identical art, a
> new folder CID **`bafybeib2aqk4vcfbpgs7aoyk6z6pk5zfcli6qjuvuqohdsdriexeji6m3i`**. Pin it as
> described in [metadata/README.md](../metadata/README.md) and deploy with
> `BASE_URI=ipfs://bafybeib2aqk4vcfbpgs7aoyk6z6pk5zfcli6qjuvuqohdsdriexeji6m3i/`. Prefer an `ipfs://`
> base URI over any https gateway URL: marketplaces and wallets resolve `ipfs://` through their own
> gateways, so no single host can break the art again.

### How to set it

- **At deploy:** `Deploy.s.sol` reads `BASE_URI` from the env and calls `setBaseUri` if set.
  `.env.example` already holds the re-pinned `ipfs://` URI. The contract rejects a non-empty URI
  without the trailing `/`, and emits ERC-4906 `BatchMetadataUpdate` so marketplaces refresh.
  > ⚠️ `BASE_URI` is **optional** in the script. If you leave it blank, `tokenURI` returns a bare id
  > and **no image resolves** until the Safe calls `setBaseUri`. Don't skip it.
- **After deploy / to change later:** owner (the Safe) calls `setBaseUri` — from the admin UI's
  **Owner · Admin → Set base URI** card, or via `cast`.

### Verify it carried over

- **UI:** open the dashboard → **Art / metadata preview** → enter a few ids (e.g. `5`, `13`, `21`)
  → the kene renders. This reads `tokenURI` on-chain and fetches the image.
- **cast:** `cast call $PSYNFT_V2 "tokenURI(uint256)(string)" 5 --rpc-url $RPC` should return
  `ipfs://bafybeib2aqk…/5`.
- **Byte-for-byte:** `node metadata/verify-pinned.mjs` checks all 34 files and their images through a
  gateway (run it through two different gateways).

---

## B. Attaching art to new batches (ids 34, 35, …)

New Fibonacci batches (`batchMintInFibonacci`) mint fresh ids to the contract. They have **no art
until the metadata folder contains files for those ids** and `baseUri` points at it.

### Option A — plain CIDs (the committed model)

1. **Author metadata + images** for the new ids. Keep the *same shape* V1 used (filenames = the bare
   id: `34`, `35`, … — check an existing file to match the exact JSON schema and whether images are
   `image: ipfs://…` or a gateway URL).
2. **Build one folder that contains every id so far** — the original 0–33 files **plus** the new
   ones. (Re-pinning the old CID's contents alongside the new files keeps 0–33 byte-identical.)
3. **Pin the folder**, note the **new folder CID**.
4. **Sanity check** the new CID resolves: open `https://<gateway>/ipfs/<newCID>/34` in a browser.
5. **`setBaseUri`** to `https://<gateway>/ipfs/<newCID>/` (owner = Safe). Mind the trailing `/`.
6. **Verify** in the UI's Art / metadata preview: old ids (`5`) still render **and** new ids (`34`)
   now render.

> Order tip: you can mint the batch first and add art after, or stage the art first — either works,
> since art resolution is independent of minting. Minimize the window where a new id has no image by
> having the folder ready before you distribute the new tokens.

### Option B — stable name (IPNS / dedicated gateway)

To avoid changing `baseUri` on every batch, set `baseUri` **once** to a mutable pointer:

- an **IPNS** name (`ipns://<key>/`) you republish to the latest folder CID, or
- a **dedicated gateway path** your pinning service lets you repoint (e.g. a Pinata "gateway" that
  always serves the latest pin).

Then adding a batch is just: pin the new superset folder and update the pointer — **no on-chain tx**.
Trade-off: a mutable pointer is a small trust/centralization surface (whoever controls the IPNS key
or gateway can change what art resolves), whereas a CID in `baseUri` is immutable. For a DAO, IPNS
controlled by the Safe/operators is usually the right balance.

---

## Quick reference

| Task | Who | How |
|---|---|---|
| Wire art at deploy | deployer | set `BASE_URI` in `.env` before `Deploy.s.sol` |
| Carry V1 art to V2 | — | re-mint preserves ids; point `baseUri` at V1's CID (re-pin recommended) |
| Change the whole folder | owner (Safe) | `setBaseUri` → new CID (trailing `/`) |
| Add art for a new batch | operator + owner | pin superset folder → `setBaseUri` to new CID (Option A), or update IPNS (Option B) |
| Verify a token's kene | anyone | UI **Art / metadata preview**, or `cast call … "tokenURI(uint256)(string)" <id>` |

**Not supported by design:** changing one token's art independently of the rest. That needs a
per-token `tokenURI` override, which V2 omits to stay behaviour-identical to V1. If the DAO later
wants it, it's a small additive change — but it's a V1 deviation and would need a fresh audit note.
