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
import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import {IUniswapV2Pair} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import {IUniswapV2Factory} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";

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
    uint256 public immutable i_maxWithdrawal;

    /**
     * @dev Balance of the contract in USDC.
     */
    uint256 public s_balanceInUSDC;

    /**
     * @dev Maximum total USDC the contract can hold.
     */
    uint256 public immutable i_bankCap;

    /**
     * @dev USDC token contract.
     */
    IERC20 public immutable s_usdc;

    /**
     * @dev Uniswap router contract
     */
    IUniswapV2Router02 public s_uniswapRouter;

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
    event KipuBank_DepositReceived(
        address user,
        uint256 amount,
        address token,
        uint256 amountInUSDC
    );

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
    error KipuBank_BankCapReached(
        uint256 maxContractBalance,
        uint256 currentBalance,
        uint256 transactionAmount
    );

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
    error KipuBank_TooMuchWithdrawal(
        uint256 maxAmountPerWithdrawal,
        uint256 amount
    );

    /**
     * @dev Reverted when the token address is invalid.
     */
    error KipuBank_InvalidAddress();

    /**
     * @dev Reverted when the amount is invalid.
     */
    error KipuBank_InvalidAmount();

    /**
     * @dev Reverted when the pair does not exists.
     * @param tokenA Token address of the pair.
     * @param tokenB Token address of the pair.
     */
    error KipuBank_PairDoesNotExist(address tokenA, address tokenB);

    /**
     * @dev Reverted when the amountOut is less than expected.
     * @param minAmountOutExpected Amount out expected.
     * @param amountOut Amount out calculated.
     */
    error KipuBank_InsufficientOutputAmount(
        uint256 minAmountOutExpected,
        uint256 amountOut
    );

    /**
     * @dev Reverted when the amount deposited is not the expected.
     * @param amountOutExpected Amount out expected.
     * @param amountOut Amount out deposited.
     */
    error KipuBank_UnexpectedAmountDeposited(
        uint256 amountOutExpected,
        uint256 amountOut
    );

    /*///////////////////////////////////

                Modifiers

    ///////////////////////////////////*/

    /// @notice Check that the token is valid
    /// @param token Token address to validate
    modifier validTokenAddress(address token) {
        if (token == address(0)) {
            revert KipuBank_InvalidAddress();
        }
        _;
    }

    /// @notice Check that the amount is greater than 0
    /// @param amount Amount to validate
    modifier validAmount(uint256 amount) {
        if (amount == 0) {
            revert KipuBank_InvalidAmount();
        }
        _;
    }

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
        address _usdc,
        address _uniswapRouter
    ) Ownable(_owner) {
        i_maxWithdrawal = _maxWithdrawal;
        i_bankCap = _bankCap;
        s_usdc = IERC20(_usdc);
        s_uniswapRouter = IUniswapV2Router02(_uniswapRouter);
    }

    /*/////////////////////////
        Receive&Fallback
    /////////////////////////*/
    /**
     * @dev Receive function to deposit ETH.
     */
    receive() external payable {
        _depositETH(msg.sender, msg.value, 0);
    }

    /**
     * @dev Fallback function to prevent accidental ETH transfers.
     */
    fallback() external payable {
        _depositETH(msg.sender, msg.value, 0);
    }

    /*/////////////////////////
            external
    /////////////////////////*/
    /**
     * @dev Function to deposit ETH into the contract.
     * @param _minAmountInUSDC The minimum amount of USDC after the swap.
     */
    function depositETH(uint256 _minAmountInUSDC) external payable nonReentrant {
        _depositETH(msg.sender, msg.value, _minAmountInUSDC);
    }

    /**
     * @dev Function to deposit tokens into the contract.
     * @param _token The address of the token to deposit.
     * @param _amountIn The amount of token to deposit.
     * @param _minAmountInUSDC The minimum amount of USDC after the swap.
     */
    function depositToken(
        address _token,
        uint256 _amountIn,
        uint256 _minAmountInUSDC
    ) external nonReentrant validTokenAddress(_token) validAmount(_amountIn) {
        // Check
        IUniswapV2Pair pair = _getPair(_token, address(s_usdc));
        uint256 amountOutExpected = _calculateAmountOut(
            pair,
            _amountIn,
            _token
        );

        if (amountOutExpected < _minAmountInUSDC) {
            revert KipuBank_InsufficientOutputAmount(
                _minAmountInUSDC,
                amountOutExpected
            );
        }

        if (_exceedsBankCap(amountOutExpected)) {
            revert KipuBank_BankCapReached(
                i_bankCap,
                s_balanceInUSDC,
                amountOutExpected
            );
        }

        // Effects
        s_depositCount += 1;
        s_balances[msg.sender] += amountOutExpected;
        s_balanceInUSDC += amountOutExpected;

        // Interaction
        IERC20(_token).safeTransferFrom(msg.sender, address(this), _amountIn);
        IERC20(_token).approve(address(s_uniswapRouter), 0);
        IERC20(_token).approve(address(s_uniswapRouter), _amountIn);
        _swapTokens(_token, address(s_usdc), _amountIn, amountOutExpected);

        emit KipuBank_DepositReceived(
            msg.sender,
            _amountIn,
            _token,
            amountOutExpected
        );
    }

    /**
     * @dev Withdraw USDC from the contract.
     * @param _amount The amount of USDC to withdraw.
     */
    function withdrawUSDC(uint256 _amount) external nonReentrant {
        if (_amount > i_maxWithdrawal) {
            revert KipuBank_TooMuchWithdrawal(i_maxWithdrawal, _amount);
        }

        if (s_balances[msg.sender] < _amount) {
            revert KipuBank_NotEnoughBalance(s_balances[msg.sender], _amount);
        }

        s_withdrawalCount += 1;
        s_balances[msg.sender] -= _amount;
        s_balanceInUSDC -= _amount;

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
     * @param _amountIn The amount of token ETH to deposit.
     * @param _minAmountInUSDC The minimum amount of USCD after the swap.
     */
    function _depositETH(address _from, uint256 _amountIn, uint256 _minAmountInUSDC) private validAmount(_amountIn) {
        // Check
        address weth = s_uniswapRouter.WETH();
        IUniswapV2Pair pair = _getPair(weth, address(s_usdc));
        uint256 amountOutExpected = _calculateAmountOut(
            pair,
            _amountIn,
            weth
        );

        if (amountOutExpected < _minAmountInUSDC) {
            revert KipuBank_InsufficientOutputAmount(
                _minAmountInUSDC,
                amountOutExpected
            );
        }

        if (_exceedsBankCap(amountOutExpected)) {
            revert KipuBank_BankCapReached(
                i_bankCap,
                s_balanceInUSDC,
                amountOutExpected
            );
        }

        // Effects
        s_depositCount += 1;
        s_balances[_from] += amountOutExpected;
        s_balanceInUSDC += amountOutExpected;

        // Interaction
        _swapTokens(weth, address(s_usdc), _amountIn, amountOutExpected);

        emit KipuBank_DepositReceived(
            _from,
            _amountIn,
            weth,
            amountOutExpected
        );
    }


    /**
     * @dev Function to calculate the amount of tokenOut to receive for a given amount of tokenIn.
     * @param _pair The pair of tokens.
     * @param _amountIn The amount of tokenIn to swap.
     * @param _tokenIn The address of the token to give.
     * @return amountOut_ The amount of tokenOut to receive.
     */
    function _calculateAmountOut(
        IUniswapV2Pair _pair,
        uint256 _amountIn,
        address _tokenIn
    ) private view returns (uint256 amountOut_) {
        (uint256 reserve0, uint256 reserve1, ) = _pair.getReserves();

        address token0 = _pair.token0();
        bool token0IsTokenIn = token0 == _tokenIn;

        amountOut_ = s_uniswapRouter.getAmountOut(
            _amountIn,
            token0IsTokenIn ? reserve0 : reserve1,
            token0IsTokenIn ? reserve1 : reserve0
        );
    }

    /**
     * @dev Function to get the pair for tokenA and tokenB.
     * @param _tokenA The address of the first token of the pair.
     * @param _tokenB The address of the second token of the pair.
     * @return pair_ The address of the pair validated.
     */
    function _getPair(
        address _tokenA,
        address _tokenB
    ) private view returns (IUniswapV2Pair pair_) {
        address pair = IUniswapV2Factory(s_uniswapRouter.factory()).getPair(
            _tokenA,
            _tokenB
        );
        if (pair == address(0)) {
            revert KipuBank_PairDoesNotExist(_tokenA, _tokenB);
        }
        pair_ = IUniswapV2Pair(pair);
    }

    /**
     * @dev Function to swap exact amount of tokenIn for exact amount of tokenOut. If the swap is not exact, the action is reverted.
     * @param _tokenIn The address of the token to give.
     * @param _tokenOut The address of the token to swap.
     * @param _amountIn The amount of tokenIn to swap.
     * @param _amountOut The amount of tokenOut to receive.
     */
    function _swapTokens(
        address _tokenIn,
        address _tokenOut,
        uint256 _amountIn,
        uint256 _amountOut
    )
        private
        validTokenAddress(_tokenIn)
        validTokenAddress(_tokenOut)
        validAmount(_amountIn)
        validAmount(_amountOut)
    {
        address[] memory path = new address[](2);
        path[0] = _tokenIn;
        path[1] = _tokenOut;
        uint deadline = block.timestamp + 300;
        uint256 oldBalance = IERC20(_tokenOut).balanceOf(address(this));
        s_uniswapRouter.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            _amountIn,
            _amountOut,
            path,
            address(this),
            deadline
        );
        uint256 newBalance = IERC20(_tokenOut).balanceOf(address(this));
        uint256 amountDeposited = newBalance - oldBalance;

        if (_amountOut != amountDeposited) {
            revert KipuBank_UnexpectedAmountDeposited(
                _amountOut,
                amountDeposited
            );
        }
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

    /**
     * @dev Function to get the amountOut in USDC for a given amount and token.
     * @param _token The address of the token to swap.
     * @param _amountIn The amount of token to swap.
     * @return uint256 The amountOut in USDC.
     */
    function getAmountOutInUSDC(
        address _token,
        uint256 _amountIn
    ) external view validTokenAddress(_token) validAmount(_amountIn) returns (uint256) {
        IUniswapV2Pair pair = _getPair(_token, address(s_usdc));
        return _calculateAmountOut(pair, _amountIn, _token);
    }
}
