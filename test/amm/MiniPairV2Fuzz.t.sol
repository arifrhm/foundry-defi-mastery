// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {MiniPairV2} from "../../src/amm/MiniPairV2.sol";
import {MockERC20} from "../mocks/MockERC20.sol";

contract MiniPairV2FuzzTest is Test {
    MiniPairV2 internal pair;
    MockERC20 internal tokenA;
    MockERC20 internal tokenB;

    address internal actor = address(0x1337);

    function setUp() public {
        tokenA = new MockERC20("Token A", "TKNA");
        tokenB = new MockERC20("Token B", "TKNB");

        if (address(tokenA) > address(tokenB)) {
            (tokenA, tokenB) = (tokenB, tokenA);
        }

        pair = new MiniPairV2(address(tokenA), address(tokenB));

        // Initial pool liquidity: 1,000,000 tokens each
        tokenA.mint(address(this), 1_000_000 ether);
        tokenB.mint(address(this), 1_000_000 ether);

        tokenA.transfer(address(pair), 1_000_000 ether);
        tokenB.transfer(address(pair), 1_000_000 ether);
        pair.mint(address(this));

        // Actor gets substantial balance
        tokenA.mint(actor, 10_000_000 ether);
        tokenB.mint(actor, 10_000_000 ether);
    }

    /// @notice Fuzz testing swap with 1000 runs to guarantee k never decreases
    function testFuzz_SwapInvariantKNeverDecreases(uint256 amountInRaw) public {
        // Bound input to [1 wei, 100,000 ether] to prevent overflow and excessive drainage
        uint256 amountIn = bound(amountInRaw, 1, 100_000 ether);

        (uint112 r0Before, uint112 r1Before,) = pair.getReserves();
        uint256 kBefore = uint256(r0Before) * uint256(r1Before);

        // Calculate maximum valid amountOut considering 0.3% fee
        uint256 amountInWithFee = amountIn * 997;
        uint256 numerator = amountInWithFee * uint256(r1Before);
        uint256 denominator = (uint256(r0Before) * 1000) + amountInWithFee;
        uint256 amountOut = numerator / denominator;

        if (amountOut == 0 || amountOut >= r1Before) {
            return;
        }

        vm.startPrank(actor);
        tokenA.transfer(address(pair), amountIn);
        pair.swap(0, amountOut, actor, "");
        vm.stopPrank();

        (uint112 r0After, uint112 r1After,) = pair.getReserves();
        uint256 kAfter = uint256(r0After) * uint256(r1After);

        // Mathematical invariant: kAfter must be strictly >= kBefore due to accumulated fees
        assertTrue(kAfter >= kBefore, "Invariant violation: k decreased after swap!");
    }
}
