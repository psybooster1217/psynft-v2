import {useEffect, useMemo, useState} from "react";
import {isAddress, type Address, type WalletClient} from "viem";
import {ACTION_GROUPS, type Role} from "./actions";
import {ActionCard, type MyRoles} from "./components/ActionCard";
import {Dashboard} from "./components/Dashboard";
import {chainName, getEthereum, publicClientFor, readState, short, walletClientFor, type ContractState} from "./eth";

const EXPLORERS: Record<number, string> = {
  1: "https://etherscan.io",
  11155111: "https://sepolia.etherscan.io",
  31337: "",
};

const ENV_ADDR = (import.meta as any).env?.VITE_CONTRACT_ADDRESS as string | undefined;
const ENV_RPC = (import.meta as any).env?.VITE_RPC_URL as string | undefined;

export default function App() {
  const [account, setAccount] = useState<Address | null>(null);
  const [chainId, setChainId] = useState<number>(1);
  // A build-time VITE_CONTRACT_ADDRESS (pinned deployment / sandbox) wins over a stale
  // localStorage value; otherwise remember the last address the user typed.
  const [address, setAddress] = useState<string>(() => ENV_ADDR || localStorage.getItem("psynft.addr") || "");
  const [state, setState] = useState<ContractState | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | undefined>();
  const [refreshKey, setRefreshKey] = useState(0);
  const [onlyMine, setOnlyMine] = useState(false);

  const hasWallet = !!getEthereum();
  const explorer = EXPLORERS[chainId];
  const pub = useMemo(() => publicClientFor(chainId, hasWallet ? undefined : ENV_RPC), [chainId, hasWallet]);
  const wallet: WalletClient | null = useMemo(() => {
    try {
      return account ? walletClientFor(chainId) : null;
    } catch {
      return null;
    }
  }, [account, chainId]);

  // Wallet connection + live account/chain subscriptions.
  useEffect(() => {
    const eth = getEthereum();
    if (!eth) return;
    const onAcc = (a: string[]) => setAccount((a[0] as Address) ?? null);
    const onChain = (c: string) => setChainId(parseInt(c, 16));
    eth.request({method: "eth_accounts"}).then((a: string[]) => a[0] && setAccount(a[0] as Address)).catch(() => {});
    eth.request({method: "eth_chainId"}).then((c: string) => setChainId(parseInt(c, 16))).catch(() => {});
    eth.on?.("accountsChanged", onAcc);
    eth.on?.("chainChanged", onChain);
    return () => {
      eth.removeListener?.("accountsChanged", onAcc);
      eth.removeListener?.("chainChanged", onChain);
    };
  }, []);

  // Persist + read contract state.
  useEffect(() => {
    if (address) localStorage.setItem("psynft.addr", address);
    if (!isAddress(address)) {
      setState(null);
      setError(undefined);
      return;
    }
    let cancelled = false;
    setLoading(true);
    setError(undefined);
    readState(pub, address as Address)
      .then((s) => !cancelled && (setState(s), setLoading(false)))
      .catch((e) => !cancelled && (setError(e?.shortMessage || e?.message || "read failed — check address / network / RPC"), setState(null), setLoading(false)));
    return () => {
      cancelled = true;
    };
  }, [pub, address, refreshKey]);

  const myRoles: MyRoles = useMemo(() => {
    const a = account?.toLowerCase();
    const eq = (x?: string) => !!a && !!x && x.toLowerCase() === a;
    return {owner: eq(state?.owner), core: eq(state?.core), treasury: eq(state?.treasury), pendingOwner: eq(state?.pendingOwner)};
  }, [account, state]);

  const myRoleLabels = (Object.keys(myRoles) as (keyof MyRoles)[]).filter((r) => myRoles[r]);

  async function connect() {
    const eth = getEthereum();
    if (!eth) {
      alert("No injected wallet found. Install MetaMask/Rabby, or connect your Safe via a WalletConnect-capable wallet.");
      return;
    }
    try {
      const accs: string[] = await eth.request({method: "eth_requestAccounts"});
      setAccount((accs[0] as Address) ?? null);
      const c: string = await eth.request({method: "eth_chainId"});
      setChainId(parseInt(c, 16));
    } catch (e: any) {
      alert(e?.message || "connection rejected");
    }
  }

  const refresh = () => setRefreshKey((k) => k + 1);

  return (
    <div className="app">
      <header className="topbar">
        <div className="brand">
          <span className="logo">◈</span>
          <div>
            <div className="title">PsyNFT V2 · Admin</div>
            <div className="subtitle">owner · core · treasury control panel</div>
          </div>
        </div>
        <div className="wallet">
          {account ? (
            <div className="acct">
              <span className="net">{chainName(chainId)}</span>
              <span className="addr mono">{short(account)}</span>
              {myRoleLabels.length > 0 && <span className="roles">{myRoleLabels.join(" · ")}</span>}
            </div>
          ) : (
            <button className="btn" onClick={connect}>
              {hasWallet ? "Connect wallet" : "No wallet detected"}
            </button>
          )}
        </div>
      </header>

      <div className="addrbar">
        <label>
          Contract address
          <input className="mono" placeholder="0x… deployed PsyNFTV2" value={address} onChange={(e) => setAddress(e.target.value.trim())} />
        </label>
        {address && !isAddress(address) && <span className="warn inline">not a valid address</span>}
        {explorer && isAddress(address) && (
          <a className="txlink" href={`${explorer}/address/${address}`} target="_blank" rel="noreferrer">
            Etherscan ↗
          </a>
        )}
      </div>

      {isAddress(address) && <Dashboard state={state} pub={pub} address={address as Address} explorer={explorer} onRefresh={refresh} loading={loading} error={error} />}

      <div className="filters">
        <label className="chk">
          <input type="checkbox" checked={onlyMine} onChange={(e) => setOnlyMine(e.target.checked)} /> Show only actions my wallet can perform
        </label>
      </div>

      <main className="panels">
        {ACTION_GROUPS.filter((g) => !onlyMine || (myRoles as any)[g.role]).map((g) => {
          const can = g.role === "any" || (myRoles as any)[g.role];
          return (
            <section key={g.title} className="group">
              <div className="group-head">
                <h3>{g.title}</h3>
                <span className={`badge ${can ? "badge-ok" : ""}`}>{g.role}</span>
              </div>
              <p className="group-blurb">{g.blurb}</p>
              <div className="cards">
                {g.items.map((def) => (
                  <ActionCard
                    key={def.fn}
                    def={def}
                    pub={pub}
                    wallet={wallet}
                    account={account}
                    address={address as Address}
                    myRoles={myRoles}
                    explorer={explorer}
                    onDone={refresh}
                  />
                ))}
              </div>
            </section>
          );
        })}
      </main>

      <footer className="foot">
        <span>Reads: {hasWallet ? "injected provider" : ENV_RPC ? "env RPC" : "chain default RPC"}.</span>
        <span>Owner actions should be executed from your Gnosis Safe. Every write is simulated before signing.</span>
      </footer>
    </div>
  );
}
