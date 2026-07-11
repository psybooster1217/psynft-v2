#!/usr/bin/env node
/**
 * Snapshot the live PsyNFT (V1) holder set into snapshot/holders.json.
 *
 * The output is consumed verbatim by script/Migrate.s.sol. For every still-existing V1
 * token it records {tokenId, owner}; burnt tokens (ownerOf reverts) are omitted. Tokens
 * still held by the V1 contract itself are left as the V1 address on purpose — the
 * migration script substitutes them with the freshly deployed V2 address so the new core
 * can re-distribute them.
 *
 * Usage:
 *   MAINNET_RPC_URL=https://... node snapshot/snapshot.mjs
 *   node snapshot/snapshot.mjs --rpc https://... --v1 0x6c6A... [--block 0xLATEST]
 *   # production: cross-verify every owner against an INDEPENDENT second provider
 *   node snapshot/snapshot.mjs --rpc https://provider-a --verify-rpc https://provider-b
 *
 * No dependencies — uses Node 18+ global fetch.
 */

import { writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const __dirname = dirname(fileURLToPath(import.meta.url));

// ---- args / env ----
const argv = process.argv.slice(2);
function arg(name, fallback) {
  const i = argv.indexOf(`--${name}`);
  return i >= 0 ? argv[i + 1] : fallback;
}
const RPC = arg("rpc", process.env.MAINNET_RPC_URL);
const V1 = (arg("v1", "0x6c6Ab7b3215374dE4A65De63eAC9BC7A0c7f402d")).toLowerCase();
const BLOCK = arg("block", "latest");
// Optional second, INDEPENDENT provider. Every owner is re-read from it at the same block
// and the run aborts on any mismatch — so no single lying/compromised RPC can poison the
// snapshot that the (irreversible) migration is built from. Strongly recommended for the
// production snapshot.
const VERIFY_RPC = arg("verify-rpc", process.env.VERIFY_RPC_URL);

if (!RPC) {
  console.error("ERROR: set MAINNET_RPC_URL or pass --rpc <url>");
  process.exit(1);
}
if (VERIFY_RPC && VERIFY_RPC === RPC) {
  console.error("ERROR: --verify-rpc must be a DIFFERENT provider than --rpc (independence is the point)");
  process.exit(1);
}

// ---- function selectors ----
const SEL = {
  tokenId: "0x17d70f7c",
  previousFibonacci: "0xa681c2e9",
  controlledTransfers: "0x74594e7d",
  totalTokensBurnt: "0x455f6f31",
  ownerOf: "0x6352211e", // ownerOf(uint256)
};

let idc = 0;

async function fetchJson(url, body) {
  const res = await fetch(url, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(body),
  });
  try {
    return await res.json();
  } catch {
    // Rate-limit/HTML error pages must surface as a clean, identifiable failure.
    throw new Error(`provider returned non-JSON (HTTP ${res.status}) from ${new URL(url).host}`);
  }
}

async function rpc(method, params, url = RPC) {
  const j = await fetchJson(url, { jsonrpc: "2.0", id: ++idc, method, params });
  if (j.error) throw new Error(`${method}: ${JSON.stringify(j.error)}`);
  return j.result;
}

async function ethCall(data, block = BLOCK, url = RPC) {
  return rpc("eth_call", [{ to: V1, data }, block], url);
}

