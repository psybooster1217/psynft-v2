// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

/**
 * @title  CutoverCalls
 * @notice Single source of truth for every Main Safe transaction in the cutover
 *         (docs/DEPLOYMENT_RUNBOOK.md §0b, §1, §4c, §4d).
 *
 *         The SAME bytes are (a) executed through the real Main Safe — real owners, real
 *         threshold, MultiSendCallOnly — by test/SafeRehearsal.fork.t.sol against live mainnet
 *         state, and (b) written as Safe Transaction Builder files by script/SafeBatches.s.sol.
 *         Signers therefore sign exactly what was rehearsed, and can compare the safeTxHash
 *         printed by the script with the hash shown on their hardware wallet.
 */
library CutoverCalls {
    // ---------------------------------------------------------------- mainnet addresses
    address internal constant MAIN_SAFE = 0xB253a1Ab24B612C2AF37f8fC935b40c7304650e5; // 2-of-4, Safe v1.3.0
    address internal constant V1_TREASURY = 0xB4528213285CD10Fdb6a14847a398d71670b3d61;
    address internal constant V1_CORE = 0xDAAAC6a81fE6a230B880b96a2B5ca903d0c1d4F6; // CoreLogic (UUPS proxy)
    /// Current EOA owner of CoreLogic AND PsycSale (both handed over by V1_NFT_OWNER on 2025-12-12).
    address internal constant V1_CORE_OWNER = 0x00c15f6db575ef6ef7814d4900507eC4B3276061;
    address internal constant V1_NFT = 0x6c6Ab7b3215374dE4A65De63eAC9BC7A0c7f402d; // V1 PsyNFT (Ownable2Step)
    /// Current EOA owner of V1 PsyNFT: a former operator wallet, not the DAO (audit 2026-10 addendum, B1).
    address internal constant V1_NFT_OWNER = 0xC3aC5Ef1A15c40241233C722FE322D83B010e445;
    address internal constant PSYC_SALE = 0xe94828A923538709c58764159D6CD99C4381d82B; // V1 PsycSale (UUPS, Ownable2Step)
    /// Canonical Safe v1.3.0 deployments (verified against safe-global/safe-deployments, 2026-10-10).
    address internal constant SAFE_FALLBACK_HANDLER = 0xf48f2B2d2a534e402487b3ee7C18c33Aec0Fe5e4;
    address internal constant MULTISEND_CALL_ONLY = 0x40A2aCCbd92BCA938b02010E17A5b8929b49130D;

    struct Call {
        address to;
        bytes data;
        string label;
    }

    /// A transaction sent by an individual wallet (not the Safe) before the Safe batches.
    struct Handover {
        address from;
        address to;
        bytes data;
        string label;
    }

    // ---------------------------------------------------------------- step 0 (individual wallets)

    /// Step 0 — the three V1 contracts are owned by two individual wallets. Each starts a two-step
    /// (Ownable2Step) handover to the Main Safe; nothing changes until the Safe accepts (§0a/§0b).
    function eoaHandovers() internal pure returns (Handover[] memory h) {
        bytes memory toSafe = abi.encodeWithSignature("transferOwnership(address)", MAIN_SAFE);
        h = new Handover[](3);
        h[0] = Handover(V1_NFT_OWNER, V1_NFT, toSafe, "V1 PsyNFT.transferOwnership(MainSafe)");
        h[1] = Handover(V1_CORE_OWNER, V1_CORE, toSafe, "CoreLogic.transferOwnership(MainSafe)");
        h[2] = Handover(V1_CORE_OWNER, PSYC_SALE, toSafe, "PsycSale.transferOwnership(MainSafe)");
    }

    /// Calldata of every step-0 handover (identical for all three contracts).
    function coreLogicHandoverCalldata() internal pure returns (bytes memory) {
        return abi.encodeWithSignature("transferOwnership(address)", MAIN_SAFE);
    }

    // ---------------------------------------------------------------- batches

    /// §0a — the Safe accepts V1 PsyNFT. Separate from §0b because it depends on a different wallet
    /// (V1_NFT_OWNER) having started its handover; run it as soon as that has happened.
    function v1NftOwnerBatch() internal pure returns (Call[] memory c) {
        c = new Call[](1);
        c[0] = Call(V1_NFT, abi.encodeWithSignature("acceptOwnership()"), "V1 PsyNFT.acceptOwnership()");
    }

    /// §0b — run AFTER V1_CORE_OWNER has started the CoreLogic and PsycSale handovers.
    function setupBatch() internal pure returns (Call[] memory c) {
        c = new Call[](3);
        c[0] = Call(V1_CORE, abi.encodeWithSignature("acceptOwnership()"), "CoreLogic.acceptOwnership()");
        c[1] = Call(PSYC_SALE, abi.encodeWithSignature("acceptOwnership()"), "PsycSale.acceptOwnership()");
        c[2] = Call(
            MAIN_SAFE,
            abi.encodeWithSignature("setFallbackHandler(address)", SAFE_FALLBACK_HANDLER),
            "MainSafe.setFallbackHandler(CompatibilityFallbackHandler v1.3.0)"
        );
    }

    /// §1 — close the exit window. CAUTION: `switchRageQuit` TOGGLES. Execute exactly once, and only
    /// while `rageQuitAllowed() == true`; a second execution would re-open V1 ego death.
    function freezeBatch() internal pure returns (Call[] memory c) {
        c = new Call[](1);
        c[0] = Call(V1_CORE, abi.encodeWithSignature("switchRageQuit()"), "CoreLogic.switchRageQuit()  [toggle -> OFF]");
    }

    /// §4c — the Safe accepts ownership of the freshly migrated V2.
    function acceptV2Batch(address v2) internal pure returns (Call[] memory c) {
        c = new Call[](1);
        c[0] = Call(v2, abi.encodeWithSignature("acceptOwnership()"), "PsyNFTV2.acceptOwnership()");
    }

    /**
     * §4d — cutover + exit-pool sweep, one atomic batch. Preconditions (checked by the rehearsal):
     * V2.owner == V2.core == MAIN_SAFE, V2.treasury == V1_TREASURY, V2.tokenId == sweepId,
     * V2.totalTokensBurnt == 0, Safe fallback handler set, V1 ego death off.
     *
     * Step 5 passes n = 1, so Treasury pays rageQuitBalance / (1 - 0) = the whole pool.
     * Step 8 (audit 2026-10, OPS-02) points V1 CoreLogic at V2: CoreLogic is V1 PsyNFT's minter,
     * so without this the Safe could still mint and sell new V1 seats after cutover. Afterwards
     * CoreLogic's mint/approve/kick paths call V2, where CoreLogic has no role, and revert.
     * Re-enabling V1 would take a deliberate Safe transaction (the Safe owns V1 after §0a).
     */
    function cutoverBatch(address v2, uint256 sweepId) internal pure returns (Call[] memory c) {
        uint256[] memory one = new uint256[](1);
        one[0] = sweepId;
        c = new Call[](8);
        c[0] = Call(V1_TREASURY, abi.encodeWithSignature("updatePsyNftContract(address)", v2), "V1Treasury.updatePsyNftContract(V2)");
        c[1] = Call(V1_TREASURY, abi.encodeWithSignature("setCoreContract(address)", MAIN_SAFE), "V1Treasury.setCoreContract(MainSafe)");
        c[2] = Call(v2, abi.encodeWithSignature("batchMintInFibonacci()"), "PsyNFTV2.batchMintInFibonacci()  [ids 34-54]");
        c[3] = Call(v2, abi.encodeWithSignature("transferNFTs(uint256[],address)", one, MAIN_SAFE), "PsyNFTV2.transferNFTs([34], MainSafe)");
        c[4] = Call(
            V1_TREASURY,
            abi.encodeWithSignature("exit(uint256,uint256,address)", sweepId, uint256(1), MAIN_SAFE),
            "V1Treasury.exit(34, 1, MainSafe)  [whole pool]"
        );
        c[5] = Call(V1_TREASURY, abi.encodeWithSignature("withdrawUserFunds()"), "V1Treasury.withdrawUserFunds()  [pool -> Safe]");
        c[6] = Call(v2, abi.encodeWithSignature("setTreasury(address)", MAIN_SAFE), "PsyNFTV2.setTreasury(MainSafe)");
        c[7] = Call(V1_CORE, abi.encodeWithSignature("updatePsyNftAddress(address)", v2), "CoreLogic.updatePsyNftAddress(V2)  [V1 minting off]");
    }

    // ---------------------------------------------------------------- Safe encoding

    /// MultiSendCallOnly payload: every entry is a CALL (operation 0) with value 0.
    function multiSendData(Call[] memory c) internal pure returns (bytes memory packed) {
        for (uint256 i; i < c.length; i++) {
            packed = abi.encodePacked(packed, uint8(0), c[i].to, uint256(0), c[i].data.length, c[i].data);
        }
        return abi.encodeWithSignature("multiSend(bytes)", packed);
    }

    /// What the Safe executes for a batch: single calls go direct (operation 0); batches go through
    /// MultiSendCallOnly via DELEGATECALL (operation 1), exactly like the Transaction Builder.
    function safeTxFor(Call[] memory c) internal pure returns (address to, bytes memory data, uint8 operation) {
        if (c.length == 1) return (c[0].to, c[0].data, 0);
        return (MULTISEND_CALL_ONLY, multiSendData(c), 1);
    }

    /// EIP-712 safeTxHash for Safe v1.3.0 (no gas refund: safeTxGas/baseGas/gasPrice = 0).
    function safeTxHash(address safe, uint256 chainId, address to, bytes memory data, uint8 operation, uint256 nonce)
        internal
        pure
        returns (bytes32)
    {
        bytes32 domain = keccak256(
            abi.encode(keccak256("EIP712Domain(uint256 chainId,address verifyingContract)"), chainId, safe)
        );
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256(
                    "SafeTx(address to,uint256 value,bytes data,uint8 operation,uint256 safeTxGas,uint256 baseGas,uint256 gasPrice,address gasToken,address refundReceiver,uint256 nonce)"
                ),
                to,
                uint256(0),
                keccak256(data),
                operation,
                uint256(0),
                uint256(0),
                uint256(0),
                address(0),
                address(0),
                nonce
            )
        );
        return keccak256(abi.encodePacked(bytes1(0x19), bytes1(0x01), domain, structHash));
    }
}
