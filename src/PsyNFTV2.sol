// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/interfaces/IERC4906.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title  PsyNFTV2
 * @notice Governance / treasury NFT for PsyDAO. This is a hardened redeployment of the
 *         original `PsyNFT` (0x6c6Ab7b3215374dE4A65De63eAC9BC7A0c7f402d) whose `owner`
 *         key is no longer reachable, which permanently blocked all administrative
 *         controls (`setCoreContract`, `setTreasury`, `setBaseUri`, transfer toggles).
 *
 *         Behaviour is preserved versus V1 except for these additions (see
 *         docs/CHANGES_FROM_V1.md for the full list and rationale):
 *           1. A parameterised `initialOwner` so a Gnosis Safe can own the contract from
 *              block 0 (V1 hard-coded `Ownable(msg.sender)`).
 *           2. An owner-gated, one-shot **migration** path (`migrateBatch` +
 *              `finalizeMigration`) that re-mints the 33 existing V1 tokens to their
 *              current holders, preserving token IDs, and then resumes the exact
 *              Fibonacci mint schedule where V1 left off.
 *           3. Events on every state-changing admin action (V1 emitted none), plus ERC-4906
 *              metadata-refresh events so marketplaces pick up a new `baseUri`.
 *           4. Owner `rescue*` helpers for assets accidentally sent to the contract.
 *           5. `renounceOwnership` is disabled (the V1 failure mode, made impossible).
 *           6. Transfer approvals are single-use (cleared whenever the token moves or burns)
 *              and `core` can revoke one early (audit 2026-10, PNFT-01/02).
 *           7. Input guards on irreversible/owner-typed values: `finalizeMigration` only accepts
 *              consecutive Fibonacci counters and `setBaseUri` requires a trailing "/"
 *              (audit 2026-10, PNFT-03/04).
 *
 *         The distribution model is unchanged: new tokens are minted to the contract
 *         itself and handed out by the `core` contract; `treasury` may burn; member-held
 *         tokens are non-transferable unless `core` grants a time-boxed `approveTransfer`
 *         while `controlledTransfers` is enabled.
 *
 * @dev    Compiler/settings match V1 for parity: solc 0.8.20, EVM `paris`, OZ v5.
 */
