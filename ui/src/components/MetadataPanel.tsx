import {useState} from "react";
import type {Address, PublicClient} from "viem";
import {gatewayFromBaseUri, ipfsToHttp, readTokenURI} from "../eth";

/**
 * Reads `tokenURI(id)` on-chain, resolves it through the collection's own IPFS gateway, fetches
 * the metadata JSON, and renders the token's art. This is the fastest way to confirm that the
 * kene (unique image) for a given id actually resolves — use it after migration to verify the V1
 * art carried over, and after a new Fibonacci batch to verify the new ids render.
 */
export function MetadataPanel({pub, address, baseUri}: {pub: PublicClient; address: Address; baseUri: string}) {
  const [id, setId] = useState("");
  const [busy, setBusy] = useState(false);
  const [status, setStatus] = useState("");
  const [uri, setUri] = useState("");
  const [imgUrl, setImgUrl] = useState("");
  const [meta, setMeta] = useState<Record<string, any> | null>(null);

  const gateway = gatewayFromBaseUri(baseUri);
  const slashOk = !baseUri || baseUri.endsWith("/");

  async function preview() {
    setBusy(true);
    setStatus("reading tokenURI…");
    setUri("");
    setImgUrl("");
    setMeta(null);
    try {
      const raw = await readTokenURI(pub, address, BigInt(id));
      setUri(raw);
      const metaUrl = ipfsToHttp(raw, gateway);
      if (!metaUrl) {
        // tokenURI isn't a resolvable http(s)/ipfs URL — typically baseUri is unset
        // (bare id), or it carries a scheme we refuse to follow.
        setStatus(`tokenURI is not a resolvable URL ("${raw}") — is baseUri set with a trailing "/"?`);
        return;
      }
      setStatus("fetching metadata…");
      let json: any = null;
      try {
        const res = await fetch(metaUrl);
        if (res.ok) json = await res.json();
      } catch {
        /* CORS or non-JSON body — fall through to treating the URI as an image */
      }
      if (json && typeof json === "object") {
        setMeta(json);
        const image = json.image || json.image_url || json.imageUrl || json.animation_url;
        if (image) setImgUrl(ipfsToHttp(String(image), gateway));
        setStatus(image ? "ok" : "metadata loaded, but it has no image field");
      } else {
        // tokenURI may point straight at an image rather than a JSON document.
        setImgUrl(metaUrl);
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
              <img src={imgUrl} alt={`token ${id}`} onError={() => setStatus("image URL did not load (gateway/CORS) — open it directly ↗")} />
            </a>
          )}
          <div className="art-meta">
            {uri && ipfsToHttp(uri, gateway) && (
              <div className="art-kv">
                <span>tokenURI</span>
                <a className="mono wrap" href={ipfsToHttp(uri, gateway)} target="_blank" rel="noreferrer">{uri}</a>
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
