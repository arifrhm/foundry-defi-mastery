// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {MiniPairV2} from "../../src/amm/MiniPairV2.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {MiniPairV2Handler} from "./MiniPairV2Handler.sol";

contract MiniPairV2InvariantTest is Test {
    MiniPairV2 internal pair;
    MockERC20 internal tokenA;
    MockERC20 internal tokenB;
    MiniPairV2Handler internal handler;

    function setUp() public {
        tokenA = new MockERC20("Token A", "TKNA");
        tokenB = new MockERC20("Token B", "TKNB");

        if (address(tokenA) > address(tokenB)) {
            (tokenA, tokenB) = (tokenB, tokenA);
        }

        pair = new MiniPairV2(address(tokenA), address(tokenB));

        // Initial liquidity
        tokenA.mint(address(this), 1_000_000 ether);
        tokenB.mint(address(this), 1_000_000 ether);
        tokenA.transfer(address(pair), 1_000_000 ether);
        tokenB.transfer(address(pair), 1_000_000 ether);
        pair.mint(address(this));

        handler = new MiniPairV2Handler(pair, tokenA, tokenB);

        bytes4[] memory selectors = new bytes4[](2);
        selectors[0] = MiniPairV2Handler.swap0.selector;
        selectors[1] = MiniPairV2Handler.swap1.selector;

        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    /// @notice Invariant: Token balances in pair must strictly equal or exceed recorded reserves
    function invariant_PairReservesMatchOrCoverBalances() public view {
        (uint112 r0, uint112 r1,) = pair.getReserves();
        assertGe(tokenA.balanceOf(address(pair)), uint256(r0));
        assertGe(tokenB.balanceOf(address(pair)), uint256(r1));
    }

    /// @notice Invariant: Product of reserves (k) must never be lower than initial base k
    function invariant_KNeverBelowInitialBase() public view {
        (uint112 r0, uint112 r1,) = pair.getReserves();
        uint256 currentK = uint256(r0) * uint256(r1);
        uint256 initialK = 1_000_000 ether * 1_000_000 ether;
        assertGe(currentK, initialK);
    }
}
