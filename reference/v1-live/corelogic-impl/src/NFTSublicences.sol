// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC1155/ERC1155Upgradeable.sol";
import "./PsyNFT.sol";
import "./PsycSale.sol";

contract NFTSublicences is Initializable, ERC1155Upgradeable, Ownable2StepUpgradeable, UUPSUpgradeable {
    
    struct TokenInformation {
        uint256 floorPrice;
        uint256 ceilingPrice;
        bool saleActive;
    }
    
    PsycSale public psycSale;
    PsyNFT public psyNft;

    mapping(uint256 => TokenInformation) public tokenInformation;

    event TokenPriceUpdate(uint256 tokenId, uint256 floor, uint256 ceiling);
    event SaleStatusChanged(bool newStatus);
    event PsycSaleSet(address psycSale);
    event PsyNftAddressChanged(address psyNft);
    event UpdatedBaseUri(string _uri);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _psyNft, 
        string memory _initUri
    ) external initializer {
        require(_psyNft != address(0), "NFTSublicences: Cannot Be Zero Address");

        __Ownable2Step_init();
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
        __ERC1155_init(_initUri);
        psyNft = PsyNFT(_psyNft);
    }

    // --------------------------------------------------------------------------------------------------------------------
    // --------------------------------------> ONLY PSYC SALE CONTRACT FUNCTIONS <-----------------------------------------
    // --------------------------------------------------------------------------------------------------------------------

    /**
     * @notice Mints a copy of a ERC721.
     * @dev Only the Psyc Sale contract can call this function.
     * @param _minter The address of the minter who will receive the sublicenses.
     * @param _erc721TokenId The ID of the ERC721 token for which sublicenses are being minted.
     */
    function mint(address _minter, uint256 _erc721TokenId) external OnlyPsycSale {
        require(tokenInformation[_erc721TokenId].saleActive, "NFTSublicences: Sale Paused");
        _mint(_minter, _erc721TokenId, 1, "");
    }

    /**
     * @notice Sets the floor and ceiling prices for a token.
     * @dev Only the Psyc Sale contract can call this function.
     * @param _tokenId The ID of the token for which the prices are being set.
     * @param _floor The floor price for the token.
     * @param _ceiling The ceiling price for the token. 
     */
    function setNftPrices(uint256 _tokenId, uint256 _floor, uint256 _ceiling) external OnlyPsycSale {
        tokenInformation[_tokenId].floorPrice = _floor;
        tokenInformation[_tokenId].ceilingPrice = _ceiling;

        emit TokenPriceUpdate(_tokenId, _floor, _ceiling);
    }

    // --------------------------------------------------------------------------------------------------------------------
    // -----------------------------------------> ONLY TOKEN OWNER FUNCTIONS <---------------------------------------------
    // --------------------------------------------------------------------------------------------------------------------

    /**
     * @notice Mints a copy of a ERC721 to the owner of the ERC721 token.
     * @dev Only the owner of the ERC721 token can call this function.
     * @param _erc721TokenId The ID of the ERC721 token for which sublicenses are being minted.
     * @param _amount The number of sublicenses to mint.
     * @notice This gives the owner a free way to mint.
     */
    function mintAs721Owner(uint256 _erc721TokenId, uint256 _amount) external Only721Owner(_erc721TokenId) {
        _mint(msg.sender, _erc721TokenId, _amount, "");
    }

    /**
     * @notice Switches the sale status of a token.
     * @dev Only the owner of the token can call this function.
     * @param _tokenId The ID of the token for which the sale status is being switched.
     */
    function switchSaleStatus(uint256 _tokenId) external Only721Owner(_tokenId) {
        tokenInformation[_tokenId].saleActive = !tokenInformation[_tokenId].saleActive;

        emit SaleStatusChanged(tokenInformation[_tokenId].saleActive);
    }

    // --------------------------------------------------------------------------------------------------------------------
    // ----------------------------------------> ONLY CONTRACT OWNER FUNCTIONS <-------------------------------------------
    // --------------------------------------------------------------------------------------------------------------------

    /**
     * @notice Sets the Psyc Sale contract address.
     * @dev Only the owner of the contract can call this function.
     * @param _psycSale The address of the Psyc Sale contract.
     */
    function setPsycSaleContract(address _psycSale) external onlyOwner {
        require(_psycSale != address(0), "NFTSublicences: Cannot Be Zero Address");

        psycSale = PsycSale(_psycSale);

        emit PsycSaleSet(_psycSale);
    }

    /**
     * @notice Updates the address of the PsyNFT contract.
     * @dev Only the owner of the contract can call this function.
     * @param _psyNft The address of the PsyNFT contract.
     */
    function updatePsyNftContract(address _psyNft) external onlyOwner {
        require(_psyNft != address(0), "NFTSublicences: Cannot Be Zero Address");

        psyNft = PsyNFT(_psyNft);
        emit PsyNftAddressChanged(_psyNft);
    }

    /**
     * @notice Updates the base URI for the ERC1155 token metadata.
     * @dev Only the contract owner can call this function.
     * @param _newuri The new base URI to set for the token metadata.
     */
    function updateBaseUri(string memory _newuri) external onlyOwner {
        _setURI(_newuri);
        
        emit UpdatedBaseUri(_newuri);
    }

    // --------------------------------------------------------------------------------------------------------------------
    // ----------------------------------------------> INTERNAL FUNCTIONS <------------------------------------------------
    // --------------------------------------------------------------------------------------------------------------------

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}

    // --------------------------------------------------------------------------------------------------------------------
    // -------------------------------------------------> MODIFIERS <------------------------------------------------------
    // --------------------------------------------------------------------------------------------------------------------

    modifier OnlyPsycSale() {
        require(msg.sender == address(psycSale), "NFTSublicences: Caller Not Psyc Sale");
        _;
    }

    modifier Only721Owner(uint256 _tokenId) {
        require(msg.sender == psyNft.ownerOf(_tokenId), "NFTSublicences: Not Token Owner");
        _;
    }
}
