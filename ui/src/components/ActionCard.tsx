import {useState} from "react";
import type {Address, PublicClient, WalletClient} from "viem";
import {type ActionDef, parseArg} from "../actions";
import {sendTx} from "../eth";

export interface MyRoles {
  owner: boolean;
  core: boolean;
  treasury: boolean;
  pendingOwner: boolean;
}

interface Props {
  def: ActionDef;
  pub: PublicClient;
  wallet: WalletClient | null;
  account: Address | null;
  address: Address;
  myRoles: MyRoles;
  explorer?: string;
  onDone: () => void;
}

type Status = "idle" | "busy" | "ok" | "err";

function prettyError(e: any): string {
  return e?.shortMessage || e?.details || e?.message || String(e);
}

export function ActionCard({def, pub, wallet, account, address, myRoles, explorer, onDone}: Props) {
  const [values, setValues] = useState<Record<string, string>>({});
  const [status, setStatus] = useState<Status>("idle");
  const [msg, setMsg] = useState<string>("");
  const [hash, setHash] = useState<string>("");

  const authorized = def.role === "any" || (myRoles as any)[def.role] === true;
  const busy = status === "busy";

  function set(name: string, v: string) {
    setValues((s) => ({...s, [name]: v}));
  }

  // The frozen V1 contract. Snapshot entries still owned by V1 (undistributed tokens) must be
  // re-pointed to the NEW contract — minting them to the dead V1 address would strand them
  // forever. This mirrors the repoint logic in script/Migrate.s.sol.
  const V1_ADDRESS = "0x6c6ab7b3215374de4a65de63eac9bc7a0c7f402d";

  function loadHoldersJson(text: string) {
    try {
      const j = JSON.parse(text);
      const ids: unknown[] = j.tokenIds ?? [];
      const rawOwners: unknown[] = j.owners ?? [];
      if (!Array.isArray(ids) || !Array.isArray(rawOwners) || ids.length !== rawOwners.length) {
        throw new Error("expected {tokenIds:[], owners:[]} of equal length");
      }
      let repointed = 0;
      const owners = rawOwners.map((o) => {
        const s = String(o).toLowerCase();
        if (/^0x0{40}$/.test(s)) throw new Error("snapshot contains a zero-address owner — refusing to load");
        if (s === V1_ADDRESS) {
          if (!/^0x[0-9a-fA-F]{40}$/.test(address ?? "")) {
            throw new Error("enter the contract address above first — it is needed to re-point V1-held tokens");
          }
          repointed++;
          return address; // undistributed V1-held token -> custody moves to THIS contract
        }
        return o;
      });
      set("holders", owners.join(", "));
      set("tokenIds", ids.join(", "));
      setMsg(
        `Loaded ${ids.length} entries` +
          (repointed ? ` (${repointed} V1-held token${repointed > 1 ? "s" : ""} re-pointed to this contract)` : "")
      );
      setStatus("idle");
    } catch (e: any) {
      setStatus("err");
      setMsg(`JSON error: ${prettyError(e)}`);
    }
  }

  async function submit() {
    if (!wallet || !account) {
      setStatus("err");
      setMsg("Connect a wallet first.");
      return;
    }
    try {
      const args = def.fields.map((f) => parseArg(f.type, values[f.name] ?? ""));
      if (def.danger && !window.confirm(`Execute "${def.label}" (${def.fn})?\nThis is a sensitive action.`)) return;
      setStatus("busy");
      setHash("");
      setMsg("Simulating…");
      // simulate happens inside sendTx; if it reverts we surface the reason before any wallet prompt
      setMsg("Confirm in your wallet…");
      const h = await sendTx({pub, wallet, account, address, functionName: def.fn, args});
      setHash(h);
      setMsg("Pending…");
      const rcpt = await pub.waitForTransactionReceipt({hash: h});
      if (rcpt.status === "success") {
        setStatus("ok");
        setMsg("Confirmed");
        onDone();
      } else {
        setStatus("err");
        setMsg("Reverted");
      }
    } catch (e: any) {
      setStatus("err");
      setMsg(prettyError(e));
    }
  }

  return (
    <div className={`card ${def.danger ? "card-danger" : ""}`}>
      <div className="card-head">
        <span className="card-title">{def.label}</span>
        <code className="fn">{def.fn}</code>
      </div>
      {def.note && <p className="note">{def.note}</p>}

      {def.fields.map((f) => (
        <label key={f.name} className="field">
          <span className="field-name">
            {f.name} <em>{f.type}</em>
          </span>
          {f.type === "address[]" || f.type === "uint256[]" || f.type === "string" ? (
            <textarea rows={f.type === "string" ? 2 : 2} placeholder={f.placeholder} value={values[f.name] ?? ""} onChange={(e) => set(f.name, e.target.value)} />
          ) : (
            <input placeholder={f.placeholder} value={values[f.name] ?? ""} onChange={(e) => set(f.name, e.target.value)} />
          )}
          {f.help && <small>{f.help}</small>}
        </label>
      ))}

      {def.fn === "migrateBatch" && (
        <details className="json-loader">
          <summary>Paste holders.json to fill fields</summary>
          <textarea rows={3} placeholder='{"tokenIds":[1,2],"owners":["0x…","0x…"]}' onChange={(e) => loadHoldersJson(e.target.value)} />
        </details>
      )}

      {!authorized && account && <div className="warn">⚠ Connected wallet is not the {def.role}. The tx will revert unless it is.</div>}

      <div className="card-foot">
        <button className={def.danger ? "btn danger" : "btn"} disabled={busy || !account} onClick={submit}>
          {busy ? "Working…" : "Execute"}
        </button>
        {msg && <span className={`status status-${status}`}>{msg}</span>}
        {hash && explorer && (
          <a className="txlink" href={`${explorer}/tx/${hash}`} target="_blank" rel="noreferrer">
            view tx ↗
          </a>
        )}
      </div>
    </div>
  );
}
