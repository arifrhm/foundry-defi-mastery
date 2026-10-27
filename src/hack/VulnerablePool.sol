// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title VulnerablePool
/// @notice Demonstrates the classic Curve/Sentiment style Read-Only Reentrancy flaw
/// @dev The pool protects state-changing methods with nonReentrant, but leaves getVirtualPrice() unprotected
contract VulnerablePool is ERC20, ReentrancyGuard {
    uint256 public totalEthReserves;

    event LiquidityAdded(address indexed provider, uint256 ethAmount, uint256 lpMinted);
    event LiquidityRemoved(address indexed provider, uint256 ethAmount, uint256 lpBurned);

    constructor() ERC20("Vulnerable LP Token", "VLP") {}

    /// @notice Add ETH to pool and receive LP shares
    function addLiquidity() external payable nonReentrant returns (uint256 lpShares) {
        require(msg.value > 0, "Zero ETH");
        uint256 _totalSupply = totalSupply();
        if (_totalSupply == 0) {
            lpShares = msg.value;
        } else {
            lpShares = (msg.value * _totalSupply) / totalEthReserves;
        }
        totalEthReserves += msg.value;
        _mint(msg.sender, lpShares);
        emit LiquidityAdded(msg.sender, msg.value, lpShares);
    }

    /// @notice Remove liquidity by burning LP shares
    /// @dev VULNERABILITY: Sends ETH before decrementing totalEthReserves!
    function removeLiquidity(uint256 lpShares) external nonReentrant returns (uint256 ethAmount) {
        require(balanceOf(msg.sender) >= lpShares, "Insufficient LP");
        uint256 _totalSupply = totalSupply();
        ethAmount = (lpShares * totalEthReserves) / _totalSupply;

        _burn(msg.sender, lpShares);

        // State changes to internal accounting totalEthReserves happens AFTER external ETH transfer!
        // During the call, totalEthReserves is still OLD, while totalSupply() is already REDUCED!
        (bool success, ) = msg.sender.call{value: ethAmount}("");
        require(success, "ETH transfer failed");

        totalEthReserves -= ethAmount;
        emit LiquidityRemoved(msg.sender, ethAmount, lpShares);
    }

    /// @notice Read-only view function used by external lending protocols as Price Oracle
    /// @dev During removeLiquidity execution, this function returns an INFLATED price!
    function getVirtualPrice() external view returns (uint256) {
        uint256 _totalSupply = totalSupply();
        if (_totalSupply == 0) return 1e18;
        // virtualPrice = totalEthReserves / totalSupply
        return (totalEthReserves * 1e18) / _totalSupply;
    }

    receive() external payable {}
}
