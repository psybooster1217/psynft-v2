# PSYC metadata: re-pin before deploying V2 (audit 2026-10, META-1)

## Why this exists

V1's `baseUri`, and the `image` link inside every metadata file, point at
`red-literary-tiglon-645.mypinata.cloud`. That dedicated Pinata gateway **no longer exists**:
Google and Cloudflare DNS both returned NXDOMAIN on 2026-10-10. The art itself is safe on IPFS:
all 34 metadata files and all 34 images still load through public gateways (checked 2026-10-10).
Only the hostname is dead.

Deploying V2 with V1's URL would ship broken art from block 0. So the metadata has been rebuilt
here with **gateway-independent `ipfs://` image links**. Every other byte is unchanged.

| Folder | What |
|---|---|
| `original/` | The 34 V1 metadata files exactly as served under V1's CID `bafybeia5k2sgu3fkeyqodrmg43b7tbhd5fsmdgf7e4b34hiwrbeaybovcy` |
| `v2/` | The same files with `https://red-literary-tiglon-645.mypinata.cloud/ipfs/` replaced by `ipfs://`. Nothing else differs (checked by script) |
| `psyc-metadata-v2.car` | `v2/` packed as an IPFS CAR file (CIDv1, `ipfs-car@1`, no wrapping directory) |
| `CID-v2.txt` | Its root CID: **`bafybeib2aqk4vcfbpgs7aoyk6z6pk5zfcli6qjuvuqohdsdriexeji6m3i`** |

The images are referenced from six existing folders. Their CIDs don't change, but those folders
must stay pinned too:

| Image folder CID | Tokens |
|---|---|
| `QmNbNzhv7P9Z3eZo4sxP3yvJ2WieVi4tUztdgCZQ61BqUo` | 0–2 |
| `QmdzQbWpxvZFxcCEWmqyU6ih9WZFLLPt3WTDCVUExnQgjC` | 3–4 |
| `QmZh7qqirB37ftNmdqdmGMiSuq2JQYDjpZ4y8PwpcusoJX` | 5–7 |
| `QmVAZZGLVYWDqH9h3LsoQBPB5BGsxbsk8SdU7jhUHFdk9n` | 8–12 |
| `QmXYCkGEztrJVdgVMAQ1eAiwd5JhtqifU3YAe9PxALG2r4` | 13–20 |
| `bafybeibvmkjq4bfueerzgnyy5h5ig3hpstp37bwy2ezw4ujq7ngjkbtzzu` | 21–33 |

## What you do (about 15 minutes, needs the PsyDAO Pinata login)

1. **Pin the metadata.** In Pinata, upload `psyc-metadata-v2.car` as a CAR file. The resulting
   CID must be `bafybeib2aqk4vcfbpgs7aoyk6z6pk5zfcli6qjuvuqohdsdriexeji6m3i`.
   If you upload the `v2/` folder instead of the CAR, the service may compute a different CID.
   That is fine as long as step 4 passes; then use *that* CID everywhere below.
2. **Pin the six image folders** above with "pin by CID" (Pinata: *Add → Import from IPFS*).
3. **Pin all seven CIDs on a second service** too (e.g. Filebase or Storacha), so one lapsed
   account can never take the art offline again. That is exactly what happened with the V1
   gateway.
4. **Verify through two different gateways:**
   ```bash
   node metadata/verify-pinned.mjs
   node metadata/verify-pinned.mjs "" https://ipfs.io/ipfs/
   ```
   Both must end with `ALL 34 OK`.
5. **Deploy** with `BASE_URI=ipfs://<CID>/` (already set in `.env.example`). The contract
   rejects a URI without the trailing `/`.

## Later: art for new seats (batch 7, ids 34–54)

`tokenURI` is `baseUri + id`, so ids 34–54 have no metadata until a superset folder (0–54) is
pinned and the Safe calls `setBaseUri`. The contract emits ERC-4906 `BatchMetadataUpdate` on
`setBaseUri`, so marketplaces refresh all tokens automatically. See [docs/METADATA.md](../docs/METADATA.md).