async function batchCall(datas, block, url = RPC) {
  // JSON-RPC batch; each element may return a result or an error (burnt token).
  const body = datas.map((data, i) => ({
    jsonrpc: "2.0",
    id: i,
    method: "eth_call",
    params: [{ to: V1, data }, block],
  }));
  const arr = await fetchJson(url, body);
  if (!Array.isArray(arr)) {
    // Some providers reject batches with a single error object.
    throw new Error(`batch rejected by ${new URL(url).host}: ${JSON.stringify(arr).slice(0, 200)}`);
  }
  const byId = new Map(arr.map((r) => [r.id, r]));
  return datas.map((_, i) => byId.get(i));
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// ERC721NonexistentToken(uint256) selector — what OZ v5 ownerOf reverts with for a burnt id.
const NONEXISTENT_SELECTOR = "0x7e273289";

// True only for a genuine EVM revert (burnt token), NOT a transient RPC/node error.
function isRevertError(err) {
  if (!err) return false;
  if (err.code === 3) return true; // standard "execution reverted"
  if (typeof err.data === "string" && err.data.toLowerCase().startsWith(NONEXISTENT_SELECTOR)) return true;
  if (/execution reverted|nonexistent|owner query for nonexistent|invalid token/i.test(err.message || "")) {
    return true;
  }
  return false;
}

// Classify a single id with retries. Returns {result} (live), {burnt:true}, or throws (transient).
// A live ownerOf ALWAYS returns a 32-byte word; anything else is retried before being trusted.
async function classifyOwner(data, block, attempts = 4, url = RPC) {
  let last;
  for (let k = 0; k < attempts; k++) {
    let r;
    try {
      [r] = await batchCall([data], block, url);
    } catch (e) {
      // Network/rate-limit failure — retryable, never interpretable as "burnt".
      last = { error: { message: String(e.message || e) } };
      await sleep(500 * (k + 1));
      continue;
    }
    if (r && !r.error && r.result && r.result !== "0x") return { result: r.result }; // definitively live
    if (r && r.error && isRevertError(r.error)) return { burnt: true }; // definitively burnt
    last = r;
    await sleep(250 * (k + 1)); // transient/ambiguous -> backoff and retry
  }
  // Persistent empty result on a node that returns 0x for reverts -> treat as burnt.
  if (last && !last.error && (!last.result || last.result === "0x")) return { burnt: true };
  // Persistent non-revert error -> refuse to guess; abort the whole snapshot.
  throw new Error(
    `ownerOf failed non-deterministically after ${attempts} attempts: ${JSON.stringify(last && last.error)} — ` +
      `aborting so a live holder is never silently dropped.`
  );
}

const toInt = (hex) => (hex && hex !== "0x" ? BigInt(hex) : 0n);
const padId = (id) => BigInt(id).toString(16).padStart(64, "0");
const decodeAddr = (word) => "0x" + word.slice(-40);

async function main() {
  // Pin the block for a reproducible snapshot.
  const blockHex = BLOCK === "latest" ? await rpc("eth_blockNumber", []) : BLOCK;
  const block = blockHex;

  const counter = Number(toInt(await ethCall(SEL.tokenId, block)));
  const previousFibonacci = Number(toInt(await ethCall(SEL.previousFibonacci, block)));
  const controlledRaw = toInt(await ethCall(SEL.controlledTransfers, block));
  const controlledTransfers = controlledRaw === 1n;
  const totalTokensBurnt = Number(toInt(await ethCall(SEL.totalTokensBurnt, block)));

  console.log(`V1:        ${V1}`);
  console.log(`block:     ${block} (${Number(block)})`);
  console.log(`counter:   ${counter}`);
  console.log(`prevFib:   ${previousFibonacci}`);
  console.log(`controlled:${controlledTransfers}`);
  console.log(`burnt(V1): ${totalTokensBurnt}`);

  // ownerOf for every ever-minted id. First pass in one batch, then re-classify any
  // element that isn't unambiguously live/burnt (transient errors must NOT read as burnt).
  const datas = [];
  for (let id = 0; id < counter; id++) datas.push(SEL.ownerOf + padId(id));
  const results = await batchCall(datas, block);

  const tokenIds = [];
  const owners = [];
  const burnt = [];
  let undistributed = 0;
  for (let id = 0; id < counter; id++) {
    const r = results[id];
    let resolved;
    if (r && !r.error && r.result && r.result !== "0x") {
      resolved = { result: r.result }; // clearly live in the batch
    } else if (r && r.error && isRevertError(r.error)) {
      resolved = { burnt: true }; // clearly a burn revert in the batch
    } else {
      // ambiguous (transient error / missing / empty) -> re-query individually with retries
      resolved = await classifyOwner(datas[id], block);
    }

    if (resolved.burnt) {
      burnt.push(id);
      continue;
    }
    const owner = decodeAddr(resolved.result);
    tokenIds.push(id);
    owners.push(owner);
    if (owner.toLowerCase() === V1) undistributed++;
  }

  if (tokenIds.length + burnt.length !== counter) {
    throw new Error("accounting mismatch");
  }
  // In THIS contract, ownerOf reverts iff the token was burned (via burn(), which increments
  // totalTokensBurnt). So the omitted count MUST match exactly — otherwise we may have dropped a
  // live holder. Fail loudly rather than ship a lossy snapshot into an irreversible migration.
  if (burnt.length !== totalTokensBurnt) {
    throw new Error(
      `FATAL: omitted ${burnt.length} tokens but V1 totalTokensBurnt=${totalTokensBurnt}. ` +
        `These must match; a live holder may have been dropped. Aborting — do NOT use this snapshot.`
    );
  }

  // Optional cross-verification: re-read EVERYTHING from an independent provider at the same
  // pinned block. Any disagreement aborts the run — the snapshot feeds an irreversible
  // migration, so a single lying RPC must not be able to poison it.
  if (VERIFY_RPC) {
    console.log(`\nCross-verifying against independent RPC…`);
    const counter2 = Number(toInt(await ethCall(SEL.tokenId, block, VERIFY_RPC)));
    if (counter2 !== counter) {
      throw new Error(`FATAL: counter mismatch between providers (${counter} vs ${counter2})`);
    }
    for (let k = 0; k < tokenIds.length; k++) {
      const r = await classifyOwner(SEL.ownerOf + padId(tokenIds[k]), block, 4, VERIFY_RPC);
      if (r.burnt) {
        throw new Error(`FATAL: provider 2 reports token ${tokenIds[k]} burnt; provider 1 said live`);
      }
      const owner2 = decodeAddr(r.result);
      if (owner2.toLowerCase() !== owners[k].toLowerCase()) {
        throw new Error(`FATAL: owner mismatch for token ${tokenIds[k]}: ${owners[k]} vs ${owner2}`);
      }
    }
    for (const id of burnt) {
      const r = await classifyOwner(SEL.ownerOf + padId(id), block, 4, VERIFY_RPC);
      if (!r.burnt) {
        throw new Error(`FATAL: provider 2 reports token ${id} LIVE; provider 1 classified it burnt`);
      }
    }
    console.log(`Cross-verification OK: ${tokenIds.length} owners + ${burnt.length} burnt ids confirmed independently.`);
  } else {
    console.warn(
      "WARN: no --verify-rpc given — snapshot rests on a single provider. For the production run, pass an independent second RPC."
    );
  }

  const out = {
    v1: V1,
    block: Number(block),
    counter,
    previousFibonacci,
    controlledTransfers,
    burnt,
    // Authoritative live-token count, passed to finalizeMigration as the completeness guard.
    liveCount: tokenIds.length,
    // tokens still held by the V1 contract; migration re-points these to the new contract
    undistributedCount: undistributed,
    tokenIds,
    owners,
    crossVerified: Boolean(VERIFY_RPC),
  };

  const path = join(__dirname, "holders.json");
  writeFileSync(path, JSON.stringify(out, null, 2) + "\n");
  console.log(`\nWrote ${tokenIds.length} live holders (+${burnt.length} burnt) -> ${path}`);
  console.log(`undistributed (V1-held, will map to V2): ${undistributed}`);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
