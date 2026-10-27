// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/// @title ConcentratedSimulator
/// @notice Mathematical simulator for Uniswap v3 style concentrated liquidity & virtual reserves
/// @dev Calculates virtual reserves, liquidity density (L), and capital efficiency multiplier within [Pa, Pb]
contract ConcentratedSimulator {
    uint256 public constant WAD = 1e18; // 18 decimal fixed-point precision

    struct Position {
        uint256 sqrtPriceLowerX96; // sqrt(Pa) in Q96
        uint256 sqrtPriceUpperX96; // sqrt(Pb) in Q96
        uint128 liquidity;         // L
        uint256 realReserve0;      // x_real
        uint256 realReserve1;      // y_real
        uint256 virtualReserve0;   // x_virtual
        uint256 virtualReserve1;   // y_virtual
    }

    error InvalidPriceRange();
    error PriceOutOfBounds();

    /// @notice Compute liquidity L given amount of token0 and price range
    function getLiquidityForAmount0(
        uint256 sqrtRatioAX96,
        uint256 sqrtRatioBX96,
        uint256 amount0
    ) public pure returns (uint128 liquidity) {
        if (sqrtRatioAX96 > sqrtRatioBX96) (sqrtRatioAX96, sqrtRatioBX96) = (sqrtRatioBX96, sqrtRatioAX96);
        uint256 intermediate = Math.mulDiv(sqrtRatioAX96, sqrtRatioBX96, 2**96);
        liquidity = uint128(Math.mulDiv(amount0, intermediate, sqrtRatioBX96 - sqrtRatioAX96));
    }

    /// @notice Compute liquidity L given amount of token1 and price range
    function getLiquidityForAmount1(
        uint256 sqrtRatioAX96,
        uint256 sqrtRatioBX96,
        uint256 amount1
    ) public pure returns (uint128 liquidity) {
        if (sqrtRatioAX96 > sqrtRatioBX96) (sqrtRatioAX96, sqrtRatioBX96) = (sqrtRatioBX96, sqrtRatioAX96);
        liquidity = uint128(Math.mulDiv(amount1, 2**96, sqrtRatioBX96 - sqrtRatioAX96));
    }

    /// @notice Simulate virtual reserves from real deposits within range [sqrtPa, sqrtPb] at current price sqrtP
    function simulatePosition(
        uint256 sqrtCurrentX96,
        uint256 sqrtPriceLowerX96,
        uint256 sqrtPriceUpperX96,
        uint256 amount0Real,
        uint256 amount1Real
    ) external pure returns (Position memory pos) {
        if (sqrtPriceLowerX96 >= sqrtPriceUpperX96) revert InvalidPriceRange();
        if (sqrtCurrentX96 < sqrtPriceLowerX96 || sqrtCurrentX96 > sqrtPriceUpperX96) revert PriceOutOfBounds();

        pos.sqrtPriceLowerX96 = sqrtPriceLowerX96;
        pos.sqrtPriceUpperX96 = sqrtPriceUpperX96;
        pos.realReserve0 = amount0Real;
        pos.realReserve1 = amount1Real;

        uint128 l0 = getLiquidityForAmount0(sqrtCurrentX96, sqrtPriceUpperX96, amount0Real);
        uint128 l1 = getLiquidityForAmount1(sqrtPriceLowerX96, sqrtCurrentX96, amount1Real);
        pos.liquidity = l0 < l1 ? l0 : l1;

        // Virtual reserves:
        // x_virtual = x_real + L / sqrt(Pb)
        // y_virtual = y_real + L * sqrt(Pa)
        uint256 xOffset = Math.mulDiv(uint256(pos.liquidity), 2**96, sqrtPriceUpperX96);
        uint256 yOffset = Math.mulDiv(uint256(pos.liquidity), sqrtPriceLowerX96, 2**96);

        pos.virtualReserve0 = amount0Real + xOffset;
        pos.virtualReserve1 = amount1Real + yOffset;
    }

    /// @notice Calculate theoretical capital efficiency multiplier: 1 / (1 - sqrt(Pa / Pb))
    /// @param priceLower Price at lower tick (WAD format, e.g. 1e18 = 1.0)
    /// @param priceUpper Price at upper tick (WAD format, e.g. 1.2e18 = 1.2)
    /// @return efficiencyMultiplier Multiplier scaled by WAD (e.g., 10e18 = 10x more capital efficient than v2)
    function calculateCapitalEfficiency(
        uint256 priceLower,
        uint256 priceUpper
    ) external pure returns (uint256 efficiencyMultiplier) {
        if (priceLower >= priceUpper) revert InvalidPriceRange();
        // ratio = priceLower / priceUpper (scaled by WAD)
        uint256 ratio = Math.mulDiv(priceLower, WAD, priceUpper);
        // sqrtRatio = sqrt(ratio * WAD)
        uint256 sqrtRatio = Math.sqrt(ratio * WAD);
        uint256 denominator = WAD - sqrtRatio;
        if (denominator == 0) return type(uint256).max;
        efficiencyMultiplier = Math.mulDiv(WAD, WAD, denominator);
    }
}
