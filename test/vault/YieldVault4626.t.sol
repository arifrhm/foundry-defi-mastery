// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {YieldVault4626} from "../../src/vault/YieldVault4626.sol";
import {MockERC20} from "../mocks/MockERC20.sol";

contract YieldVault4626Test is Test {
    YieldVault4626 internal vault;
    MockERC20 internal asset;

    uint256 internal alicePrivateKey = 0xA11CE;
    address internal alice;
    address internal bob = address(0xB0B);
    address internal keeper = address(0x9999);

    bytes32 internal constant DEPOSIT_PERMIT_TYPEHASH = keccak256(
        "DepositPermit(address owner,address receiver,uint256 assets,uint256 nonce,uint256 deadline)"
    );

    function setUp() public {
        alice = vm.addr(alicePrivateKey);
        asset = new MockERC20("Underlying USD", "USDx");
        vault = new YieldVault4626(asset, "Vault USDx Share", "vUSDx", keeper);

        asset.mint(alice, 100_000 ether);
        asset.mint(bob, 100_000 ether);

        vm.prank(alice);
        asset.approve(address(vault), type(uint256).max);
        vm.prank(bob);
        asset.approve(address(vault), type(uint256).max);
    }

    function testStandardDepositAndRedeem() public {
        vm.prank(alice);
        uint256 shares = vault.deposit(1000 ether, alice);

        assertEq(shares, 1000 ether);
        assertEq(vault.totalAssets(), 1000 ether);
        assertEq(vault.balanceOf(alice), 1000 ether);

        vm.prank(alice);
        uint256 assetsWithdrawn = vault.redeem(shares, alice, alice);

        assertEq(assetsWithdrawn, 1000 ether);
        assertEq(vault.totalAssets(), 0);
    }

    function testEIP712_DepositWithSignature() public {
        uint256 assetsToDeposit = 500 ether;
        uint256 deadline = block.timestamp + 1 hours;
        uint256 nonce = vault.nonces(alice);

        // Construct EIP-712 typed digest
        bytes32 structHash = keccak256(
            abi.encode(
                DEPOSIT_PERMIT_TYPEHASH,
                alice,
                bob, // Alice deposits, Bob receives vault shares
                assetsToDeposit,
                nonce,
                deadline
            )
        );

        // Derive domain separator from contract
        bytes32 domainSeparator = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes("YieldVault4626")),
                keccak256(bytes("1")),
                block.chainid,
                address(vault)
            )
        );

        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));

        // Sign digest with Alice's private key
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(alicePrivateKey, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        // Relayer (Bob or keeper) submits transaction on-chain
        vm.prank(bob);
        uint256 sharesMinted = vault.depositWithSignature(alice, bob, assetsToDeposit, deadline, signature);

        assertEq(sharesMinted, assetsToDeposit);
        assertEq(vault.balanceOf(bob), assetsToDeposit);
        assertEq(vault.nonces(alice), 1); // Nonce incremented

        // Attempting to replay same signature must revert
        vm.expectRevert();
        vm.prank(bob);
        vault.depositWithSignature(alice, bob, assetsToDeposit, deadline, signature);
    }

    function testChainlinkAutomation_CheckAndPerformUpkeep() public {
        // Alice deposits assets into vault
        vm.prank(alice);
        vault.deposit(10_000 ether, alice);

        // Check upkeep initially (should be false because time elapsed < 1 day)
        (bool upkeepNeededBefore,) = vault.checkUpkeep("");
        assertFalse(upkeepNeededBefore);

        // Warp time forward by 1 day + 1 second
        vm.warp(block.timestamp + 1 days + 1);

        // Now upkeep must be due
        (bool upkeepNeededAfter,) = vault.checkUpkeep("");
        assertTrue(upkeepNeededAfter);

        // Keeper executes performUpkeep
        vm.prank(keeper);
        vault.performUpkeep("");

        // Upkeep reset
        (bool upkeepNeededFinal,) = vault.checkUpkeep("");
        assertFalse(upkeepNeededFinal);
    }
}
