import {useEffect, useMemo, useState} from "react";
import {isAddress, type Address, type WalletClient} from "viem";
import {ACTION_GROUPS, type Role} from "./actions";
import {ActionCard, type MyRoles, type SafeTx} from "./components/ActionCard";
import {Dashboard} from "./components/Dashboard";
import {
  SUPPORTED_CHAINS,
  chainName,
  downloadText,
  getEthereum,
  publicClientFor,
  readState,
  safeBuilderJson,
  sandboxAccounts,
  sandboxImpersonate,
  sandboxWalletClient,
  short,
  walletClientFor,
  type ContractState,
} from "./eth";

const EXPLORERS: Record<number, string> = {
  1: "https://etherscan.io",
  11155111: "https://sepolia.etherscan.io",
  31337: "",
};

const ENV_ADDR = (import.meta as any).env?.VITE_CONTRACT_ADDRESS as string | undefined;
const ENV_RPC = (import.meta as any).env?.VITE_RPC_URL as string | undefined;
/** Optional: the chain this deployment lives on (e.g. 1). Enables the wrong-network banner. */
const ENV_CHAIN = Number((import.meta as any).env?.VITE_CHAIN_ID || 0) || undefined;

const isZeroAddr = (a?: string) => !a || /^0x0{40}$/i.test(a);

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
  // chainId reported by VITE_RPC_URL itself, so label/explorer are right without a wallet (UI-8)
  const [rpcChainId, setRpcChainId] = useState<number | undefined>();
  // "sandbox" = local anvil accounts / impersonation, signed by the node (no keys in the app)
  const [mode, setMode] = useState<"injected" | "sandbox">("injected");
  const [sandboxList, setSandboxList] = useState<Address[]>([]);
  const [actAs, setActAs] = useState("");
  const [batch, setBatch] = useState<SafeTx[]>([]);

  const hasWallet = !!getEthereum();
  const useRpc = mode === "sandbox" || !hasWallet;
  const activeChain = useRpc ? (rpcChainId ?? chainId) : chainId;
  const explorer = EXPLORERS[activeChain];
  const sandboxAvailable = !!ENV_RPC && rpcChainId === 31337;
  const pub = useMemo(() => publicClientFor(activeChain, useRpc ? ENV_RPC : undefined), [activeChain, useRpc]);
  const wallet: WalletClient | null = useMemo(() => {
    try {
      if (!account) return null;
      return mode === "sandbox" && ENV_RPC ? sandboxWalletClient(ENV_RPC) : walletClientFor(chainId);
    } catch {
      return null;
    }
  }, [account, chainId, mode]);

  // Ask the configured RPC which chain it serves.
  useEffect(() => {
    if (!ENV_RPC) return;
    publicClientFor(31337, ENV_RPC)
      .getChainId()
      .then(setRpcChainId)
      .catch(() => setRpcChainId(undefined));
  }, []);

  // Local sandbox: list anvil's unlocked dev accounts.
  useEffect(() => {
    if (!sandboxAvailable || !ENV_RPC) return;
    sandboxAccounts(publicClientFor(31337, ENV_RPC))
      .then((a) => setSandboxList(a.slice(0, 10)))
      .catch(() => setSandboxList([]));
  }, [sandboxAvailable]);

  // Wallet connection + live account/chain subscriptions.
  useEffect(() => {
    const eth = getEthereum();
    if (!eth) return;
    const onAcc = (a: string[]) => mode === "injected" && setAccount((a[0] as Address) ?? null);
    const onChain = (c: string) => setChainId(parseInt(c, 16));
    eth.request({method: "eth_accounts"}).then((a: string[]) => a[0] && mode === "injected" && setAccount(a[0] as Address)).catch(() => {});
    eth.request({method: "eth_chainId"}).then((c: string) => setChainId(parseInt(c, 16))).catch(() => {});
    eth.on?.("accountsChanged", onAcc);
    eth.on?.("chainChanged", onChain);
    return () => {
      eth.removeListener?.("accountsChanged", onAcc);
      eth.removeListener?.("chainChanged", onChain);
    };
  }, [mode]);

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

  async function useSandbox(who: string) {
    if (!who) return;
    if (!isAddress(who)) {
      alert("not a valid address");
      return;
    }
    try {
      if (!sandboxList.some((a) => a.toLowerCase() === who.toLowerCase())) {
        await sandboxImpersonate(publicClientFor(31337, ENV_RPC), who as Address);
      }
      setMode("sandbox");
      setAccount(who as Address);
    } catch (e: any) {
      alert(e?.shortMessage || e?.message || "impersonation failed (is this an anvil node?)");
    }
  }

  async function connect() {
    setMode("injected");
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

  // Forget the wallet locally, and best-effort revoke the site's permission so a page
  // refresh doesn't silently reconnect the same (possibly wrong) account. Older wallets
  // don't support wallet_revokePermissions — the local clear still fully disconnects the UI.
  async function disconnect() {
    const eth = getEthereum();
    try {
      await eth?.request?.({method: "wallet_revokePermissions", params: [{eth_accounts: {}}]});
    } catch {
      /* unsupported wallet — soft clear below is enough */
    }
    setAccount(null);
    setMode("injected");
  }

  // Re-open the wallet's account picker so the operator can switch to a different account
  // (e.g. after realising they connected the wrong one). Cancelling leaves the current one.
  async function switchWallet() {
    if (mode === "sandbox") return disconnect();
    const eth = getEthereum();
    if (!eth) return connect();
    try {
      await eth.request({method: "wallet_requestPermissions", params: [{eth_accounts: {}}]});
      const accs: string[] = await eth.request({method: "eth_accounts"});
      setAccount((accs[0] as Address) ?? null);
    } catch {
      /* user dismissed the picker — keep the current account */
    }
  }

  const refresh = () => setRefreshKey((k) => k + 1);

  function roleHolder(role: string): Address | undefined {
    if (!state) return undefined;
    if (role === "owner") return state.owner;
    if (role === "core") return state.core;
    if (role === "treasury") return state.treasury;
    if (role === "pendingOwner") return isZeroAddr(state.pendingOwner) ? undefined : state.pendingOwner;
    return undefined;
  }

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
              <span className="net">{mode === "sandbox" ? "Sandbox" : chainName(chainId)}</span>
              <span className="addr mono" title={account}>{short(account)}</span>
              {myRoleLabels.length > 0 ? (
                <span className="roles">{myRoleLabels.join(" · ")}</span>
              ) : (
                <span className="roles norole" title="This wallet is not owner/core/treasury — writes will revert. Switch if this is the wrong account.">no admin roles</span>
              )}
              <button className="btn ghost sm" onClick={switchWallet} title="Connect a different account">Switch</button>
              <button className="btn ghost sm" onClick={disconnect} title="Disconnect this wallet from the dApp">Disconnect</button>
            </div>
          ) : (
            <div className="acct">
              {hasWallet && (
                <button className="btn" onClick={connect}>
                  Connect wallet
                </button>
              )}
              {sandboxAvailable && (
                <select className="sandbox-pick" value="" onChange={(e) => useSandbox(e.target.value)} title="Local sandbox: anvil signs for its dev accounts; no keys involved">
                  <option value="">Sandbox account…</option>
                  {sandboxList.map((a, i) => (
                    <option key={a} value={a}>
                      #{i} {short(a)}
                    </option>
                  ))}
                </select>
              )}
              {!hasWallet && !sandboxAvailable && <span className="roles norole">No wallet detected (reads only)</span>}
            </div>
          )}
        </div>
      </header>

      {sandboxAvailable && (
        <div className="sandbox-bar">
          <span>Local sandbox (chainId 31337). Pick an account above, or act as any address (e.g. the real Main Safe or a holder on a mainnet fork):</span>
          <input className="mono" placeholder="0x… address to act as" value={actAs} onChange={(e) => setActAs(e.target.value.trim())} />
          <button className="btn ghost sm" onClick={() => useSandbox(actAs)}>
            Act as
          </button>
        </div>
      )}

      {account && mode === "injected" && ENV_CHAIN && chainId !== ENV_CHAIN && (
        <div className="banner banner-err">
          Your wallet is on <b>{chainName(chainId)}</b>, but this deployment lives on <b>{chainName(ENV_CHAIN)}</b>. Switch network before doing anything.
        </div>
      )}
      {!SUPPORTED_CHAINS[activeChain] && <div className="banner banner-err">Unsupported network (chain {activeChain}). Supported: Ethereum, Sepolia, local sandbox.</div>}

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
                    chainId={activeChain}
                    roleAddress={roleHolder(def.role)}
                    onAddToBatch={(tx) => setBatch((b) => [...b, tx])}
                  />
                ))}
              </div>
            </section>
          );
        })}
      </main>

      {batch.length > 0 && (
        <div className="batch-bar">
          <b>
            Safe batch · {batch.length} call{batch.length > 1 ? "s" : ""}
          </b>
          <ol>
            {batch.map((t, i) => (
              <li key={i} className="mono">
                {t.label}
              </li>
            ))}
          </ol>
          <button className="btn sm" onClick={() => downloadText("psynft-safe-batch.json", safeBuilderJson(activeChain, state?.owner, batch))}>
            Download for Transaction Builder
          </button>
          <button className="btn ghost sm" onClick={() => setBatch([])}>
            Clear
          </button>
        </div>
      )}

      <footer className="foot">
        <span>Reads: {useRpc ? (ENV_RPC ? "env RPC" : "chain default RPC") : "injected provider"}.</span>
        <span>
          Owner/core/treasury actions belong on the Safe: use <b>Export for Safe</b> or <b>+ Safe batch</b>, then import the file in Safe → Apps → Transaction Builder.
          Every action is simulated before you sign or export.
        </span>
      </footer>
    </div>
  );
}
