// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "./PsyNFT.sol";
import "openzeppelin-contracts/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

contract Treasury is Ownable2Step, ReentrancyGuard, Pausable {
    PsyNFT public psyNFT;

    address public core;
    address public psycSale;
    uint256 public rageQuitBalance;
    uint256 public pendingBalances;

    mapping(address => uint256) public userBalances;

    constructor(address _psyNFT) Ownable(msg.sender) isZeroAddress(_psyNFT) {
        psyNFT = PsyNFT(_psyNFT);
    }

    // --------------------------------------------------------------------------------------------------------------------
    // -----------------------------------------> ONLY CORE LOGIC CONTRACT FUNCTIONS <-------------------------------------------
    // --------------------------------------------------------------------------------------------------------------------

    /**
     * @notice Allows a user to exit by burning their token and receiving a payout.
     * @dev The user must be the owner of the token and the function can only be called by the CoreLogic contract.
     * @param _tokenId The ID of the token to be burned.
     * @param _user The address of the user who owns the token.
     */
    function exit(uint256 _tokenId, uint256 _numberofTokensSold, address _user) external nonReentrant whenNotPaused {
        require(_user == psyNFT.ownerOf(_tokenId), "Treasury: Not token owner");
        require(msg.sender == core, "Treasury: Only callable by CoreLogic.sol");

        uint256 payout = _calculateProRataPayout(_numberofTokensSold);
        userBalances[_user] += payout;
        pendingBalances += payout;
        rageQuitBalance -= payout;

        psyNFT.burn(_tokenId);
    }

    // --------------------------------------------------------------------------------------------------------------------
    // ----------------------------------------> ONLY CONTRACT OWNER FUNCTIONS <-------------------------------------------
    // --------------------------------------------------------------------------------------------------------------------

    /**
     * @notice Sets the address of the CoreLogic contract.
     * @dev Only the contract owner can call this function.
     * @param _core The address of the CoreLogic contract.
     * @dev The address cannot be the zero address.
     */
    function setCoreContract(address _core) external onlyOwner isZeroAddress(_core) {
        core = _core;
    }

    /**
     * @notice Updates the address of the Psy NFT contract.
     * @dev Only the contract owner can call this function.
     * @param _psyNft The address of the psyNFT contract.
     * @dev The address cannot be the zero address.
     */
    function updatePsyNftContract(address _psyNft) external onlyOwner isZeroAddress(_psyNft) {
        psyNFT = PsyNFT(_psyNft);
    }

    /**
     * @notice Updates the address of the psycSale contract.
     * @dev Only the contract owner can call this function.
     * @param _psycSale The address of the psyc sale contract.
     * @dev The address cannot be the zero address.
     */
    function updatePsycSaleAddress(address _psycSale) external onlyOwner isZeroAddress(_psycSale) {
        psycSale = _psycSale;
    }

    /**
     * @notice Withdraws funds from the Treasury contract and sends them to the specified receiver address.
     * @dev Only the contract owner can call this function.
     * @dev The amount to withdraw must be available in the Treasury contract's balance.
     * @param _receiver The address to which the funds will be sent.
     * @param _amount The amount of funds to withdraw.
     */
    function withdrawFundsAsPsyDao(address _receiver, uint256 _amount)
        external
        isZeroAddress(_receiver)
        onlyOwner
        nonReentrant
        whenNotPaused
    {
        require(address(this).balance - pendingBalances - rageQuitBalance >= _amount, "Treasury: Insufficient Balance");
        require(_amount > 0, "Treasury: Cannot Withdraw Zero");

        (bool sent,) = _receiver.call{value: _amount}("");
        require(sent, "Failed to send Ether");
    }

    /**
     * @notice Pauses the contract.
     * @dev The function can only be called by the contract owner.
     */
    function pause() external onlyOwner {
        _requireNotPaused();
        _pause();
    }

    /**
     * @notice Unpauses the contract.
     * @dev The function can only be called by the contract owner.
     */
    function unpause() external onlyOwner {
        _requirePaused();
        _unpause();
    }

    // --------------------------------------------------------------------------------------------------------------------
    // -----------------------------------------------> PUBLIC FUNCTIONS <-------------------------------------------------
    // --------------------------------------------------------------------------------------------------------------------

    /**
     * @notice Allows a user to withdraw their funds from the Treasury contract.
     * @dev The user must have a positive balance in the Treasury contract.
     * @dev The function can only be called by the user.
     * @dev The user's balance will be set to zero after the withdrawal.
     * @dev The amount to send must be available in the Treasury contract's balance.
     */
    function withdrawUserFunds() external nonReentrant whenNotPaused {
        require(userBalances[msg.sender] > 0, "Treasury: User Insufficient Balance");

        uint256 amountToSend = userBalances[msg.sender];
        
        userBalances[msg.sender] = 0;
        pendingBalances -= amountToSend;

        (bool sent,) = msg.sender.call{value: amountToSend}("");
        require(sent, "Failed to send Ether");
    }

    /**
     * @notice Allows the Psyc Sale contract to send profits to the Treasury contract.
     * @dev The function can only be called by the Psyc Sale contract.
     */
    function receiveRageQuitProfit() external payable whenNotPaused {
        require(msg.sender == psycSale, "Treasury: Only callable by Psyc Sale");
        rageQuitBalance += msg.value;
    }

    receive() external payable whenNotPaused {}

    // --------------------------------------------------------------------------------------------------------------------
    // ----------------------------------------------> INTERNAL FUNCTIONS <------------------------------------------------
    // --------------------------------------------------------------------------------------------------------------------

    function _calculateProRataPayout(uint256 _numberOftokensSold) internal view returns (uint256) {
        uint256 currentSupply = _numberOftokensSold - psyNFT.totalTokensBurnt();
        return rageQuitBalance / currentSupply;
    }

    modifier isZeroAddress(address _address) {
        require(_address != address(0), "Treasury: Cannot Be Zero Address");
        _;
    }
}
