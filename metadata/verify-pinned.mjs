#!/usr/bin/env node
/**
 * Verify a pinned PSYC metadata folder against the files in this repo (audit 2026-10, META-1).
 *
 *   node metadata/verify-pinned.mjs [CID] [gateway]
 *
 * CID defaults to metadata/CID-v2.txt; gateway defaults to https://gateway.pinata.cloud/ipfs/.
 * For every token id 0..33 it checks that <gateway><CID>/<id> is byte-identical to
 * metadata/v2/<id>, and that the image it points to (ipfs://...) loads. Exit code 0 = all good.
 * No dependencies (Node 18+). Run it against TWO different gateways after pinning.
 */
import {readFileSync, readdirSync} from "node:fs";
import {dirname, join} from "node:path";
import {fileURLToPath} from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const cid = process.argv[2] || readFileSync(join(here, "CID-v2.txt"), "utf8").trim();
const gw = (process.argv[3] || "https://gateway.pinata.cloud/ipfs/").replace(/\/?$/, "/");
const ids = readdirSync(join(here, "v2")).filter((f) => /^\d+$/.test(f)).map(Number).sort((a, b) => a - b);

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
async function get(url, method = "GET") {
  for (let attempt = 0; attempt < 5; attempt++) {
    const res = await fetch(url, {method});
    if (res.status === 429) {
      await sleep(3000 * (attempt + 1)); // public gateways rate-limit; back off
      continue;
    }
    return res;
  }
  throw new Error(`rate-limited: ${url}`);
}

let bad = 0;
console.log(`Verifying ${ids.length} metadata files under ${gw}${cid}/`);
for (const id of ids) {
  const want = readFileSync(join(here, "v2", String(id)));
  try {
    const res = await get(`${gw}${cid}/${id}`);
    const got = Buffer.from(await res.arrayBuffer());
    if (!res.ok || !got.equals(want)) {
      bad++;
      console.log(`  ✗ ${id}: ${res.ok ? "content differs" : "HTTP " + res.status}`);
      continue;
    }
    const image = JSON.parse(got.toString("utf8")).image;
    const imgPath = image.replace(/^ipfs:\/\//, "");
    const img = await get(`${gw}${imgPath}`, "HEAD");
    if (!img.ok) {
      bad++;
      console.log(`  ✗ ${id}: metadata OK, image ${image} -> HTTP ${img.status}`);
    } else {
      console.log(`  ✓ ${id}  ${image}`);
    }
  } catch (e) {
    bad++;
    console.log(`  ✗ ${id}: ${e.message}`);
  }
  await sleep(300);
}
console.log(bad === 0 ? `\nALL ${ids.length} OK — safe to deploy with BASE_URI=ipfs://${cid}/` : `\n${bad} PROBLEM(S) — do not deploy yet`);
process.exit(bad === 0 ? 0 : 1);
