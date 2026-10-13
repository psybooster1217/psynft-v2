// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import "./PsyNFT.sol";
import "./NFTSublicences.sol";
import "./Treasury.sol";
import "./PsycSale.sol";

contract CoreLogic is Initializable, Ownable2StepUpgradeable, UUPSUpgradeable {
    PsyNFT public psyNFT;
    Treasury public treasury;
    PsycSale public psycSale;
    bool public rageQuitAllowed;

    event PsyNftAddressChanged(address psyNft);
    event TreasuryAddressChanged(address treasury);
    event RageQuitStatusChanged(bool newStatus);
    event TransferApproved(uint256 tokenId, address to, uint256 allowedTransferTimeInSeconds);
    event PsycSaleAddressChanged(address psycSale);


    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _psyNFT, 
        address _psycSale, 
        address _treasury
    ) external initializer {
        require(_psyNFT != address(0), "CoreLogic: Cannot Be Zero Address");
        require(_treasury != address(0), "CoreLogic: Cannot Be Zero Address");
        require(_psycSale != address(0), "CoreLogic: Cannot Be Zero Address");

        __Ownable2Step_init();
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();

        psyNFT = PsyNFT(_psyNFT);
        treasury = Treasury(payable(_treasury));
        psycSale = PsycSale(_psycSale);
        rageQuitAllowed = false;
    }

    // --------------------------------------------------------------------------------------------------------------------
    // -----------------------------------------> GENERAL ONLY OWNER FUNCTIONS <-------------------------------------------
    // --------------------------------------------------------------------------------------------------------------------

    /**
     * @notice Allows the contract owner to switch the rage quit functionality on or off.
     * @dev This function can only be called by the contract owner.
     */
    function switchRageQuit() external onlyOwner {
        rageQuitAllowed = !rageQuitAllowed;

        emit RageQuitStatusChanged(rageQuitAllowed);
    }

    /**
     * @notice Allows the contract owner to update the address of the PsyNFT contract.
     * @dev This function can only be called by the contract owner.
     * @param _newPsyNftAddress The new address of the PsyNFT contract.
     */
    function updatePsyNftAddress(address _newPsyNftAddress) external onlyOwner {
        require(_newPsyNftAddress != address(0), "CoreLogic: Cannot Be Zero Address");
        psyNFT = PsyNFT(_newPsyNftAddress);

        emit PsyNftAddressChanged(_newPsyNftAddress);
    }

    /**
     * @notice Allows the contract owner to update the address of the Treasury contract.
     * @dev This function can only be called by the contract owner.
     * @param _newTreasuryAddress The new address of the Treasury contract.
     */
    function updateTreasuryAddress(address _newTreasuryAddress) external onlyOwner {
        require(_newTreasuryAddress != address(0), "CoreLogic: Cannot Be Zero Address");
        treasury = Treasury(payable(_newTreasuryAddress));
        
        emit TreasuryAddressChanged(_newTreasuryAddress);
    }

    /**
     * @notice Allows the contract owner to update the address of the PsycSale contract.
     * @dev This function can only be called by the contract owner.
     * @param _newPsycSaleAddress The new address of the PsycSale contract.
     */
    function updatePsycSaleAddress(address _newPsycSaleAddress) external onlyOwner {
        require(_newPsycSaleAddress != address(0), "CoreLogic: Cannot Be Zero Address");
        psycSale = PsycSale(_newPsycSaleAddress);

        emit PsycSaleAddressChanged(_newPsycSaleAddress);
    }

    // --------------------------------------------------------------------------------------------------------------------
    // -----------------------------------------------> PSY NFT FUNCTIONS <------------------------------------------------
    // --------------------------------------------------------------------------------------------------------------------

    /**
     * @notice Mints the initial batch of Psy NFTs.
     * @dev This function can only be called by the contract owner.
     */
    function mintInitialBatch() external onlyOwner {
        psyNFT.initialMint();
    }

    /**
     * @notice Mints the next batch of Psy NFTs using the Fibonacci sequence.
     * @dev This function can only be called by the contract owner.
     */
    function mintNextBatch() external onlyOwner {
        psyNFT.batchMintInFibonacci();
    }

    /**
     * @notice Approves the transfer of a Psy NFT to a specified address.
     * @dev This function can only be called by the contract owner.
     * @param _tokenId The ID of the Psy NFT to be transferred.
     * @param _to The address to which the Psy NFT will be transferred.
     * @param _allowedTransferTimeInSeconds The allowed transfer time in seconds for the approved transfer.
     */
    function approveNftTransfer(uint256 _tokenId, address _to, uint256 _allowedTransferTimeInSeconds) external {
        require(msg.sender == owner() || msg.sender == address(psycSale), "CoreLogic: Invalid Permissions");
        psyNFT.approveTransfer(_tokenId, _to, _allowedTransferTimeInSeconds);

        emit TransferApproved(_tokenId, _to, _allowedTransferTimeInSeconds);
    }

    // --------------------------------------------------------------------------------------------------------------------
    // ----------------------------------------------> TREASURY FUNCTIONS <------------------------------------------------
    // --------------------------------------------------------------------------------------------------------------------

    /**
     * @notice Allows a user to rage quit by exiting the specified token ID from the treasury.
     * @dev This function can only be called externally.
     * @param _tokenId The ID of the token to be burned.
     */
    function rageQuit(uint256 _tokenId) external {
        require(rageQuitAllowed, "CoreLogic: Rage Quit Disabled");
        treasury.exit(_tokenId, psycSale.numberOfNftsSold(), msg.sender);
    }

    /**
     * @notice Allows the contract owner to forcefully exit a token from the treasury.
     * @dev This function can only be called by the contract owner.
     * @param _tokenId The ID of the token to be forcefully exited.
     * @param _user The address of the user whose token will be forcefully exited.
     */
    function kick(uint256 _tokenId, address _user) external onlyOwner {
        treasury.exit(_tokenId, psycSale.numberOfNftsSold(), _user);
    }

    // --------------------------------------------------------------------------------------------------------------------
    // -------------------------------------------> PSYC SALE FUNCTIONS <--------------------------------------------------
    // --------------------------------------------------------------------------------------------------------------------

    /**
     * @notice Creates a batch of NFTs for sale and sends tokens to PsycSale.
     * @dev This function can only be called by the contract owner.
     * @param _tokenIDs Token IDs to be included in batch.
     * @param _saleStartTime Start time of sale.
     * @param _merkleRoot Merkle Root of whitelisted merkle tree.
     */
    function createSaleBatchPsycSale(
        uint256[] memory _tokenIDs,
        uint256 _saleStartTime,
        uint256 _floorPrice,
        uint256 _ceilingPrice,
        bytes32 _merkleRoot,
        string memory _ipfsHash
    ) external onlyOwner returns (uint256) {
        transferNftsPsycSale(_tokenIDs);
        uint256 batchID = psycSale.createSaleBatch(
            _tokenIDs, 
            _saleStartTime, 
            _floorPrice, 
            _ceilingPrice, 
            _merkleRoot, 
            _ipfsHash
        );

        return batchID;
    }

    // --------------------------------------------------------------------------------------------------------------------
    // ----------------------------------------------> INTERNAL FUNCTIONS <------------------------------------------------
    // --------------------------------------------------------------------------------------------------------------------

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}
    
    function _transfer(uint256[] memory _tokenIds, address _user) internal {
        psyNFT.transferNFTs(_tokenIds, _user);
    }

    function transferNftsPsycSale(uint256[] memory _tokenIds) internal {
        _transfer(_tokenIds, address(psycSale));
    }
}
