import {getAddress, isAddress} from "viem";

export type Role = "owner" | "core" | "treasury" | "pendingOwner" | "any";
export type FieldType = "address" | "uint256" | "bool" | "string" | "address[]" | "uint256[]";

export interface Field {
  name: string;
  type: FieldType;
  placeholder?: string;
  help?: string;
}

export interface ActionDef {
  fn: string;
  label: string;
  role: Role;
  fields: Field[];
  note?: string;
  danger?: boolean; // require an extra confirm
}

export interface ActionGroup {
  title: string;
  role: Role;
  blurb: string;
  items: ActionDef[];
}

/** Parse one raw input string into the ABI-ready value for its type. Throws on invalid input. */
export function parseArg(type: FieldType, raw: string): unknown {
  const v = raw.trim();
  switch (type) {
    case "address": {
      if (!isAddress(v)) throw new Error(`invalid address: "${v}"`);
      return getAddress(v);
    }
    case "uint256": {
      if (!/^\d+$/.test(v)) throw new Error(`expected a whole number, got "${v}"`);
      return BigInt(v);
    }
    case "bool": {
      if (v === "true") return true;
      if (v === "false") return false;
      throw new Error(`expected true/false, got "${v}"`);
    }
    case "string":
      return raw; // preserve as typed
    case "address[]": {
      const parts = splitList(v);
      return parts.map((p) => {
        if (!isAddress(p)) throw new Error(`invalid address in list: "${p}"`);
        return getAddress(p);
      });
    }
    case "uint256[]": {
      const parts = splitList(v);
      return parts.map((p) => {
        if (!/^\d+$/.test(p)) throw new Error(`invalid number in list: "${p}"`);
        return BigInt(p);
      });
    }
  }
}

function splitList(v: string): string[] {
  return v
    .replace(/[\[\]]/g, "")
    .split(/[\s,]+/)
    .map((s) => s.trim())
    .filter(Boolean);
}

