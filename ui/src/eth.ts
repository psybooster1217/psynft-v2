import {
  createPublicClient,
  createWalletClient,
  custom,
  http,
  type Address,
  type Chain,
  type PublicClient,
  type WalletClient,
} from "viem";
import {mainnet, sepolia, foundry} from "viem/chains";
import {PSYNFT_V2_ABI} from "./abi";

export const SUPPORTED_CHAINS: Record<number, Chain> = {
  1: mainnet,
  11155111: sepolia,
  31337: foundry,
};

export function chainName(id: number): string {
  return SUPPORTED_CHAINS[id]?.name ?? `Chain ${id}`;
}

export function getEthereum(): any | undefined {
  return typeof window !== "undefined" ? (window as any).ethereum : undefined;
}

export function publicClientFor(chainId: number, rpcUrl?: string): PublicClient {
  const chain = SUPPORTED_CHAINS[chainId] ?? mainnet;
  const eth = getEthereum();
  const transport = rpcUrl ? http(rpcUrl) : eth ? custom(eth) : http();
  return createPublicClient({chain, transport});
}

export function walletClientFor(chainId: number): WalletClient {
  const chain = SUPPORTED_CHAINS[chainId] ?? mainnet;
  const eth = getEthereum();
  if (!eth) throw new Error("No injected wallet found (install MetaMask/Rabby, or use the sandbox accounts).");
  return createWalletClient({chain, transport: custom(eth)});
}

/**
 * Sandbox wallet (local anvil only). anvil keeps its dev accounts unlocked and can impersonate
 * any address, so the node signs `eth_sendTransaction` itself: no private key ever lives in this
 * app. Only offered when the read RPC reports chainId 31337.
 */
export function sandboxWalletClient(rpcUrl: string): WalletClient {
  return createWalletClient({chain: foundry, transport: http(rpcUrl)});
}

export async function sandboxAccounts(pub: PublicClient): Promise<Address[]> {
  return (await pub.request({method: "eth_accounts"} as any)) as Address[];
}

/** Lets the sandbox act as any address (e.g. the real Main Safe or a real holder on a fork). */
export async function sandboxImpersonate(pub: PublicClient, who: Address): Promise<void> {
  await pub.request({method: "anvil_impersonateAccount", params: [who]} as any);
  // give it gas money on the local chain
  await pub.request({method: "anvil_setBalance", params: [who, "0x56BC75E2D63100000"]} as any);
}

/** Safe Transaction Builder file for one or more calls (import via Safe -> Apps -> Transaction Builder). */
export function safeBuilderJson(chainId: number, safe: Address | undefined, txs: {to: Address; data: `0x${string}`; label: string}[]): string {
  return JSON.stringify(
    {
      version: "1.0",
      chainId: String(chainId),
      createdAt: Date.now(),
      meta: {
        name: `PsyNFT V2: ${txs.map((t) => t.label).join(", ")}`.slice(0, 120),
        description: "Exported from the PsyNFT V2 admin panel. Check the decoded calls in the Safe UI before signing.",
        ...(safe ? {createdFromSafeAddress: safe} : {}),
      },
      transactions: txs.map((t) => ({to: t.to, value: "0", data: t.data, contractMethod: null, contractInputsValues: null})),
    },
    null,
    2
  );
}

export interface ContractState {
  name: string;
  symbol: string;
  owner: Address;
  pendingOwner: Address;
  core: Address;
  treasury: Address;
  tokenId: bigint;
  previousFibonacci: bigint;
  totalTokensBurnt: bigint;
  migratedCount: bigint;
  initialMintCalled: boolean;
  migrationStarted: boolean;
  migrationFinalized: boolean;
  controlledTransfers: boolean;
  baseUri: string;
}

export async function readState(pub: PublicClient, address: Address): Promise<ContractState> {
  const base = {address, abi: PSYNFT_V2_ABI} as const;
  const call = <T>(functionName: string) => pub.readContract({...base, functionName: functionName as any}) as Promise<T>;
  const [
    name,
    symbol,
    owner,
    pendingOwner,
    core,
    treasury,
    tokenId,
    previousFibonacci,
    totalTokensBurnt,
    migratedCount,
    initialMintCalled,
    migrationStarted,
    migrationFinalized,
    controlledTransfers,
    baseUri,
  ] = await Promise.all([
    call<string>("name"),
    call<string>("symbol"),
    call<Address>("owner"),
    call<Address>("pendingOwner"),
    call<Address>("core"),
    call<Address>("treasury"),
    call<bigint>("tokenId"),
    call<bigint>("previousFibonacci"),
    call<bigint>("totalTokensBurnt"),
    call<bigint>("migratedCount"),
    call<boolean>("initialMintCalled"),
    call<boolean>("migrationStarted"),
    call<boolean>("migrationFinalized"),
    call<boolean>("controlledTransfers"),
    call<string>("baseUri"),
  ]);

  return {
    name,
    symbol,
    owner,
    pendingOwner,
    core,
    treasury,
    tokenId,
    previousFibonacci,
    totalTokensBurnt,
    migratedCount,
    initialMintCalled,
    migrationStarted,
    migrationFinalized,
    controlledTransfers,
    baseUri,
  };
}