contract PsyNFTV2 is IERC4906, ERC721, Ownable2Step, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @dev ERC-4906 interface id (metadata update events).
    bytes4 private constant ERC4906_INTERFACE_ID = bytes4(0x49064906);

    struct ApprovedTransfers {
        uint256 tokenId;
        uint256 transferExpiryDate;
        address to;
    }

    // --------------------------------------------------------------------- //
    //                          Storage (V1 parity)                          //
    // --------------------------------------------------------------------- //

    /// @notice Next token id to be minted by the Fibonacci schedule / initial mint.
    uint256 public tokenId;
    /// @notice Previous Fibonacci term; drives the size of the next batch.
    uint256 public previousFibonacci;
    /// @notice Running count of burnt tokens (informational).
    uint256 public totalTokensBurnt;

    /// @notice The PsyDAO Core contract permitted to mint/distribute/approve transfers.
    address public core;
    /// @notice The treasury address permitted to burn.
    address public treasury;

    /// @notice True once the initial 3-token mint (or migration finalize) has run.
    bool public initialMintCalled;
    /// @notice When true, member-held tokens require a `core`-granted approval to move.
    bool public controlledTransfers;

    /// @notice Base URI for token metadata.
    string public baseUri;

    /// @notice Per-token transfer approvals granted by `core`.
    mapping(uint256 => ApprovedTransfers) public approvedTransfers;

    // --------------------------------------------------------------------- //
    //                        Storage (V2 additions)                         //
    // --------------------------------------------------------------------- //

    /// @notice True after the first `migrateBatch` call; blocks the fresh `initialMint`.
    bool public migrationStarted;
    /// @notice True after `finalizeMigration`; permanently locks the migration path.
    bool public migrationFinalized;
    /// @notice Number of tokens minted via `migrateBatch` so far (completeness guard).
    uint256 public migratedCount;
    /// @dev Highest migrated tokenId + 1; `finalizeMigration` cannot set `tokenId` below this.
    uint256 private _migrationCeiling;

    // --------------------------------------------------------------------- //
    //                                Events                                 //
    // --------------------------------------------------------------------- //

    event CoreUpdated(address indexed previousCore, address indexed newCore);
    event TreasuryUpdated(address indexed previousTreasury, address indexed newTreasury);
    event BaseUriUpdated(string newBaseUri);
    event ControlledTransfersSet(bool enabled);
    event TransferApproved(uint256 indexed tokenId, address indexed to, uint256 expiry);
    event TransferApprovalRevoked(uint256 indexed tokenId);
    event TokenBurnt(uint256 indexed tokenId, address indexed from);
    event Migrated(uint256 indexed tokenId, address indexed to);
    event MigrationFinalized(uint256 nextTokenId, uint256 previousFibonacci, bool controlledTransfers);
    event ERC20Rescued(address indexed token, address indexed to, uint256 amount);
    event ERC721Rescued(address indexed token, address indexed to, uint256 tokenId);
    event ETHRescued(address indexed to, uint256 amount);

    // --------------------------------------------------------------------- //
    //                              Constructor                              //
    // --------------------------------------------------------------------- //

    /**
     * @param initialOwner The initial owner (pass the deployer to script migration, then
     *        `transferOwnership` to the Gnosis Safe; or pass the Safe directly).
     */
    constructor(address initialOwner) ERC721("PsyNFT", "PSY") Ownable(initialOwner) {
        controlledTransfers = true;
        previousFibonacci = 2;
    }

    // --------------------------------------------------------------------- //
    //                       Migration path (V2, one-shot)                   //
    // --------------------------------------------------------------------- //

    modifier notFinalized() {
        require(!migrationFinalized, "PsyNFT: Migration Finalized");
        _;
    }

    /**
     * @notice Re-mints a batch of snapshotted V1 tokens to their current holders.
     * @dev Owner-only. May be called repeatedly (chunking) until `finalizeMigration`.
     *      Uses `_mint` (not `_safeMint`) so tokens whose current holder is a contract
     *      (e.g. a Gnosis Safe or the V1 core) migrate without an `onERC721Received`
     *      check — every recipient already custodied the equivalent V1 token the same
     *      way. `_mint` reverts on a duplicate id, guarding against double-migration.
     * @param holders  Current owners, in the same order as `tokenIds`.
     * @param tokenIds Original V1 token ids to reproduce exactly. Any V1 token that was
     *      burnt is simply omitted; any token still held by the V1 contract itself should
     *      be passed with `holders[i]` = this contract's address so `core` can re-distribute.
     */
    function migrateBatch(address[] calldata holders, uint256[] calldata tokenIds)
        external
        onlyOwner
        notFinalized
        nonReentrant
    {
        require(!initialMintCalled, "PsyNFT: Initial Mint Done");
        require(holders.length == tokenIds.length, "PsyNFT: Length Mismatch");
        require(holders.length != 0, "PsyNFT: Empty Batch");

        migrationStarted = true;

        for (uint256 i; i < holders.length; i++) {
            address to = holders[i];
            require(to != address(0), "PsyNFT: Zero Holder");

            uint256 id = tokenIds[i];
            _mint(to, id); // reverts if `id` already exists -> no double mint
            migratedCount++;

            if (id + 1 > _migrationCeiling) {
                _migrationCeiling = id + 1;
            }
            emit Migrated(id, to);
        }
    }

    /**
     * @notice Closes the migration, restores the mint counters, and resumes the schedule.
     * @dev Owner-only, one-shot. After this call `migrateBatch` is permanently disabled and
     *      `batchMintInFibonacci` continues from `nextTokenId`. Because the lock is irreversible,
     *      the caller MUST declare `expectedCount` (the authoritative number of live V1 tokens,
     *      independent of the snapshot file) and the call reverts unless exactly that many tokens
     *      were migrated. This makes a truncated/short migration fail loudly instead of silently
     *      stranding an omitted holder with no recovery path.
     * @param nextTokenId        The V1 `tokenId` counter to resume from (V1 value: 34).
     *                           Must be >= the highest migrated id + 1.
     * @param previousFibonacci_ The V1 `previousFibonacci` to resume from (V1 value: 21).
     *                           Must be the Fibonacci term directly before `nextTokenId`
     *                           (the schedule only ever produces such pairs: 2/3, 3/5 … 21/34).
     * @param controlledTransfers_ Whether member transfers stay restricted (V1 value: true).
     * @param expectedCount      Authoritative live-token count (V1 `tokenId - totalTokensBurnt`,
     *                           i.e. 33). Must equal `migratedCount` or the call reverts.
     */
    function finalizeMigration(
        uint256 nextTokenId,
        uint256 previousFibonacci_,
        bool controlledTransfers_,
        uint256 expectedCount
    ) external onlyOwner notFinalized {
        require(migrationStarted, "PsyNFT: Migration Not Started");
        require(migratedCount == expectedCount, "PsyNFT: Incomplete Migration");
        require(nextTokenId >= _migrationCeiling, "PsyNFT: nextTokenId Too Low");
        require(_isFibonacciPair(previousFibonacci_, nextTokenId), "PsyNFT: Counters Not On Schedule");

        tokenId = nextTokenId;
        previousFibonacci = previousFibonacci_;
        controlledTransfers = controlledTransfers_;
        initialMintCalled = true; // resume schedule, block fresh initialMint
        migrationFinalized = true; // lock migration

        emit MigrationFinalized(nextTokenId, previousFibonacci_, controlledTransfers_);
    }

    // --------------------------------------------------------------------- //
    //                        Minting (V1 parity)                            //
    // --------------------------------------------------------------------- //

    /**
     * @notice Initializes a *fresh* deployment by minting the initial 3 tokens.
     * @dev Only `core` may call, and only once. Unavailable once a migration has started
     *      (a migrated deployment resumes via `finalizeMigration` instead).
     */
    function initialMint() external onlyCoreContract nonReentrant {
        require(!initialMintCalled, "PsyNFT: Initial Mint Complete");
        require(!migrationStarted, "PsyNFT: Migration In Progress");

        initialMintCalled = true;

        uint256 localTokenId = 0;

        while (localTokenId < 3) {
            _safeMint(address(this), localTokenId);
            localTokenId++;
        }

        tokenId = localTokenId;
    }

    /**
     * @notice Batch mints the next Fibonacci number of tokens to the contract.
     * @dev Only `core` may call. Requires the initial mint (or migration finalize) to be done.
     */
    function batchMintInFibonacci() external onlyCoreContract nonReentrant {
        require(initialMintCalled, "PsyNFT: Initial Mint Not Completed");

        uint256 batchAmount = previousFibonacci;
        previousFibonacci = tokenId;

        while (batchAmount > 0) {
            _safeMint(address(this), tokenId);
            tokenId++;
            batchAmount--;
        }
    }

    // --------------------------------------------------------------------- //
    //                    Distribution & transfers (V1 parity)               //
    // --------------------------------------------------------------------- //

    /**
     * @notice Transfers multiple contract-held NFTs to a recipient.
     * @dev Only `core` may call.
     */
    function transferNFTs(uint256[] memory _tokenIds, address _recipient) external onlyCoreContract {
        require(_recipient != address(0), "PsyNFT: Recipient Cannot Be Zero Address");
        require(_tokenIds.length != 0, "PsyNFT: Token Array Empty");
        for (uint256 x; x < _tokenIds.length; x++) {
            _safeTransfer(address(this), _recipient, _tokenIds[x]);
        }
    }

    /**
     * @notice Grants a time-boxed transfer approval for a member-held token.
     * @dev Only `core` may call. `_to` may be any address (approving address(0) is invalid
     *      as an ERC721 destination but the field is used only for the controlled-transfer check).
     */
    function approveTransfer(uint256 _tokenId, address _to, uint256 _allowedTransferTimeInSeconds)
        external
        onlyCoreContract
    {
        require(_tokenId < tokenId, "PsyNFT: Non Existent Token");
        require(
            block.timestamp > approvedTransfers[_tokenId].transferExpiryDate,
            "PsyNFT: Transfer Request Currently Active"
        );

        uint256 expiry = block.timestamp + _allowedTransferTimeInSeconds;
        approvedTransfers[_tokenId] = ApprovedTransfers({tokenId: _tokenId, transferExpiryDate: expiry, to: _to});

        emit TransferApproved(_tokenId, _to, expiry);
    }

    /**
     * @notice Cancels a transfer approval before it expires (e.g. one granted to a wrong address).
     * @dev Only `core` may call. V1 had no way to withdraw a live grant: a mistaken approval
     *      stayed usable, and blocked any corrected one, until it expired.
     */
    function revokeTransfer(uint256 _tokenId) external onlyCoreContract {
        require(approvedTransfers[_tokenId].transferExpiryDate != 0, "PsyNFT: No Approval To Revoke");
        delete approvedTransfers[_tokenId];
        emit TransferApprovalRevoked(_tokenId);
    }

    /**
     * @notice ERC721 transfer with the controlled-transfer gate.
     * @dev When `controlledTransfers` is on and the token is not held by the contract, the
     *      destination must match a live `approveTransfer` grant. Contract-held tokens
     *      (distributed by `core`) are never gated. Also governs `safeTransferFrom`, which
     *      routes through this function in OZ v5.
     */
    function transferFrom(address _from, address _to, uint256 _tokenId) public override(ERC721, IERC721) {
        if (controlledTransfers && ownerOf(_tokenId) != address(this)) {
            require(_to == approvedTransfers[_tokenId].to, "PsyNFT: Incorrect Receiver");
            require(block.timestamp <= approvedTransfers[_tokenId].transferExpiryDate, "PsyNFT: Approval Expired");
        }

        return super.transferFrom(_from, _to, _tokenId);
    }

    /**
     * @notice Burns a token. Only the treasury may call.
     */
    function burn(uint256 _tokenId) external {
        require(msg.sender == treasury, "PsyNFT: Caller Is Not Treasury");
        address from = ownerOf(_tokenId);
        totalTokensBurnt++;
        _burn(_tokenId);
        emit TokenBurnt(_tokenId, from);
    }

    // --------------------------------------------------------------------- //
    //                        Admin setters (V1 parity + events)             //
    // --------------------------------------------------------------------- //

    /// @notice Sets the Core contract. Owner-only, non-zero.
    function setCoreContract(address _core) external onlyOwner {
        require(_core != address(0), "PsyNFT: Core Cannot Be Zero Address");
        emit CoreUpdated(core, _core);
        core = _core;
    }

    /// @notice Sets the treasury. Owner-only, non-zero.
    function setTreasury(address _treasury) external onlyOwner {
        require(_treasury != address(0), "PsyNFT: Treasury Cannot Be Zero Address");
        emit TreasuryUpdated(treasury, _treasury);
        treasury = _treasury;
    }

    /// @notice Disables controlled transfers. Owner-only.
    function disableControlledTransfers() external onlyOwner {
        require(controlledTransfers, "PsyNFT: Controlled Transfers Already Disabled");
        controlledTransfers = false;
        emit ControlledTransfersSet(false);
    }

    /// @notice Enables controlled transfers. Owner-only.
    function enableControlledTransfers() external onlyOwner {
        require(!controlledTransfers, "PsyNFT: Controlled Transfers Already Enabled");
        controlledTransfers = true;
        emit ControlledTransfersSet(true);
    }

    /**
     * @notice Sets the metadata base URI. Owner-only.
     * @dev `tokenURI` is `baseUri + id`, so a non-empty URI must end with "/" or every token's
     *      metadata link breaks. Emits ERC-4906 `BatchMetadataUpdate` so marketplaces refresh art.
     */
    function setBaseUri(string memory _uri) external onlyOwner {
        bytes memory b = bytes(_uri);
        require(b.length == 0 || b[b.length - 1] == "/", "PsyNFT: Base URI Must End With Slash");
        baseUri = _uri;
        emit BaseUriUpdated(_uri);
        emit BatchMetadataUpdate(0, type(uint256).max);
    }

    /**
     * @notice Permanently disabled. V1 was bricked by an unreachable owner key; V2 makes
     *         ownership indestructible instead. Combined with Ownable2Step, ownership can
     *         only ever move to an address that actively accepts it — it can never be
     *         renounced into the void.
     */
    function renounceOwnership() public view override onlyOwner {
        revert("PsyNFT: Ownership Cannot Be Renounced");
    }

    // --------------------------------------------------------------------- //
    //                        Rescue helpers (V2 additions)                  //
    // --------------------------------------------------------------------- //

    /// @notice Rescues ERC20 tokens accidentally sent to this contract. Owner-only.
    function rescueERC20(address token, address to, uint256 amount) external onlyOwner nonReentrant {
        require(to != address(0), "PsyNFT: Rescue To Zero");
        IERC20(token).safeTransfer(to, amount);
        emit ERC20Rescued(token, to, amount);
    }

    /// @notice Rescues a *foreign* ERC721 sent to this contract. Cannot touch PsyNFT's own tokens.
    function rescueERC721(address token, address to, uint256 tokenId_) external onlyOwner nonReentrant {
        require(token != address(this), "PsyNFT: Cannot Rescue Self");
        require(to != address(0), "PsyNFT: Rescue To Zero");
        IERC721(token).transferFrom(address(this), to, tokenId_);
        emit ERC721Rescued(token, to, tokenId_);
    }

    /// @notice Rescues ETH force-sent to this contract. Owner-only.
    function rescueETH(address payable to, uint256 amount) external onlyOwner nonReentrant {
        require(to != address(0), "PsyNFT: Rescue To Zero");
        (bool ok,) = to.call{value: amount}("");
        require(ok, "PsyNFT: ETH Transfer Failed");
        emit ETHRescued(to, amount);
    }

    // --------------------------------------------------------------------- //
    //                              ERC721 plumbing                          //
    // --------------------------------------------------------------------- //

    /// @notice Lets the contract custody NFTs (it holds undistributed tokens).
    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }

    /// @notice ERC-165: ERC-721 (+ metadata) and ERC-4906.
    function supportsInterface(bytes4 interfaceId) public view override(ERC721, IERC165) returns (bool) {
        return interfaceId == ERC4906_INTERFACE_ID || super.supportsInterface(interfaceId);
    }

    /**
     * @dev Clears a token's transfer approval whenever the token changes hands or is burnt, so an
     *      approval is single-use and never carries over to a later owner (PNFT-01). Mints are
     *      skipped (no approval can exist for an unminted id) to keep batch-mint gas unchanged.
     *      Runs after the controlled-transfer check in `transferFrom` and before any
     *      `onERC721Received` callback.
     */
    function _update(address to, uint256 tokenId_, address auth) internal override returns (address from) {
        from = super._update(to, tokenId_, auth);
        if (from != address(0) && approvedTransfers[tokenId_].transferExpiryDate != 0) {
            delete approvedTransfers[tokenId_];
        }
    }

    function _baseURI() internal view override returns (string memory) {
        return baseUri;
    }

    /// @dev True iff (prev, next) are consecutive terms of the schedule's Fibonacci sequence
    ///      2, 3, 5, 8, 13, 21, 34, 55, … The loop is bounded by `next` (≤ ~370 steps for any uint).
    function _isFibonacciPair(uint256 prev, uint256 next) private pure returns (bool) {
        uint256 a = 2;
        uint256 b = 3;
        while (b < next) {
            (a, b) = (b, a + b);
        }
        return a == prev && b == next;
    }

    modifier onlyCoreContract() {
        require(msg.sender == core, "PsyNFT: Caller Not Core Contract");
        _;
    }
}
