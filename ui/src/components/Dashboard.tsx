import {useState} from "react";
import type {Address, PublicClient} from "viem";
import {type ContractState, isZero, readApprovedTransfer, readBalanceOf, readOwnerOf, short} from "../eth";
import {MetadataPanel} from "./MetadataPanel";

interface Props {
  state: ContractState | null;
  pub: PublicClient;
  address: Address;
  explorer?: string;
  onRefresh: () => void;
  loading: boolean;
  error?: string;
}

function Row({label, value, mono}: {label: string; value: React.ReactNode; mono?: boolean}) {
  return (
    <div className="kv">
      <span className="k">{label}</span>
      <span className={`v ${mono ? "mono" : ""}`}>{value}</span>
    </div>
  );
}

function Flag({on}: {on: boolean}) {
  return <span className={`flag ${on ? "on" : "off"}`}>{on ? "true" : "false"}</span>;
}

export function Dashboard({state, pub, address, explorer, onRefresh, loading, error}: Props) {
  const [idQuery, setIdQuery] = useState("");
  const [ownerResult, setOwnerResult] = useState("");
  const [balQuery, setBalQuery] = useState("");
  const [balResult, setBalResult] = useState("");
  const [apprResult, setApprResult] = useState("");

  const link = (addr?: string) =>
    addr && explorer && !isZero(addr) ? (
      <a href={`${explorer}/address/${addr}`} target="_blank" rel="noreferrer">
        {short(addr)}
      </a>
    ) : (
      <span title={addr}>{isZero(addr) ? "unset (0x0)" : short(addr)}</span>
    );

  async function lookupOwner() {
    setOwnerResult("…");
    try {
      const o = await readOwnerOf(pub, address, BigInt(idQuery));
      setOwnerResult(o);
    } catch (e: any) {
      setOwnerResult(e?.shortMessage || "nonexistent / burnt");
    }
  }
  async function lookupBalance() {
    setBalResult("…");
    try {
      setBalResult(String(await readBalanceOf(pub, address, balQuery as Address)));
    } catch (e: any) {
      setBalResult(e?.shortMessage || "error");
    }
  }
  async function lookupAppr() {
    setApprResult("…");
    try {
      const a = await readApprovedTransfer(pub, address, BigInt(idQuery || "0"));
      const exp = Number(a.transferExpiryDate);
      const when = exp === 0 ? "none" : new Date(exp * 1000).toISOString();
      setApprResult(`to ${short(a.to)} · expires ${when}`);
    } catch (e: any) {
      setApprResult(e?.shortMessage || "error");
    }
  }

  return (
    <section className="dash">
      <div className="dash-head">
        <h2>Contract state</h2>
        <button className="btn ghost" onClick={onRefresh} disabled={loading}>
          {loading ? "Reading…" : "↻ Refresh"}
        </button>
      </div>
      {error && <div className="warn">{error}</div>}
      {!state && !error && <p className="muted">Enter a contract address to read state.</p>}
      {state && (
        <>
          <div className="grid">
            <Row label="name / symbol" value={`${state.name} (${state.symbol})`} />
            <Row label="owner" value={link(state.owner)} mono />
            <Row label="pendingOwner" value={link(state.pendingOwner)} mono />
            <Row label="core" value={link(state.core)} mono />
            <Row label="treasury" value={link(state.treasury)} mono />
            <Row label="tokenId (next)" value={String(state.tokenId)} />
            <Row label="previousFibonacci" value={String(state.previousFibonacci)} />
            <Row label="totalTokensBurnt" value={String(state.totalTokensBurnt)} />
            <Row label="migratedCount" value={String(state.migratedCount)} />
            <Row label="initialMintCalled" value={<Flag on={state.initialMintCalled} />} />
            <Row label="migrationStarted" value={<Flag on={state.migrationStarted} />} />
            <Row label="migrationFinalized" value={<Flag on={state.migrationFinalized} />} />
            <Row label="controlledTransfers" value={<Flag on={state.controlledTransfers} />} />
          </div>
          <Row
            label="baseUri"
            value={
              <span className="mono wrap">
                {state.baseUri || "unset"}
                {state.baseUri && !state.baseUri.endsWith("/") && <span className="warn inline"> ⚠ no trailing “/”</span>}
              </span>
            }
          />

          <div className="lookups">
            <div className="lookup">
              <label>ownerOf / approvedTransfers</label>
              <div className="lk-row">
                <input placeholder="token id" value={idQuery} onChange={(e) => setIdQuery(e.target.value)} />
                <button className="btn ghost" onClick={lookupOwner}>owner</button>
                <button className="btn ghost" onClick={lookupAppr}>approval</button>
              </div>
              {ownerResult && <code className="lk-res">{ownerResult}</code>}
              {apprResult && <code className="lk-res">{apprResult}</code>}
            </div>
            <div className="lookup">
              <label>balanceOf</label>
              <div className="lk-row">
                <input placeholder="0x… address" value={balQuery} onChange={(e) => setBalQuery(e.target.value)} />
                <button className="btn ghost" onClick={lookupBalance}>query</button>
              </div>
              {balResult && <code className="lk-res">{balResult}</code>}
            </div>
          </div>

          <MetadataPanel pub={pub} address={address} baseUri={state.baseUri} />
        </>
      )}
    </section>
  );
}
