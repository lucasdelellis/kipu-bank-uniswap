// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

/*///////////////////////
        Imports
///////////////////////*/
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/*///////////////////////
        Libraries
///////////////////////*/
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/*///////////////////////
        Interfaces
///////////////////////*/
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title KipuBank
 * @author lucasdelellis
 * @notice This contract implements a simple bank system where users can deposit and withdraw ETH and USDC.
 * @dev The contract has a maximum cap on the total ETH it can hold and a maximum withdrawal limit per transaction.
 */
contract KipuBank is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /*///////////////////////////////////
            State variables
    ///////////////////////////////////*/
    /**
     * @dev Mapping to store the balance of each user in USDC.
     */
    mapping(address user => uint256 balance) private s_balances;

    /**
     * @dev Counter for the number of deposits made.
     */
    uint256 public s_depositCount;

    /**
     * @dev Counter for the number of withdrawals made.
     */
    uint256 public s_withdrawalCount;

    /**
     * @dev Maximum amount that can be withdrawn in a single transaction in USDC.
     */
    uint256 immutable public i_maxWithdrawal;

    /**
     * @dev Balance of the contract in USDC.
     */
    uint256 public s_balanceInUSDC;

    /**
     * @dev Maximum total USDC the contract can hold.
     */
    uint256 immutable public i_bankCap;

    /**
     * @dev USDC token contract.
     */
    IERC20 immutable public s_usdc;    

    /*///////////////////////////////////
                Events
    ///////////////////////////////////*/
    /**
     * @dev Emitted when a deposit is received.
     * @param user The address of the user who made the deposit.
     * @param amount The amount of token deposited.
     * @param token The address of the token of the deposit.
     * @param amountInUSDC The amount deposited in the user balance after swapping to USDC.
     */
    event KipuBank_DepositReceived(address user, uint256 amount, address token, uint256 amountInUSDC);

    /**
     * @dev Emitted when a withdrawal is made.
     * @param user The address of the user who made the withdrawal.
     * @param amount The amount of USDC withdrawn.
     * @param token The address of the token of the withdrawal.
     */
    event KipuBank_WithdrawalMade(address user, uint256 amount, address token);

    /*///////////////////////////////////
                Errors
    ///////////////////////////////////*/
    /**
     * @dev Reverted when the contract's balance cap is reached.
     * @param maxContractBalance The maximum balance the contract can hold in USDC.
     * @param currentBalance The current balance of the contract in USDC.
     * @param transactionAmount The amount of USDC of the deposit.
     */
    error KipuBank_BankCapReached(uint256 maxContractBalance, uint256 currentBalance, uint256 transactionAmount);

    /**
     * @dev Reverted when the user does not have enough balance to withdraw.
     * @param balance The current balance of the user.
     * @param amount The amount the user tried to withdraw.
     */
    error KipuBank_NotEnoughBalance(uint256 balance, uint256 amount);

    /**
     * @dev Reverted when the withdrawal amount exceeds the maximum allowed per transaction.
     * @param maxAmountPerWithdrawal The maximum amount allowed per withdrawal.
     * @param amount The amount the user tried to withdraw.
     */
    error KipuBank_TooMuchWithdrawal(uint256 maxAmountPerWithdrawal, uint256 amount);

    /**
     * @dev Reverted when the ETH transfer fails.
     * @param error The error message from the failed transfer.
     */
    // error KipuBank_TransferFailed(bytes error);
    // TODO Ver si sirve
    

    /*/////////////////////////
            constructor
    /////////////////////////*/
    /**
     * @param _bankCap The maximum total USDC the contract can hold.
     * @param _maxWithdrawal The maximum amount (in USDC) that can be withdrawn per transaction.
     * @param _owner The address of the contract owner.
     * @param _usdc USDC token address.
     */
    constructor(
        uint256 _bankCap,
        uint256 _maxWithdrawal,
        address _owner,
        address _usdc
    ) Ownable(_owner) {
        i_maxWithdrawal = _maxWithdrawal;
        i_bankCap = _bankCap;
        s_usdc = IERC20(_usdc);
    }

    /*/////////////////////////
        Receive&Fallback
    /////////////////////////*/
    /**
     * @dev Receive function to deposit ETH.
     */
    receive() external payable {
        _depositETH(msg.sender, msg.value);
    }

    /**
     * @dev Fallback function to prevent accidental ETH transfers.
     */
    fallback() external payable {
        _depositETH(msg.sender, msg.value);
    }

    /*/////////////////////////
            external
    /////////////////////////*/
    /**
     * @dev Function to deposit ETH into the contract.
     */
    function depositETH() external payable nonReentrant {
        _depositETH(msg.sender, msg.value);
    }

    /**
     * @dev Withdraw USDC from the contract.
     */
    function withdrawUSDC(uint256 _amount) external nonReentrant {
        uint256 amountInUSD = _convertToUSD(_amount, _getUSDCPriceInUSD(), USDC_DECIMALS);

        if (amountInUSD > i_maxWithdrawal) {
            revert KipuBank_TooMuchWithdrawal(i_maxWithdrawal, amountInUSD);
        }

        if (s_balances[msg.sender][address(s_usdc)] < _amount) {
            revert KipuBank_NotEnoughBalance(s_balances[msg.sender][address(s_usdc)], _amount);
        }

        s_withdrawalCount += 1;
        s_balances[msg.sender][address(s_usdc)] -= _amount;
        s_balanceInUSD -= amountInUSD;

        s_usdc.safeTransfer(msg.sender, _amount);

        emit KipuBank_WithdrawalMade(msg.sender, _amount, address(s_usdc));
    }

    /*/////////////////////////
            private
    /////////////////////////*/
    /**
     * @dev Function to check if the deposit exceeds the bank cap.
     * @param _amount The amount to deposit in USDC.
     * @return bool True if the deposit exceeds the bank cap, false otherwise.
     */
    function _exceedsBankCap(uint256 _amount) private view returns (bool) {
        return (s_balanceInUSDC + _amount) > i_bankCap;
    }

    /**
     * @dev Function to deposit ETH into the contract.
     * @param _from The address of the user making the deposit.
     * @param _amount The amount of token ETH to deposit.
     */
    function _depositETH(address _from, uint256 _amount) private {
        uint256 amountInUSD = _convertToUSD(_amount, _getETHPriceInUSD(), ETH_DECIMALS);
        if (_exceedsBankCap(amountInUSD)) {
            revert KipuBank_BankCapReached(i_bankCap, s_balanceInUSD, amountInUSD);
        }

        s_depositCount += 1;
        s_balances[_from][address(0)] += _amount;
        s_balanceInUSD += amountInUSD;
        emit KipuBank_DepositReceived(_from, _amount, address(0));
    }

    /*/////////////////////////
        View & Pure
    /////////////////////////*/
    /**
     * @dev Function to get the balance of the caller.
     * @return uint256 The balance of the caller in USDC.
     */
    function getBalance() external view returns (uint256) {
        return s_balances[msg.sender];
    }
}
