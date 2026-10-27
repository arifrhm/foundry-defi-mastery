# Foundry DeFi Mastery & Core Blockchain Primitives

[![Foundry](https://img.shields.io/badge/Foundry-v1.8.6-blue.svg)](https://getfoundry.sh/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Solidity](https://img.shields.io/badge/Solidity-0.8.26-363636.svg)](https://soliditylang.org/)

An advanced, production-grade sandbox and engineering repository implementing fundamental Web3 & DeFi primitives from scratch, backed by comprehensive Foundry test suites including **1,000-run property-based fuzzing**, **stateful invariant testing**, **EIP-712 cryptographic signatures**, **Chainlink Automation**, and a **fully reproducible real-world DeFi hack exploit PoC**.

---

## 🏛️ Repository Architecture

```
foundry-defi-mastery/
├── src/
│   ├── amm/
│   │   ├── MiniPairV2.sol               # Production Uniswap v2 constant product AMM (x * y = k)
│   │   └── ConcentratedSimulator.sol    # Uniswap v3 virtual reserves & capital efficiency engine
│   ├── vault/
│   │   └── YieldVault4626.sol           # ERC-4626 Tokenized Vault with EIP-712 & Chainlink Automation
│   └── hack/
│       ├── VulnerablePool.sol           # Flawed pool demonstrating Read-Only Reentrancy
│       ├── LendingMarket.sol            # Victim lending protocol using pool virtual price as oracle
│       └── Exploiter.sol                # Attacker smart contract triggering the flash drain
├── test/
│   ├── amm/
│   │   ├── MiniPairV2.t.sol             # Unit tests (minting, swapping, burning, TWAP)
│   │   ├── MiniPairV2Fuzz.t.sol         # Property-based fuzz test (1000 runs on invariant k)
│   │   ├── MiniPairV2Handler.sol        # Stateful invariant actor handler
│   │   └── MiniPairV2Invariant.t.sol    # Invariant testing (k non-decreasing, reserve coverage)
│   ├── vault/
│   │   └── YieldVault4626.t.sol         # EIP-712 permit signatures & Chainlink keeper tests
│   └── hack/
│       └── ReadOnlyReentrancyPoC.t.sol  # 100% reproducible exploit PoC draining $50,000 USDC
└── docs/
    └── post-mortem-read-only-reentrancy.md # Full technical post-mortem analysis & EIP-1153 fix
```

---

## ⚡ Module 1: Constant Product AMM (Uniswap v2) & Concentrated Liquidity Simulator

### Core Features
* **`MiniPairV2.sol`**:
  * Implements the foundational invariant: $(x + \Delta x \cdot 0.997)(y - \Delta y) \ge x \cdot y$.
  * Minimum liquidity lock ($1,000$ wei permanently burned to `0x...dead`) to neutralize first-depositor inflation attacks.
  * UQ112x112 cumulative time-weighted price accumulators (`price0CumulativeLast`, `price1CumulativeLast`) for on-chain TWAP.
* **`ConcentratedSimulator.sol`**:
  * Simulates virtual reserves and liquidity density ($L$) within tick ranges $[P_a, P_b]$.
  * Implements theoretical capital efficiency formula:
    $$C_{\text{eff}} = \frac{1}{1 - \sqrt{\frac{P_a}{P_b}}}$$
  * Demonstrates that for a $\pm 10\%$ peg band ($[0.9, 1.1]$), concentrated liquidity achieves **$>10\times$ higher capital efficiency** than v2.

### Testing Rigor
* **Fuzzing (1,000 runs)**: Validates that for any arbitrary trade input ($1\text{ wei}$ to $100,000\text{ ether}$), $k_{\text{after}} \ge k_{\text{before}}$.
* **Stateful Invariant Testing (16,384 calls across 256 runs)**: Randomly exercises `swap0` and `swap1` sequences across arbitrary actors, asserting that token balances always cover reserves and $k$ never dips below the baseline.

---

## 🏦 Module 2: ERC-4626 Vault with EIP-712 & Chainlink Automation

### Core Features
* **`YieldVault4626.sol`**:
  * Full compliance with the **ERC-4626 Tokenized Vault Standard**.
  * **EIP-712 Cryptographic Signature Delegated Deposit**: Users sign a gasless off-chain authorization message (`DepositPermit`). Relayers or keepers can submit the transaction on-chain with zero gas cost to the user.
  * **Chainlink Automation**: Implements `AutomationCompatibleInterface` (`checkUpkeep` and `performUpkeep`). Automatically evaluates whether the compounding harvest window (e.g. 1 day) has elapsed, auto-compounding yields to drive up the share exchange rate.

---

## 💥 Module 3: Read-Only Reentrancy Exploit PoC & Post-Mortem

### The Scenario
Reproduces the architectural vulnerability responsible for historical multi-million dollar hacks (such as the **Sentiment Protocol $3.6M exploit**).

1. The pool protects state-changing methods with `nonReentrant`, but exposes an unprotected read-only view function (`getVirtualPrice()`).
2. Inside `removeLiquidity()`, LP shares are burned **before** the ETH transfer, and internal reserves are updated **after** the external transfer.
3. During the `receive()` callback, the pool's virtual price is artificially inflated by **5,050%**.
4. The attacker re-enters an external lending market that uses `getVirtualPrice()` as a price feed, borrowing **100% of the victim's USDC liquidity ($50,000 USDC)** against 1 LP token.

Detailed post-mortem analysis and remediation available in [`docs/post-mortem-read-only-reentrancy.md`](docs/post-mortem-read-only-reentrancy.md).

---

## 🚀 Running the Sandbox Locally

### Prerequisites
* [Foundry](https://getfoundry.sh/) (`forge`, `cast`, `anvil`)

```bash
# Clone the repository
git clone https://github.com/arifrhm/foundry-defi-mastery.git
cd foundry-defi-mastery

# Run all test suites
forge test -vv

# Run AMM Fuzzing suite (1000 runs)
forge test --match-path "test/amm/MiniPairV2Fuzz.t.sol"

# Run Stateful Invariant test
forge test --match-path "test/amm/MiniPairV2Invariant.t.sol"

# Run EIP-712 & Chainlink Vault tests
forge test --match-path "test/vault/*"

# Run Read-Only Reentrancy Hack PoC
forge test --match-path "test/hack/*" -vv
```

---

## 🧪 Test Execution Results

```
Ran 3 test suites:
[PASS] testBurnLiquidity() (gas: 383720)
[PASS] testConcentratedLiquidityCapitalEfficiency() (gas: 10180)
[PASS] testInitialLiquidityMint() (gas: 276110)
[PASS] testSwapExecutionWithFee() (gas: 383688)
[PASS] testFuzz_SwapInvariantKNeverDecreases(uint256) (runs: 1000, μ: 117976, ~: 121787)
[PASS] invariant_KNeverBelowInitialBase (runs: 256, calls: 16384, reverts: 0)
[PASS] invariant_PairReservesMatchOrCoverBalances (runs: 256, calls: 16384, reverts: 0)
[PASS] testChainlinkAutomation_CheckAndPerformUpkeep() (gas: 214106)
[PASS] testEIP712_DepositWithSignature() (gas: 233546)
[PASS] testStandardDepositAndRedeem() (gas: 195466)
[PASS] test_ReproduceReadOnlyReentrancyDrain() (gas: 343757)

Suite result: ok. 11 passed; 0 failed; 0 skipped (100% Pass Rate)
```

---

## 📜 License
MIT License. Crafted for high-standard smart contract engineering and security research.
