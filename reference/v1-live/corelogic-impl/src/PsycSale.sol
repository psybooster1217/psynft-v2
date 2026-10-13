pragma solidity 0.8.20;

import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "openzeppelin-contracts/contracts/utils/cryptography/MerkleProof.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";

import "./PsyNFT.sol";
import "./NFTSublicences.sol";
import "./CoreLogic.sol";
import "./Treasury.sol";

contract PsycSale is
    Initializable,
    Ownable2StepUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable
{
    uint256 public saleBatchCount;
    uint256 public royalties;
    uint256 public numberOfNftsSold;

    uint8 public buyLimit;
    bool public privateSale;

    PsyNFT public psyNFT;
    CoreLogic public core;
    Treasury public treasury;
    NFTSublicences public sublicencesNft;
    RevenueSplit public revenueSplit;

    struct SaleBatch {
        uint256 startIndex;
        uint256 endIndex;
        uint256 floorPriceInEth;
        uint256 ceilingPriceInEth;
        uint256 saleStartTime;
        uint256 numberOfNftsSoldInBatch;
        bool paused;
    }

    struct RevenueSplit {
        uint256 psycFee;
        uint256 royalty;
        uint256 erc721OwnerPortion;
    }

    mapping(uint256 => SaleBatch) public saleBatches;
    mapping(address => uint256) public userPurchases;
    mapping(uint256 => bool) public tokenIDSold;
    mapping(uint256 => bytes32) public merkleRoots;
    mapping(uint256 => uint256) public tokenToBatchId;
    mapping(address => uint256) public userWithdrawalBalances;

    event SalesBatchCreated(
        uint256 batchID,
        uint256[] tokenIDs,
        uint256 floorPrice,
        uint256 ceilingPrice,
        uint256 saleStartTime,
        string ipfsHash
    );
    event FloorPriceChanged(uint256 batchID, uint256 newFloorPrice);
    event CeilingPriceChanged(uint256 batchID, uint256 newCeilingPrice);
    event BuyLimitChanged(uint8 newLimit);
    event TokenSold(uint256 batchID, uint256 tokenID, address to);
    event CoreAddressSet(address core);
    event MerkleUpdated(uint256 batchId, bytes32 oldMerkle, bytes32 newMerkle, string ipfsHash);
    event SalePermissionUpdated(bool permissionStatus);
    event PsyNFTAddressChanged(address psycSale);
    event TreasuryAddressChanged(address treasury);
    event SublicencesAddressChanged(address sublicences);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _psyNFT, address _sublicenceNft, address payable _treasury)
        external
        initializer
    {
        require(_psyNFT != address(0), "PsycSale: Cannot Be Zero Address");
        require(_sublicenceNft != address(0), "PsycSale: Cannot Be Zero Address");
        require(_treasury != address(0), "PsycSale: Cannot Be Zero Address");

        __Pausable_init();
        __Ownable2Step_init();
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();

        psyNFT = PsyNFT(_psyNFT);
        sublicencesNft = NFTSublicences(_sublicenceNft);
        treasury = Treasury(_treasury);
        buyLimit = 1;
        privateSale = true;
        revenueSplit.royalty = 2000;
        revenueSplit.erc721OwnerPortion = 7935;
        revenueSplit.psycFee = 65;
    }

    // --------------------------------------------------------------------------------------------------------------------
    // -----------------------------------------> ONLY CORE LOGIC CONTRACT FUNCTIONS <-------------------------------------------
    // --------------------------------------------------------------------------------------------------------------------

    /**
     * @notice Creates a batch of NFTs for sale.
     * @param _tokenIDs Token IDs to be included in batch.
     * @param _saleStartTime Start time of sale.
     * @param _floorPrice The price to pay purchasing a random NFT.
     * @param _ceilingPrice The price to pay for selected a specific NFT to purchase.
     * @param _merkleRoot Merkle Root for the specific batch.
     * @param _ipfsHash ipfs hash to be emitted in event for BE to know where the whitelisted addresses are being stored.
     */
    function createSaleBatch(
        uint256[] memory _tokenIDs,
        uint256 _saleStartTime,
        uint256 _floorPrice,
        uint256 _ceilingPrice,
        bytes32 _merkleRoot,
        string memory _ipfsHash
    ) external nonReentrant returns (uint256) {
        require(msg.sender == address(core), "PsycSale: Only CoreLogic Contract");
        require(_ceilingPrice >= _floorPrice, "PsycSale: Ceiling Price Below Floor");
        require(address(sublicencesNft.psycSale()) != address(0), "PsycSale: Sale Address Not Set In Sublicences NFT");

        unchecked {
            saleBatchCount++;
        }

        saleBatches[saleBatchCount] = SaleBatch({
            startIndex: _tokenIDs[0],
            endIndex: _tokenIDs[_tokenIDs.length - 1],
            floorPriceInEth: _floorPrice,
            ceilingPriceInEth: _ceilingPrice,
            saleStartTime: _saleStartTime,
            numberOfNftsSoldInBatch: 0,
            paused: false
        });

        for (uint256 x; x < _tokenIDs.length; x++) {
            tokenToBatchId[_tokenIDs[x]] = saleBatchCount;
            sublicencesNft.setNftPrices(_tokenIDs[x], _floorPrice, _ceilingPrice);
        }

        merkleRoots[saleBatchCount] = _merkleRoot;

        SaleBatch storage sale = saleBatches[saleBatchCount];

        emit SalesBatchCreated(
            saleBatchCount, _tokenIDs, sale.floorPriceInEth, sale.ceilingPriceInEth, sale.saleStartTime, _ipfsHash
        );

        return saleBatchCount;
    }

    // --------------------------------------------------------------------------------------------------------------------
    // --------------------------------------------> PUBLIC FUNCTIONS <----------------------------------------------------
    // --------------------------------------------------------------------------------------------------------------------

    /**
     * @notice Allows a whitelisted account to purchase from a specific tokenID from a batch paying the ceiling price of the token.
     * @param _batchID Id of batch to purchase from.
     * @param _tokenID Token Id to purchase.
     * @param _proof Merkle proof for the caller to prove they are on the whitelist for the specified batch.
     * @notice If sale is public, provide empty proof.
     */
    function buyFromBatch(uint256 _batchID, uint256 _tokenID, bytes32[] memory _proof)
        external
        payable
        nonReentrant
        whenNotPaused
        SaleStarted(_batchID)
        SaleNotPaused(_batchID)
        ValidBatch(_batchID)
        PurchaseLimit
    {
        require(!tokenIDSold[_tokenID], "PsycSale: Token Already Sold");
        require(tokenToBatchId[_tokenID] == _batchID, "PsycSale: Token Not In Batch");

        if (privateSale) {
            _checkWhitelisted(_batchID, _proof);
        }
        uint256 tokenValue = saleBatches[_batchID].ceilingPriceInEth;
        require(msg.value == tokenValue, "PsycSale: Incorrect Value");

        _processPurchase(_batchID, _tokenID, tokenValue);

        emit TokenSold(_batchID, _tokenID, msg.sender);
    }

    /**
     * @notice Allows a whitelisted account to purchase from a random tokenID from a batch paying the floor price of the token.
     * @dev random available token is selected.
     * @param _batchID Id of batch to purchase from.
     * @param _proof Merkle proof for the caller to prove they are on the whitelist for the specified batch.
     * @notice If sale is public, provide empty proof.
     */
    function buyRandomFromBatch(uint256 _batchID, bytes32[] memory _proof)
        external
        payable
        nonReentrant
        whenNotPaused
        SaleStarted(_batchID)
        SaleNotPaused(_batchID)
        ValidBatch(_batchID)
        PurchaseLimit
        returns (uint256)
    {
        SaleBatch memory sale = saleBatches[_batchID];

        if (privateSale) {
            _checkWhitelisted(_batchID, _proof);
        }

        uint256 tokenValue = sale.floorPriceInEth;
        require(msg.value == tokenValue, "PsycSale: Incorrect Value");

        require(
            sale.numberOfNftsSoldInBatch < ((sale.endIndex - sale.startIndex) + 1), "PsycSale: No Nfts Left In Batch"
        );
        uint256 randomTokenID = _getRandomOriginal(sale.startIndex, sale.endIndex);
        require(tokenToBatchId[randomTokenID] == _batchID, "PsycSale: Token Not In Batch");

        _processPurchase(_batchID, randomTokenID, tokenValue);

        emit TokenSold(_batchID, randomTokenID, msg.sender);

        return randomTokenID;
    }

    /**
     * @notice Allows an account to purchase a specific token copy from a specific tokenID from a batch paying the ceiling price of the token.
     * @param _batchId Id of batch to purchase from.
     * @param _erc721TokenId Token Id to purchase.
     */
    function buyNftCopyFromBatch(uint256 _batchId, uint256 _erc721TokenId)
        external
        payable
        whenNotPaused
        SaleStarted(_batchId)
        ValidBatch(_batchId)
    {
        require(tokenToBatchId[_erc721TokenId] == _batchId, "PsycSale: Token Not In Batch");

        (, uint256 ceilingPrice,) = sublicencesNft.tokenInformation(_erc721TokenId);
        require(msg.value == ceilingPrice, "PsycSale: Incorrect Value");

        sublicencesNft.mint(msg.sender, _erc721TokenId);
        _calculateFundDistribution(_erc721TokenId, ceilingPrice);
    }

    /**
     * @notice Allows an account to purchase a random token copy from a specific batch paying the floor price of the token.
     * @param _batchId Id of batch to purchase from.
     */
    function buyRandomNftCopyFromBatch(uint256 _batchId)
        external
        payable
        whenNotPaused
        SaleStarted(_batchId)
        ValidBatch(_batchId)
        returns (uint256)
    {
        uint256 randomTokenID = _getRandomCopy(saleBatches[_batchId].startIndex, saleBatches[_batchId].endIndex);
        require(tokenToBatchId[randomTokenID] == _batchId, "PsycSale: Token Not In Batch");

        (uint256 floorPrice,,) = sublicencesNft.tokenInformation(randomTokenID);
        require(msg.value == floorPrice, "PsycSale: Incorrect Value");

        sublicencesNft.mint(msg.sender, randomTokenID);
        _calculateFundDistribution(randomTokenID, floorPrice);

        return randomTokenID;
    }

    /**
     * @notice Allows an account to withdraw their profits as an NFT owner.
     * @notice Profits built up through sales of copies.
     */
    function withdrawProfitsAsNftOwner() external {
        uint256 amount = userWithdrawalBalances[msg.sender];
        userWithdrawalBalances[msg.sender] = 0;

        (bool sent,) = msg.sender.call{value: amount}("");
        require(sent, "Failed to send Ether");
    }

    // --------------------------------------------------------------------------------------------------------------------
    // ----------------------------------------> ONLY CONTRACT OWNER FUNCTIONS <-------------------------------------------
    // --------------------------------------------------------------------------------------------------------------------

    /**
     * @notice Sets the address of the CoreLogic contract.
     * @param _core The address of CoreLogic contract.
     */
    function setCoreContract(address _core) external onlyOwner {
        require(_core != address(0), "PsycSale: Cannot Be Zero Address");

        core = CoreLogic(_core);

        emit CoreAddressSet(_core);
    }

    /**
     * @notice Updates the address of the PsyNFT contract.
     * @param _newPsyNftAddress The new address of the PsyNFT contract.
     */
    function updatePsyNftAddress(address _newPsyNftAddress) external onlyOwner {
        require(_newPsyNftAddress != address(0), "PsycSale: Cannot Be Zero Address");
        psyNFT = PsyNFT(_newPsyNftAddress);

        emit PsyNFTAddressChanged(_newPsyNftAddress);
    }

    /**
     * @notice Updates the address of the Treasury contract.
     * @param _newTreasuryAddress The new address of the Treasury contract.
     */
    function updateTreasuryAddress(address _newTreasuryAddress) external onlyOwner {
        require(_newTreasuryAddress != address(0), "PsycSale: Cannot Be Zero Address");
        treasury = Treasury(payable(_newTreasuryAddress));

        emit TreasuryAddressChanged(_newTreasuryAddress);
    }

    /**
     * @notice Updates the address of the Sublicences contract.
     * @param _newSublicencesAddress The new address of the Sublicences contract.
     */
    function updateSublicencesAddress(address _newSublicencesAddress) external onlyOwner {
        require(_newSublicencesAddress != address(0), "PsycSale: Cannot Be Zero Address");
        sublicencesNft = NFTSublicences(_newSublicencesAddress);

        emit SublicencesAddressChanged(_newSublicencesAddress);
    }

    /**
     * @notice Updates the merkle root for a specific batch
     * @dev merkleroot gets generated in JS offline and sent to the contract
     * @param _batchId Id of the batch to update the merkle root for
     * @param _newMerkle new merkle root to be used for buying a Psyc NFT
     * @param _ipfsHash ipfs hash to be emitted in event for BE to know where the whitelisted addresses are being stored.
     */
    function updateMerkleRoot(uint256 _batchId, bytes32 _newMerkle, string memory _ipfsHash) external onlyOwner {
        require(_batchId > 0, "PsycSale: Non-Existent Batch");

        bytes32 oldMerkle = merkleRoots[_batchId];
        merkleRoots[_batchId] = _newMerkle;

        emit MerkleUpdated(_batchId, oldMerkle, _newMerkle, _ipfsHash);
    }

    /**
     * @notice Changes the floor and ceiling price of a specific batch.
     * @param _batchID Id of batch to change the prices for.
     * @param _newFloorPrice New floor price.
     * @param _newCeilingPrice New ceiling price.
     * @dev The new ceiling price must be greater than the floor price.
     * @dev The new floor price must be greater than 0.
     */
    function changeFloorAndCeilingPriceOfBatch(uint256 _batchID, uint256 _newFloorPrice, uint256 _newCeilingPrice)
        external
        onlyOwner
    {
        require(_batchID > 0, "PsycSale: Non-Existent Batch");
        require(
            _newCeilingPrice > 0 && _newCeilingPrice > _newFloorPrice, "PsycSale: Invalid Ceiling Price"
        );
        require(_newFloorPrice > 0, "PsycSale: Invalid Floor Price");

        saleBatches[_batchID].floorPriceInEth = _newFloorPrice;
        saleBatches[_batchID].ceilingPriceInEth = _newCeilingPrice;

        emit FloorPriceChanged(_batchID, _newFloorPrice);
        emit CeilingPriceChanged(_batchID, _newCeilingPrice);
    }

    /**
     * @notice Changes the amount of NFTs an address can purchase.
     * @param _newLimit Limit amount.
     */
    function changeBuyLimit(uint8 _newLimit) external onlyOwner {
        require(_newLimit != buyLimit, "PsycSale: Limit Identical");
        require(_newLimit >= 1, "PsycSale: No Limit");

        buyLimit = _newLimit;

        emit BuyLimitChanged(_newLimit);
    }

    /**
     * @notice Switches the status of private or public sales.
     * @dev Only the contract owner can call this function.
     * @dev OWhen called, it will set sale status to opposite of current status.
     */
    function switchSaleType() external onlyOwner {
        privateSale = !privateSale;

        emit SalePermissionUpdated(privateSale);
    }

    /**
     * @notice Updates the revenue splits for the contract.
     * @param _royaltyPercentage The percentage of the sale that goes to the original NFT owner.
     * @param _ownerPercentage The percentage of the sale that goes to the ERC721 owner.
     * @param _fee The percentage of the sale that goes to the Psyc treasury.
     * @dev The sum of the three percentages must equal 10,000.
     */
    function updateRevenueSplits(uint256 _royaltyPercentage, uint256 _ownerPercentage, uint256 _fee)
        external
        onlyOwner
    {
        require(_royaltyPercentage + _ownerPercentage + _fee == 10_000, "PsycSale: Incorrect Percentages");

        revenueSplit.royalty = _royaltyPercentage;
        revenueSplit.erc721OwnerPortion = _ownerPercentage;
        revenueSplit.psycFee = _fee;
    }

    /**
     * @notice Pauses the contract.
     * @dev Only the contract owner can call this function.
     */
    function pause() external onlyOwner {
        _requireNotPaused();
        _pause();
    }

    /**
     * @notice Unpauses the contract.
     * @dev Only the contract owner can call this function.
     */
    function unpause() external onlyOwner {
        _requirePaused();
        _unpause();
    }

    /**
     * @notice Switches the status of a specific batch.
     * @param _batchId Id of the batch to switch the status for.
     */
    function switchBatchStatus(uint256 _batchId) external ValidBatch(_batchId) onlyOwner {
        saleBatches[_batchId].paused = !saleBatches[_batchId].paused;
    }

    /**
     * @notice Withdraws the contract's balance and sends it to the treasury.
     * @dev Only the contract owner can call this function.
     * @dev If the transfer fails, an error message is thrown.
     * @notice This function should be used with caution as it transfers the entire balance of the contract.
     */
    function withdrawRoyalties(address _receiver) external onlyOwner {
        require(_receiver != address(0), "PsycSale: Receiver Cannot Be Zero Address");

        uint256 amount = royalties;
        royalties = 0;

        (bool sent,) = _receiver.call{value: amount}("");
        require(sent, "Failed to send Ether");
    }

    /**
     * @notice Allows the contract owner to set the sale status for copies of the ERC721 / original of multiple tokens.
     * @param _tokenIds An array of token IDs to set the sale status for.
     * @dev Can only be called for ERC721s owned by the contract.
     */
    function setSalesActive(uint256[] memory _tokenIds) external onlyOwner {
        for (uint256 x; x < _tokenIds.length; x++) {
            sublicencesNft.switchSaleStatus(_tokenIds[x]);
        }
    }

    // --------------------------------------------------------------------------------------------------------------------
    // ----------------------------------------------> INTERNAL FUNCTIONS <------------------------------------------------
    // --------------------------------------------------------------------------------------------------------------------

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /// @notice Allows contract to receive NFTs
    /// @dev Returns the valid selector to the ERC721 contract to prove contract can hold NFTs
    function onERC721Received(address, address, uint256 _tokenId, bytes calldata) external pure returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }

    function _processPurchase(uint256 _batchId, uint256 _tokenId, uint256 _amountPaid) internal {
        userPurchases[msg.sender]++;
        tokenIDSold[_tokenId] = true;
        numberOfNftsSold++;
        saleBatches[_batchId].numberOfNftsSoldInBatch++;

        core.approveNftTransfer(_tokenId, msg.sender, 400);
        psyNFT.approve(msg.sender, _tokenId);
        psyNFT.transferFrom(address(this), msg.sender, _tokenId);

        uint256 royaltyAmount = _amountPaid * revenueSplit.royalty / 10_000;
        uint256 psycAmount = _amountPaid - royaltyAmount;

        treasury.receiveRageQuitProfit{value: psycAmount}();
        royalties += royaltyAmount;
    }
    
    // Gets a random NFT for a batch for an original NFT to be minted
    function _getRandomOriginal(uint256 _startIndex, uint256 _endIndex) internal view returns (uint256 tokenId) {
        uint256 randomIndex = uint256(keccak256(abi.encodePacked(block.timestamp, block.prevrandao, msg.sender)))
            % (_endIndex - _startIndex + 1);

        tokenId = _startIndex + randomIndex;

        for (uint256 i = 0; i < _endIndex - _startIndex + 1; i++) {
            if (!tokenIDSold[tokenId]) {
                return tokenId;
            }
            if (tokenId == _endIndex) {
                tokenId = _startIndex;
            } else {
                tokenId++;
            }
        }

        return tokenId;
    }

    // Gets a random NFT for a batch for a sublicence / copy NFT to be minted
    function _getRandomCopy(uint256 _startIndex, uint256 _endIndex) internal view returns (uint256 tokenId) {
        uint256 randomIndex = uint256(keccak256(abi.encodePacked(block.timestamp, block.prevrandao, msg.sender)))
            % (_endIndex - _startIndex + 1);

        tokenId = _startIndex + randomIndex;

        for (uint256 i = 0; i < _endIndex - _startIndex + 1; i++) {
            (,, bool active) = sublicencesNft.tokenInformation(tokenId);
            if (active && (psyNFT.ownerOf(tokenId) != address(0))) {
                return tokenId;
            }
            if (tokenId == _endIndex) {
                tokenId = _startIndex;
            } else {
                tokenId++;
            }
        }

        return tokenId;
    }

    function _calculateFundDistribution(uint256 _token, uint256 _amountPaid) internal {
        if (psyNFT.ownerOf(_token) == address(this)) {
            uint256 royaltyAmount = _amountPaid * revenueSplit.royalty / 10_000;
            uint256 psycAmount = _amountPaid - royaltyAmount;

            treasury.receiveRageQuitProfit{value: psycAmount}();

            royalties += royaltyAmount;
        } else {
            uint256 royaltyAmount = _amountPaid * revenueSplit.royalty / 10_000;
            uint256 psycAmount = _amountPaid * revenueSplit.psycFee / 10_000;
            uint256 ownerAmount = _amountPaid * revenueSplit.erc721OwnerPortion / 10_000;

            treasury.receiveRageQuitProfit{value: psycAmount}();

            userWithdrawalBalances[psyNFT.ownerOf(_token)] += ownerAmount;
            royalties += royaltyAmount;
        }
    }

    function _checkWhitelisted(uint256 _batchId, bytes32[] memory _proof) internal view {
        require(_proof.length != 0, "PsycSale: No Proof Provided");
        require(
            MerkleProof.verify(_proof, merkleRoots[_batchId], keccak256(abi.encodePacked(msg.sender))),
            "PsycSale: Not Whitelisted"
        );
    }

    // --------------------------------------------------------------------------------------------------------------------
    // ---------------------------------------------------> MODIFIERS <----------------------------------------------------
    // --------------------------------------------------------------------------------------------------------------------

    modifier SaleStarted(uint256 _batchId) {
        require(block.timestamp >= saleBatches[_batchId].saleStartTime, "PsycSale: Sale Has Not Started");
        _;
    }

    modifier ValidBatch(uint256 _batchId) {
        require(_batchId > 0, "PsycSale: Cannot Be Batch Zero");
        _;
    }

    modifier PurchaseLimit() {
        require(userPurchases[msg.sender] < buyLimit, "PsycSale: Purchase Limit Reached");
        _;
    }

    modifier SaleNotPaused(uint256 _batchId) {
        require(!saleBatches[_batchId].paused, "PsycSale: Sale Paused");
        _;
    }
}