export const ACTION_GROUPS: ActionGroup[] = [
  {
    title: "Owner · Admin",
    role: "owner",
    blurb: "High-stakes configuration. Execute from the Gnosis Safe.",
    items: [
      {fn: "setCoreContract", label: "Set core contract", role: "owner", fields: [{name: "_core", type: "address", placeholder: "0x… new core"}]},
      {fn: "setTreasury", label: "Set treasury", role: "owner", fields: [{name: "_treasury", type: "address", placeholder: "0x… new treasury"}]},
      {
        fn: "setBaseUri",
        label: "Set base URI",
        role: "owner",
        fields: [
          {
            name: "_uri",
            type: "string",
            placeholder: "ipfs://CID/ or https://gateway/ipfs/CID/",
            help: "Must end with a trailing “/”. Every id resolves to baseURI + tokenId under this one folder. See docs/METADATA.md.",
          },
        ],
        note: "Token metadata resolves to baseURI + tokenId. Point it at the IPFS folder holding your metadata files; carrying over V1 art = set this to V1's CID.",
      },
      {fn: "enableControlledTransfers", label: "Enable controlled transfers", role: "owner", fields: []},
      {fn: "disableControlledTransfers", label: "Disable controlled transfers", role: "owner", fields: [], danger: true},
      {
        fn: "transferOwnership",
        label: "Transfer ownership (step 1 of 2)",
        role: "owner",
        fields: [{name: "newOwner", type: "address", placeholder: "0x… new owner / Safe"}],
        note: "Ownable2Step: the new owner must then call acceptOwnership.",
        danger: true,
      },
    ],
  },
  {
    title: "Pending owner",
    role: "pendingOwner",
    blurb: "Finalize an ownership transfer.",
    items: [{fn: "acceptOwnership", label: "Accept ownership (step 2 of 2)", role: "pendingOwner", fields: []}],
  },
  {
    title: "Owner · Migration",
    role: "owner",
    blurb: "One-shot re-mint of the V1 holders. Prefer the Migrate.s.sol script for the real run.",
    items: [
      {
        fn: "migrateBatch",
        label: "Migrate batch",
        role: "owner",
        fields: [
          {name: "holders", type: "address[]", placeholder: "0xabc…, 0xdef… (or paste holders.json below)"},
          {name: "tokenIds", type: "uint256[]", placeholder: "1, 2, 3 …"},
        ],
        note: "Re-mints each tokenId to its holder. Use the JSON loader below to fill both fields.",
      },
      {
        fn: "finalizeMigration",
        label: "Finalize migration",
        role: "owner",
        fields: [
          {name: "nextTokenId", type: "uint256", placeholder: "34"},
          {name: "previousFibonacci_", type: "uint256", placeholder: "21"},
          {name: "controlledTransfers_", type: "bool", placeholder: "true"},
          {name: "expectedCount", type: "uint256", placeholder: "33 (must equal migratedCount)"},
        ],
        note: "Irreversible. Reverts unless migratedCount == expectedCount.",
        danger: true,
      },
    ],
  },
  {
    title: "Owner · Rescue",
    role: "owner",
    blurb: "Recover assets sent to the contract by mistake. Amounts are in base units (wei).",
    items: [
      {
        fn: "rescueERC20",
        label: "Rescue ERC-20",
        role: "owner",
        fields: [
          {name: "token", type: "address", placeholder: "0x… token"},
          {name: "to", type: "address", placeholder: "0x… recipient"},
          {name: "amount", type: "uint256", placeholder: "amount in base units"},
        ],
      },
      {
        fn: "rescueERC721",
        label: "Rescue ERC-721 (foreign)",
        role: "owner",
        fields: [
          {name: "token", type: "address", placeholder: "0x… foreign NFT (not this contract)"},
          {name: "to", type: "address", placeholder: "0x… recipient"},
          {name: "tokenId_", type: "uint256", placeholder: "token id"},
        ],
      },
      {
        fn: "rescueETH",
        label: "Rescue ETH",
        role: "owner",
        fields: [
          {name: "to", type: "address", placeholder: "0x… recipient"},
          {name: "amount", type: "uint256", placeholder: "amount in wei"},
        ],
      },
    ],
  },
  {
    title: "Core · Mint & distribute",
    role: "core",
    blurb: "Routine operations. Call from the core address.",
    items: [
      {fn: "initialMint", label: "Initial mint (fresh deploy only)", role: "core", fields: [], note: "Mints ids 0–2 to the contract. Unavailable after migration."},
      {fn: "batchMintInFibonacci", label: "Mint next Fibonacci batch", role: "core", fields: [], note: "Mints previousFibonacci tokens to the contract."},
      {
        fn: "transferNFTs",
        label: "Distribute NFTs",
        role: "core",
        fields: [
          {name: "_tokenIds", type: "uint256[]", placeholder: "1, 2, 3 …"},
          {name: "_recipient", type: "address", placeholder: "0x… member"},
        ],
        note: "Sends contract-held tokens to a member.",
      },
      {
        fn: "approveTransfer",
        label: "Approve a member transfer",
        role: "core",
        fields: [
          {name: "_tokenId", type: "uint256", placeholder: "token id"},
          {name: "_to", type: "address", placeholder: "0x… allowed recipient"},
          {name: "_allowedTransferTimeInSeconds", type: "uint256", placeholder: "e.g. 86400 (24h)"},
        ],
        note: "While controlled transfers are on, a member-held token can only move to this recipient before the window expires. Single-use: it is cleared once the token moves.",
      },
      {
        fn: "revokeTransfer",
        label: "Revoke a transfer approval",
        role: "core",
        fields: [{name: "_tokenId", type: "uint256", placeholder: "token id"}],
        note: "Cancels a live approval early (e.g. one granted to the wrong address) so a corrected one can be issued.",
      },
    ],
  },
  {
    title: "Member · Move my seat",
    role: "any",
    blurb: "What a holder does after core approved a move. Use it to test the controlled-transfer gate.",
    items: [
      {
        fn: "transferFrom",
        label: "Transfer a seat",
        role: "any",
        fields: [
          {name: "_from", type: "address", placeholder: "0x… current holder (your address)"},
          {name: "_to", type: "address", placeholder: "0x… approved recipient"},
          {name: "_tokenId", type: "uint256", placeholder: "token id"},
        ],
        note: "With controlled transfers on, this only succeeds to the approved recipient before the approval expires.",
      },
    ],
  },
  {
    title: "Treasury",
    role: "treasury",
    blurb: "Call from the treasury address.",
    items: [{fn: "burn", label: "Burn token", role: "treasury", fields: [{name: "_tokenId", type: "uint256", placeholder: "token id"}], danger: true}],
  },
];
