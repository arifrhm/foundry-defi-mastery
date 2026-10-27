// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {MiniPairV2} from "../../src/amm/MiniPairV2.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {ConcentratedSimulator} from "../../src/amm/ConcentratedSimulator.sol";

contract MiniPairV2Test is Test {
    MiniPairV2 internal pair;
    MockERC20 internal tokenA;
    MockERC20 internal tokenB;
    ConcentratedSimulator internal simulator;

    address internal alice = address(0xAAAA);
    address internal bob = address(0xBBBB);

    function setUp() public {
        tokenA = new MockERC20("Token A", "TKNA");
        tokenB = new MockERC20("Token B", "TKNB");

        // Sort tokens to ensure deterministic token0 < token1
        if (address(tokenA) > address(tokenB)) {
            (tokenA, tokenB) = (tokenB, tokenA);
        }

        pair = new MiniPairV2(address(tokenA), address(tokenB));
        simulator = new ConcentratedSimulator();

        tokenA.mint(alice, 1_000_000 ether);
        tokenB.mint(alice, 1_000_000 ether);
        tokenA.mint(bob, 100_000 ether);
        tokenB.mint(bob, 100_000 ether);
    }

    function testInitialLiquidityMint() public {
        vm.startPrank(alice);
        tokenA.transfer(address(pair), 10_000 ether);
        tokenB.transfer(address(pair), 10_000 ether);

        uint256 lpMinted = pair.mint(alice);
        vm.stopPrank();

        // sqrt(10000e18 * 10000e18) - 1000
        assertEq(lpMinted, 10_000 ether - 1000);
        assertEq(pair.balanceOf(address(0x000000000000000000000000000000000000dEaD)), 1000);
        assertEq(pair.totalSupply(), 10_000 ether);

        (uint112 r0, uint112 r1,) = pair.getReserves();
        assertEq(r0, 10_000 ether);
        assertEq(r1, 10_000 ether);
    }

    function testSwapExecutionWithFee() public {
        // Alice adds initial liquidity
        vm.startPrank(alice);
        tokenA.transfer(address(pair), 100_000 ether);
        tokenB.transfer(address(pair), 100_000 ether);
        pair.mint(alice);
        vm.stopPrank();

        // Bob swaps 1,000 tokenA for tokenB
        vm.startPrank(bob);
        tokenA.transfer(address(pair), 1000 ether);

        // Calculate expected amountOut with 0.3% fee:
        // dy = (997 * dx * y) / (1000 * x + 997 * dx)
        // dy = (997 * 1000 * 100000) / (1000 * 100000 + 997 * 1000) = 987.158...
        uint256 amountInWithFee = 1000 ether * 997;
        uint256 expectedOut = (amountInWithFee * 100_000 ether) / (100_000 ether * 1000 + amountInWithFee);

        uint256 bobBBefore = tokenB.balanceOf(bob);
        pair.swap(0, expectedOut, bob, "");
        uint256 bobBAfter = tokenB.balanceOf(bob);

        assertEq(bobBAfter - bobBBefore, expectedOut);
        assertTrue(expectedOut < 1000 ether); // Slippage & fee impact
        vm.stopPrank();

        (uint112 r0, uint112 r1,) = pair.getReserves();
        assertEq(r0, 101_000 ether);
        assertEq(r1, 100_000 ether - expectedOut);
    }

    function testBurnLiquidity() public {
        vm.startPrank(alice);
        tokenA.transfer(address(pair), 10_000 ether);
        tokenB.transfer(address(pair), 10_000 ether);
        uint256 lp = pair.mint(alice);

        pair.transfer(address(pair), lp);
        (uint256 a0, uint256 a1) = pair.burn(alice);
        vm.stopPrank();

        assertTrue(a0 > 9_999 ether);
        assertTrue(a1 > 9_999 ether);
    }

    function testConcentratedLiquidityCapitalEfficiency() public view {
        // Lower price = 0.9 (0.9e18), Upper price = 1.1 (1.1e18) (narrow +/-10% peg band)
        uint256 priceLower = 0.9e18;
        uint256 priceUpper = 1.1e18;

        uint256 efficiency = simulator.calculateCapitalEfficiency(priceLower, priceUpper);
        // Concentrated liquidity is over 10x more capital efficient than full range v2
        assertTrue(efficiency > 10e18);
        console.log("Capital Efficiency for +/-10% band: %s / 1e18 x", efficiency / 1e18);
    }
}
