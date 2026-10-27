# Post-Mortem Analysis & Reproducible PoC: Read-Only Reentrancy & Oracle Manipulation

**Author:** Arif Rahman  
**Date:** October 2026  
**Vulnerability Type:** Cross-Contract Read-Only Reentrancy / Oracle Price Inflation  
**Real-World Impact Incident:** Sentiment Protocol ($3.6M Drained, April 2023), Curve Finance StETH Pool Intermediary Oracle Incidents  
**Test Suite:** Foundry (`forge test --match-path "test/hack/*" -vv`)

---

## 1. Executive Summary

Read-only reentrancy is an insidious class of smart contract vulnerabilities where an attacker does **not** re-enter a state-modifying function of the vulnerable contract (which is typically shielded by OpenZeppelin's `nonReentrant` modifier). Instead, the attacker intercepts execution via a fallback hook (`receive()` or `fallback()`) while the contract is in an **inconsistent intermediate state**, and then calls a **third-party protocol** (such as a collateralized lending market or synthetics platform) that relies on a `view` or read-only function (like `getVirtualPrice()`) as a price oracle.

Because standard reentrancy guards only restrict functions bearing the `nonReentrant` modifier, `view` functions remain fully callable during state transitions. If internal balances are not updated before external calls (a violation of the *Checks-Effects-Interactions* pattern), the oracle returns an artificially inflated asset price, allowing the attacker to borrow 100% of the victim protocol's funds against worthless or minimal collateral.

---

## 2. Anatomy of the Vulnerability

### 2.1 The Flawed Liquidity Pool (`VulnerablePool.sol`)
In a typical AMM or liquidity pool, the "Virtual Price" represents the ratio of underlying assets to outstanding LP share tokens:

$$\text{Virtual Price} = \frac{\text{Total Underlying Reserves}}{\text{Total Supply of LP Tokens}}$$

In `VulnerablePool.sol`, the liquidity removal function was implemented as follows:

```solidity
function removeLiquidity(uint256 lpShares) external nonReentrant returns (uint256 ethAmount) {
    require(balanceOf(msg.sender) >= lpShares, "Insufficient LP");
    uint256 _totalSupply = totalSupply();
    ethAmount = (lpShares * totalEthReserves) / _totalSupply;

    // 1. Burn LP shares (Effects: totalSupply drops immediately!)
    _burn(msg.sender, lpShares);

    // 2. Interaction: Raw ETH transfer triggers attacker's receive() hook!
    (bool success, ) = msg.sender.call{value: ethAmount}("");
    require(success, "ETH transfer failed");

    // 3. Delayed State Update: totalEthReserves is updated AFTER the external call!
    totalEthReserves -= ethAmount;
}
```

### 2.2 The Inconsistent Intermediate State
When the external call to `msg.sender` executes:
* `totalSupply()` has already been reduced by 99%.
* `totalEthReserves` has **not** been updated yet.
* A call to `getVirtualPrice()` calculates:

$$\text{getVirtualPrice}() = \frac{\text{OLD totalEthReserves}}{\text{NEW (massively reduced) totalSupply}} \gg \text{Fair Market Value}$$

In our verified proof-of-concept, the virtual price surged from **1.0 ETH** to **50.5 ETH per LP share** (a **5,050% artificial inflation**).

---

## 3. Attack Execution Flow

```
Attacker              VulnerablePool            LendingMarket (Victim)
   |                        |                             |
   |--- 1. addLiquidity() ->|                             |
   |<-- receives 100 LP ----|                             |
   |                        |                             |
   |--- 2. depositCollateral(1 LP) ---------------------->|
   |                        |                             |
   |--- 3. removeLiquidity(99 LP)                         |
   |           |                                          |
   |           |-- burns 99 LP (totalSupply = 1 LP)       |
   |           |-- transfers 99 ETH                       |
   |           v                                          |
   |<-- receive() hook                                    |
   |        |                                             |
   |        |-- 4. borrow(50,000 USDC) ------------------>|
   |        |         |                                   |
   |        |         |-- queries getVirtualPrice() ---->| (Returns 50.5 ETH/LP!)
   |        |         |-- evaluates collateral: $101k    |
   |        |         |-- max borrow capacity: $80.8k     |
   |        |         |-- approves borrow $50k USDC       |
   |        |         v                                   |
   |        |<-- transfers 50,000 USDC -------------------|
   |        |                                             |
   |--------+                                             |
   |                                                      |
   | (removeLiquidity finishes, updates totalEthReserves) |
   v                                                      v
[Attacker walks away with 99 ETH + 50,000 USDC]       [Lending Market Drained]
```

---

## 4. Empirical Test Trace (Foundry Verification)

Executing the automated exploit suite with verbose logging (`forge test --match-path "test/hack/*" -vv`):

```bash
Ran 1 test for test/hack/ReadOnlyReentrancyPoC.t.sol:ReadOnlyReentrancyPoCTest
[PASS] test_ReproduceReadOnlyReentrancyDrain() (gas: 343757)
Logs:
  === BEFORE EXPLOIT ===
  Pool Total Reserves (ETH): 1
  Pool Virtual Price (ETH): 1
  Market USDC Liquidity: 50000
  Attacker USDC Balance: 0
  Attacker Initial ETH: 100
  === AFTER EXPLOIT ===
  Market USDC Liquidity Remaining: 0
  Attacker Plundered USDC: 50000
  Attacker Final ETH: 99

Suite result: ok. 1 passed; 0 failed; 0 skipped; finished in 5.54ms
```

### Numerical Breakdown:
1. **Initial State:**
   * Pool has 1 ETH reserves and 1 LP share ($P_{\text{virtual}} = 1.0\text{ ETH}$).
   * Lending Market holds **50,000 USDC** in available borrowing liquidity.
   * Attacker starts with 100 ETH.
2. **Setup:**
   * Attacker deposits 100 ETH into pool, receiving 100 LP shares (Total pool: 101 ETH, 101 LP shares).
   * Attacker deposits **1 LP share** into Lending Market as collateral.
3. **Trigger:**
   * Attacker initiates `removeLiquidity(99 LP)`.
   * Pool burns 99 LP shares. Pool `totalSupply` drops to $101 - 99 = 2$ LP.
   * Pool invokes raw `call{value: 99 ETH}` to Attacker contract.
4. **Exploitation inside `receive()` fallback:**
   * Attacker invokes `market.borrow(50_000 ether)`.
   * Lending Market evaluates collateral:
     $$\text{Virtual Price} = \frac{101\text{ ETH}}{2\text{ LP}} = 50.5\text{ ETH/LP}$$
     $$\text{Collateral Value in USD} = 1\text{ LP} \times 50.5\text{ ETH} \times \$2,000 = \$101,000\text{ USD}$$
     $$\text{Borrow Capacity (80% LTV)} = \$101,000 \times 0.8 = \$80,800\text{ USDC}$$
   * The requested 50,000 USDC borrow is approved and dispatched.
5. **Resolution:**
   * Attacker reclaims their 99 ETH from the pool withdrawal.
   * Total net profit: **+50,000 USDC** with near-zero capital loss.

---

## 5. Defense-in-Depth & Remediation Strategies

### Mitigation 1: Enforce Strict Checks-Effects-Interactions (CEI)
Never perform an external interaction (`transfer`, `call`) before all internal storage variables are synchronized:

```solidity
// CORRECT: Update storage BEFORE external call
_burn(msg.sender, lpShares);
totalEthReserves -= ethAmount; // <--- State finalized

(bool success, ) = msg.sender.call{value: ethAmount}("");
require(success, "ETH transfer failed");
```

### Mitigation 2: Read-Only Reentrancy Lock using Transient Storage (EIP-1153)
With the Ethereum Cancun upgrade, smart contracts can utilize cheap transient storage (`TSTORE` and `TLOAD`) to establish read-only reentrancy locks without incurring high SSTORE gas penalties:

```solidity
bytes32 private constant REENTRANCY_GUARD_SLOT = keccak256("reentrancy.guard");

modifier nonReentrantView() {
    assembly {
        if tload(REENTRANCY_GUARD_SLOT) {
            revert(0, 0) // Revert if view is queried while state modification is in progress
        }
    }
    _;
}

modifier nonReentrantWithLock() {
    assembly {
        if tload(REENTRANCY_GUARD_SLOT) { revert(0, 0) }
        tstore(REENTRANCY_GUARD_SLOT, 1)
    }
    _;
    assembly {
        tstore(REENTRANCY_GUARD_SLOT, 0)
    }
}
```

### Mitigation 3: Third-Party Protocol Defenses
Consumer protocols (like Lending Markets) should never trust a single raw on-chain spot query:
1. **TWAP (Time-Weighted Average Price):** Query TWAP prices that span over multiple blocks rather than instantaneous flash reserves.
2. **Oracle Sanity Bounds:** Compare oracle readings against external decentralized feeds (Chainlink Data Feeds) and revert if deviation exceeds 2-3%.
