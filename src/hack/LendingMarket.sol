// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {VulnerablePool} from "./VulnerablePool.sol";

/// @title LendingMarket (Victim Protocol)
/// @notice Implements collateralized lending using VulnerablePool.getVirtualPrice() as Oracle
contract LendingMarket {
    VulnerablePool public immutable pool;
    IERC20 public immutable borrowAsset; // e.g. USDC or DAI

    uint256 public constant ETH_USD_PRICE = 2000; // 1 ETH = 2,000 USD
    uint256 public constant COLLATERAL_FACTOR = 80; // 80% LTV
    uint256 public constant BPS_DENOMINATOR = 100;

    mapping(address => uint256) public collateralDeposited;
    mapping(address => uint256) public borrowedAmount;

    error InsufficientCollateral();
    error TransferFailed();

    constructor(VulnerablePool _pool, IERC20 _borrowAsset) {
        pool = _pool;
        borrowAsset = _borrowAsset;
    }

    /// @notice Deposit LP token as collateral
    function depositCollateral(uint256 lpAmount) external {
        collateralDeposited[msg.sender] += lpAmount;
        bool ok = pool.transferFrom(msg.sender, address(this), lpAmount);
        if (!ok) revert TransferFailed();
    }

    /// @notice Borrow debt tokens against deposited LP collateral value
    function borrow(uint256 amountToBorrow) external {
        uint256 lpCollateral = collateralDeposited[msg.sender];
        if (lpCollateral == 0) revert InsufficientCollateral();

        // Query oracle: VulnerablePool.getVirtualPrice()
        uint256 virtualPrice = pool.getVirtualPrice(); // LP virtual price in ETH (WAD)

        // Collateral valuation in USD units: (lp * virtualPrice / 1e18) * ETH_USD_PRICE
        uint256 collateralValueInEth = (lpCollateral * virtualPrice) / 1e18;
        uint256 collateralValueInUsd = collateralValueInEth * ETH_USD_PRICE;
        uint256 maxBorrowCapacity = (collateralValueInUsd * COLLATERAL_FACTOR) / BPS_DENOMINATOR;

        uint256 totalDebt = borrowedAmount[msg.sender] + amountToBorrow;
        if (totalDebt > maxBorrowCapacity) revert InsufficientCollateral();

        borrowedAmount[msg.sender] = totalDebt;
        bool ok = borrowAsset.transfer(msg.sender, amountToBorrow);
        if (!ok) revert TransferFailed();
    }
}