export async function readOwnerOf(pub: PublicClient, address: Address, id: bigint): Promise<Address> {
  return (await pub.readContract({address, abi: PSYNFT_V2_ABI, functionName: "ownerOf", args: [id]})) as Address;
}

export async function readTokenURI(pub: PublicClient, address: Address, id: bigint): Promise<string> {
  return (await pub.readContract({address, abi: PSYNFT_V2_ABI, functionName: "tokenURI", args: [id]})) as string;
}

/**
 * Reuse the collection's own IPFS gateway (e.g. its Pinata host) to resolve previews so they
 * load fast and without CORS surprises. Falls back to a public gateway if baseUri isn't an
 * `…/ipfs/CID/` URL (e.g. a bare `ipfs://` baseUri).
 */
export function gatewayFromBaseUri(baseUri?: string): string {
  const m = baseUri?.match(/^(https?:\/\/[^/]+\/ipfs\/)/i);
  return m ? m[1] : PUBLIC_GATEWAYS[0];
}

/**
 * Public gateways tried in order when the collection's own gateway fails (audit 2026-10, UI-9:
 * V1's dedicated Pinata host stopped resolving, which silently broke every preview).
 */
export const PUBLIC_GATEWAYS = ["https://gateway.pinata.cloud/ipfs/", "https://ipfs.io/ipfs/", "https://dweb.link/ipfs/"];

/** "CID/path" for `ipfs://CID/path` or `https://any-host/ipfs/CID/path`; null otherwise. */
export function ipfsPath(uri: string): string | null {
  if (!uri) return null;
  if (uri.startsWith("ipfs://")) return uri.slice("ipfs://".length).replace(/^ipfs\//, "") || null;
  const m = uri.match(/^https?:\/\/[^/]+\/ipfs\/(.+)$/i);
  return m ? m[1] : null;
}

/**
 * Every http(s) URL worth trying for an on-chain/metadata URI, best first: the collection's own
 * gateway, then the public ones. Non-IPFS http(s) URLs are returned as-is; anything else
 * (javascript:, data:, relative …) yields [] because these values are untrusted.
 */
export function gatewayCandidates(uri: string, baseUri?: string): string[] {
  const path = ipfsPath(uri);
  if (!path) return /^https?:\/\//i.test(uri) ? [uri] : [];
  const own = baseUri?.match(/^(https?:\/\/[^/]+\/ipfs\/)/i)?.[1];
  const gws = own ? [own, ...PUBLIC_GATEWAYS] : PUBLIC_GATEWAYS;
  return Array.from(new Set(gws.map((g) => g + path)));
}

/**
 * Normalize an `ipfs://…` URI to an HTTP gateway URL; pass http(s) URLs through unchanged.
 * Anything else (javascript:, data:, relative, …) returns "" — these values come from
 * on-chain strings and remote metadata JSON, so they are untrusted and must never become
 * a clickable href or fetch target with an arbitrary scheme.
 */
export function ipfsToHttp(uri: string, gateway = "https://ipfs.io/ipfs/"): string {
  if (!uri) return "";
  if (uri.startsWith("ipfs://")) {
    const path = uri.slice("ipfs://".length).replace(/^ipfs\//, "");
    return gateway.replace(/\/?$/, "/") + path;
  }
  return /^https?:\/\//i.test(uri) ? uri : "";
}

export async function readBalanceOf(pub: PublicClient, address: Address, who: Address): Promise<bigint> {
  return (await pub.readContract({address, abi: PSYNFT_V2_ABI, functionName: "balanceOf", args: [who]})) as bigint;
}

export interface ApprovedTransfer {
  tokenId: bigint;
  transferExpiryDate: bigint;
  to: Address;
}

export async function readApprovedTransfer(pub: PublicClient, address: Address, id: bigint): Promise<ApprovedTransfer> {
  const r = (await pub.readContract({
    address,
    abi: PSYNFT_V2_ABI,
    functionName: "approvedTransfers",
    args: [id],
  })) as readonly [bigint, bigint, Address];
  return {tokenId: r[0], transferExpiryDate: r[1], to: r[2]};
}

/** Simulate then send a write. Returns the tx hash. Throws with a decoded revert reason. */
export async function sendTx(params: {
  pub: PublicClient;
  wallet: WalletClient;
  account: Address;
  address: Address;
  functionName: string;
  args: unknown[];
}): Promise<`0x${string}`> {
  const {pub, wallet, account, address, functionName, args} = params;
  const {request} = await pub.simulateContract({
    address,
    abi: PSYNFT_V2_ABI,
    functionName: functionName as any,
    args: args as any,
    account,
  });
  return wallet.writeContract(request as any);
}

export function isZero(addr?: string): boolean {
  return !addr || /^0x0{40}$/i.test(addr);
}

export function short(addr?: string): string {
  if (!addr) return "—";
  return addr.length > 12 ? `${addr.slice(0, 6)}…${addr.slice(-4)}` : addr;
}

/** Save a text file in the browser (used for Safe Transaction Builder exports). */
export function downloadText(filename: string, text: string): void {
  const url = URL.createObjectURL(new Blob([text], {type: "application/json"}));
  const a = document.createElement("a");
  a.href = url;
  a.download = filename;
  a.click();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}
