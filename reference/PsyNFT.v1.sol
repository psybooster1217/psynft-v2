// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "openzeppelin-contracts/contracts/token/ERC721/ERC721.sol";
import "openzeppelin-contracts/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract PsyNFT is ERC721, Ownable2Step, ReentrancyGuard {
    struct ApprovedTransfers {
        uint256 tokenId;
        uint256 transferExpiryDate;
        address to;
    }

    uint256 public tokenId;
    uint256 public previousFibonacci;
    uint256 public totalTokensBurnt;

    address public core;
    address public treasury;

    bool public initialMintCalled;
    bool public controlledTransfers;

    string public baseUri;

    mapping(uint256 => ApprovedTransfers) public approvedTransfers;

    constructor() ERC721("PsyNFT", "PSY") Ownable(msg.sender) {
        controlledTransfers = true;
        previousFibonacci = 2;
    }

    /**
     * @notice Initializes the contract by minting the initial tokens.
     * @dev Only the contract owner can call this function.
     * @dev This function can only be called once.
     */
    function initialMint() external onlyCoreContract nonReentrant {
        require(!initialMintCalled, "PsyNFT: Initial Mint Complete");

        initialMintCalled = true;

        uint256 localTokenId = 0;

        while (localTokenId < 3) {
            _safeMint(address(this), localTokenId);
            localTokenId++;
        }

        tokenId = localTokenId;
    }

    /**
     * @notice Batch mints a specified number of tokens in a Fibonacci sequence.
     * @dev Only the core contract can call this function.
     * @dev Requires that the initial mint has been completed.
     * @dev The number of tokens to be minted is determined by the previous Fibonacci number.
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

    /**
     * @notice Transfers multiple NFTs to a specified recipient.
     * @dev Only the core contract can call this function.
     * @param _tokenIds An array of token IDs to be transferred.
     * @param _recipient The address of the recipient.
     */
    function transferNFTs(uint256[] memory _tokenIds, address _recipient) external onlyCoreContract {
        require(_recipient != address(0), "PsyNFT: Recipient Cannot Be Zero Address");
        require(_tokenIds.length != 0, "PsyNFT: Token Array Empty");
        for (uint256 x; x < _tokenIds.length; x++) {
            _safeTransfer(address(this), _recipient, _tokenIds[x]);
        }
    }

    /**
     * @notice Approves the transfer of a PsyNFT token to a specified recipient.
     * @dev Only the core contract can call this function.
     * @dev Cann approve address(0) for the purpose of burning.
     * @param _tokenId The ID of the PsyNFT token to be transferred.
     * @param _to The address of the recipient.
     * @param _allowedTransferTimeInSeconds The duration in seconds for which the transfer is allowed.
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

        approvedTransfers[_tokenId] = ApprovedTransfers({
            tokenId: _tokenId,
            transferExpiryDate: block.timestamp + _allowedTransferTimeInSeconds,
            to: _to
        });
    }

    /**
     * @notice Sets the address of the Core contract.
     * @dev Only the contract owner can call this function.
     * @param _core The address of the Core contract.
     * @dev The address cannot be the zero address.
     */
    function setCoreContract(address _core) external onlyOwner {
        require(_core != address(0), "PsyNFT: Core Cannot Be Zero Address");
        core = _core;
    }

    /**
     * @notice Disables controlled transfers of PsyNFT tokens.
     * @dev Only the contract owner can call this function.
     * @dev Requires that controlled transfers are currently enabled.
     */
    function disableControlledTransfers() external onlyOwner {
        require(controlledTransfers, "PsyNFT: Controlled Transfers Already Disabled");
        controlledTransfers = false;
    }

    /**
     * @notice Enables controlled transfers of PsyNFT tokens.
     * @dev Only the contract owner can call this function.
     * @dev Requires that controlled transfers are currently disabled.
     */
    function enableControlledTransfers() external onlyOwner {
        require(!controlledTransfers, "PsyNFT: Controlled Transfers Already Enabled");
        controlledTransfers = true;
    }

    /**
     * @notice Sets the address of the treasury.
     * @dev Only the contract owner can call this function.
     * @param _treasury The address of the treasury.
     */
    function setTreasury(address _treasury) external onlyOwner {
        require(_treasury != address(0), "PsyNFT: Treasury Cannot Be Zero Address");
        treasury = _treasury;
    }

    /**
     * @notice Transfers an NFT from one address to another.
     * @dev Overrides the transferFrom function in the ERC721 contract.
     * @param _from The address from which the NFT is being transferred.
     * @param _to The address to which the NFT is being transferred.
     * @param _tokenId The ID of the NFT being transferred.
     * @dev If the NFT is not owned by the contract, the transfer must be approved by the transfer request.
     * @dev The recipient address must match the address specified in the transfer request.
     * @dev The transfer request must not be expired.
     */
    function transferFrom(address _from, address _to, uint256 _tokenId) public override {
        if (controlledTransfers && ownerOf(_tokenId) != address(this)) {
            require(_to == approvedTransfers[_tokenId].to, "PsyNFT: Incorrect Receiver");
            require(block.timestamp <= approvedTransfers[_tokenId].transferExpiryDate, "PsyNFT: Approval Expired");
        }

        return super.transferFrom(_from, _to, _tokenId);
    }

    /**
     * @notice Burns a PsyNFT token.
     * @dev Only the treasury address can call this function.
     * @dev Psy admin must approve the transfer to address(0).
     * @param _tokenId The ID of the PsyNFT token to be burned.
     */
    function burn(uint256 _tokenId) external {
        require(msg.sender == treasury, "PsyNFT: Caller Is Not Treasury");
        totalTokensBurnt++;
        _burn(_tokenId);
    }

    /**
     * @notice Sets the base URI for the PsyNFT tokens.
     * @param _uri The new base URI for the tokens.
     */
    function setBaseUri(string memory _uri) external onlyOwner {
        baseUri = _uri;
    }

    /**
     * @notice Allows contract to receive NFTs
     * @dev Returns the valid selector to the ERC721 contract to prove contract can hold NFTs
     */
    function onERC721Received(address, address, uint256 _tokenId, bytes calldata) external returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }

    /**
     * @dev Returns the base URI for the PsyNFT tokens.
     * @return The base URI as a string.
     */
    function _baseURI() internal view override returns (string memory) {
        return baseUri;
    }

    modifier onlyCoreContract() {
        require(msg.sender == address(core), "PsyNFT: Caller Not Core Contract");
        _;
    }
}
