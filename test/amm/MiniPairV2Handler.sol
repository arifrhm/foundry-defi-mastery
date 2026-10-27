// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {MiniPairV2} from "../../src/amm/MiniPairV2.sol";
import {MockERC20} from "../mocks/MockERC20.sol";

contract MiniPairV2Handler is Test {
    MiniPairV2 public pair;
    MockERC20 public tokenA;
    MockERC20 public tokenB;

    uint256 public previousK;

    constructor(MiniPairV2 _pair, MockERC20 _tokenA, MockERC20 _tokenB) {
        pair = _pair;
        tokenA = _tokenA;
        tokenB = _tokenB;

        (uint112 r0, uint112 r1,) = pair.getReserves();
        previousK = uint256(r0) * uint256(r1);
    }

    function swap0(uint256 amountInRaw) public {
        uint256 amountIn = bound(amountInRaw, 1 ether, 50_000 ether);

        (uint112 r0, uint112 r1,) = pair.getReserves();
        uint256 amountInWithFee = amountIn * 997;
        uint256 numerator = amountInWithFee * uint256(r1);
        uint256 denominator = (uint256(r0) * 1000) + amountInWithFee;
        uint256 amountOut = numerator / denominator;

        if (amountOut == 0 || amountOut >= r1) return;

        tokenA.mint(address(this), amountIn);
        tokenA.transfer(address(pair), amountIn);
        pair.swap(0, amountOut, address(this), "");

        (uint112 r0After, uint112 r1After,) = pair.getReserves();
        uint256 currentK = uint256(r0After) * uint256(r1After);
        require(currentK >= previousK, "k decreased in swap0");
        previousK = currentK;
    }

    function swap1(uint256 amountInRaw) public {
        uint256 amountIn = bound(amountInRaw, 1 ether, 50_000 ether);

        (uint112 r0, uint112 r1,) = pair.getReserves();
        uint256 amountInWithFee = amountIn * 997;
        uint256 numerator = amountInWithFee * uint256(r0);
        uint256 denominator = (uint256(r1) * 1000) + amountInWithFee;
        uint256 amountOut = numerator / denominator;

        if (amountOut == 0 || amountOut >= r0) return;

        tokenB.mint(address(this), amountIn);
        tokenB.transfer(address(pair), amountIn);
        pair.swap(amountOut, 0, address(this), "");

        (uint112 r0After, uint112 r1After,) = pair.getReserves();
        uint256 currentK = uint256(r0After) * uint256(r1After);
        require(currentK >= previousK, "k decreased in swap1");
        previousK = currentK;
    }
}
