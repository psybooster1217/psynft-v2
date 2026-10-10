import {useState} from "react";
import type {Address, PublicClient} from "viem";
import {gatewayCandidates, readTokenURI} from "../eth";

/**
 * Reads `tokenURI(id)` on-chain, resolves it through the collection's own IPFS gateway (falling
 * back to public gateways when that host is down), fetches the metadata JSON, and renders the
 * token's art. This is the fastest way to confirm that the
 * kene (unique image) for a given id actually resolves — use it after migration to verify the V1
 * art carried over, and after a new Fibonacci batch to verify the new ids render.
 */
export function MetadataPanel({pub, address, baseUri}: {pub: PublicClient; address: Address; baseUri: string}) {
  const [id, setId] = useState("");
  const [busy, setBusy] = useState(false);
  const [status, setStatus] = useState("");
  const [uri, setUri] = useState("");
  const [imgCands, setImgCands] = useState<string[]>([]);
  const [imgIdx, setImgIdx] = useState(0);
  const [metaUrl, setMetaUrl] = useState("");
  const [meta, setMeta] = useState<Record<string, any> | null>(null);

  const imgUrl = imgCands[imgIdx] ?? "";
  const slashOk = !baseUri || baseUri.endsWith("/");

  async function preview() {
    setBusy(true);
    setStatus("reading tokenURI…");
    setUri("");
    setImgCands([]);
    setImgIdx(0);
    setMetaUrl("");
    setMeta(null);
    try {
      const raw = await readTokenURI(pub, address, BigInt(id));
      setUri(raw);
      const cands = gatewayCandidates(raw, baseUri);
      if (cands.length === 0) {
        // tokenURI isn't a resolvable http(s)/ipfs URL — typically baseUri is unset
        // (bare id), or it carries a scheme we refuse to follow.
        setStatus(`tokenURI is not a resolvable URL ("${raw}") — is baseUri set with a trailing "/"?`);
        return;
      }
      let json: any = null;
      let used = "";
      for (const c of cands) {
        setStatus(`fetching metadata via ${new URL(c).host}…`);
        try {
          // a dead gateway can hang for a long time; give each one 8 s
          const res = await fetch(c, {signal: AbortSignal.timeout(8000)});
          if (res.ok) {
            json = await res.json();
            used = c;
            break;
          }
        } catch {
          /* gateway down, CORS, or non-JSON body — try the next one */
        }
      }
      setMetaUrl(used || cands[0]);
      if (json && typeof json === "object") {
        setMeta(json);
        const image = json.image || json.image_url || json.imageUrl || json.animation_url;
        if (image) {
          // try the gateway that just worked for the metadata first
          const worked = used ? new URL(used).origin : "";
          const imgs = gatewayCandidates(String(image), baseUri);
          setImgCands([...imgs.filter((u) => worked && u.startsWith(worked)), ...imgs.filter((u) => !worked || !u.startsWith(worked))]);
        }
        const fellBack = used && used !== cands[0] ? ` (collection gateway down — loaded via ${new URL(used).host})` : "";
        setStatus((image ? "ok" : "metadata loaded, but it has no image field") + fellBack);
      } else {
        // tokenURI may point straight at an image rather than a JSON document.
        setImgCands(cands);
        setStatus("no JSON metadata — treating the URI as an image");
      }
    } catch (e: any) {
      setStatus(e?.shortMessage || e?.message || "nonexistent / burnt id, or baseUri unset");
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="art">
      <div className="art-head">
        <label>Art / metadata preview</label>
        {!slashOk && <span className="warn inline art-warn">⚠ baseUri has no trailing “/” — tokenURI will be malformed</span>}
      </div>
      <div className="lk-row">
        <input placeholder="token id (e.g. 5)" value={id} onChange={(e) => setId(e.target.value)} />
        <button className="btn ghost" onClick={preview} disabled={busy || id === ""}>
          {busy ? "…" : "preview"}
        </button>
      </div>
      {status && <code className="lk-res">{status}</code>}
      {(uri || imgUrl) && (
        <div className="art-body">
          {imgUrl && (
            <a className="art-thumb" href={imgUrl} target="_blank" rel="noreferrer">
              <img
                src={imgUrl}
                alt={`token ${id}`}
                onError={() =>
                  imgIdx + 1 < imgCands.length
                    ? setImgIdx(imgIdx + 1)
                    : setStatus("image did not load from any gateway — the file may no longer be pinned")
                }
              />
            </a>
          )}
          <div className="art-meta">
            {uri && metaUrl && (
              <div className="art-kv">
                <span>tokenURI</span>
                <a className="mono wrap" href={metaUrl} target="_blank" rel="noreferrer">{uri}</a>
              </div>
            )}
            {meta?.name && (
              <div className="art-kv">
                <span>name</span>
                <span>{String(meta.name)}</span>
              </div>
            )}
            {imgUrl && (
              <div className="art-kv">
                <span>image</span>
                <a className="mono wrap" href={imgUrl} target="_blank" rel="noreferrer">{imgUrl}</a>
              </div>
            )}
          </div>
        </div>
      )}
    </div>
  );
}
