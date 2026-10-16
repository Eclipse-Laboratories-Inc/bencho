# Security Audit Report

## Critical: Incorrect deposit amount transferred to treasury in EtherBridge

**File:** `smart-contracts/src/v1/EtherBridge.sol`  
**Function:** `deposit()` (line 101-131)

**Root Cause:**  
The deposit function converts the deposit amount from wei to lamports (line 113: `uint256 lamportAmount = amount / WEI_PER_GWEI`), stores this in `message.amount`, but then incorrectly uses this lamport value as the wei amount when transferring to the treasury (line 127: `call{value: message.amount}`). Since `message.amount` is in lamports (1e9 times smaller than wei), the actual transfer to treasury is only 1/1,000,000,000th of what it should be.

**Impact:**  
For a 1 ETH deposit (1e18 wei), only 1e9 wei (1 gwei) is actually locked in the treasury, leaving 999,999,999 gwei stuck in the EtherBridge contract. This breaks the fundamental invariant that deposited funds must be fully locked. Attackers can drain the treasury by withdrawing more than was actually locked, and legitimate users lose their funds.

**Recommendation:**  
Change line 127 to transfer the original `amount` in wei, not the converted lamport amount:
```solidity
(bool success,) = payable(address(treasury)).call{value: amount}("");
```

---

## Critical: Treasury re-initialization vulnerability

**File:** `smart-contracts/src/v1/EtherBridge.sol`, `smart-contracts/src/v1/Treasury.sol`  
**Function:** `EtherBridge.initialize()` (line 95)

**Root Cause:**  
The EtherBridge's `initialize()` function calls `treasury.initialize()` on line 95 after retrieving the Treasury address from the registry. However, the Treasury contract uses OpenZeppelin's `initializer` modifier which only prevents re-initialization from being called on the same proxy. If the Treasury is already initialized, but EtherBridge is redeployed or reinitialized, it will call `treasury.initialize()` again, which will execute `__Ownable_init(msg.sender)` and transfer ownership of the Treasury to the new EtherBridge contract instance.

**Impact:**  
If the EtherBridge contract is upgraded or reinitialized, it could steal ownership of the Treasury contract, allowing it to withdraw all locked funds. An attacker who can trigger a reinitialization (or a malicious upgrade) could drain all user deposits.

**Recommendation:**  
Remove the `treasury.initialize()` call from EtherBridge. The Treasury should be initialized separately during deployment, and EtherBridge should only reference it, never initialize it.

---

## Critical: Arbitrary contract call in Router without gas limit enforcement

**File:** `smart-contracts/src/v1/Router.sol`  
**Function:** `routeIncomingMessage()` (line 47-63)

**Root Cause:**  
Line 61 performs an arbitrary call to a module contract without proper gas limit enforcement: `(bool success,) = actualAddress.call(message);`. While the mailbox routing limits gas to `MIN_DEPOSIT_GAS_ONLY_ROUTING` (300k gas), the Router itself does not enforce any gas limits when calling module contracts, allowing all remaining gas to be forwarded.

**Impact:**  
A malicious or compromised module contract could consume all available gas, causing denial of service. More critically, the arbitrary call pattern combined with unlimited gas forwarding creates a reentrancy vector. Even with ReentrancyGuard on the Router, a malicious module could call back into other contracts in the system before the Router's reentrancy lock is released, potentially allowing cross-contract reentrancy attacks.

**Recommendation:**  
1. Implement explicit gas limits for module calls
2. Add return value validation for the external call
3. Consider using a try-catch pattern to handle failures gracefully
4. Document the expected interface that module contracts must implement

---

## Critical: Missing nonce replay protection in Solana deposit function

**File:** `eclipse-programs/programs/canonical_bridge/src/instructions/deposit.rs`  
**Function:** `deposit()` (line 29-57)

**Root Cause:**  
The deposit function creates a `DepositReceipt` account using the `eth_deposit_nonce` as part of the seed (line 16), but there is no verification that this nonce corresponds to an actual, valid Ethereum deposit event. The PDA creation will fail if the same nonce is reused (preventing replay), but there's no verification that the nonce is sequential or valid.

**Impact:**  
While Anchor's account initialization prevents the same nonce from being used twice, there is no guarantee that the nonce comes from a legitimate Ethereum deposit. The relayer could skip nonces or use nonces in any order. More critically, if the deposit fails after the receipt is created but before the transfer, the nonce is consumed but the user doesn't receive funds, and that deposit can never be retried.

**Recommendation:**  
1. Implement a sequential nonce counter to ensure deposits are processed in order
2. Add validation that the nonce hasn't been skipped
3. Consider implementing a two-phase commit pattern where receipt creation and fund transfer are atomic

---

## Critical: Missing relayer authorization check in Solana withdraw function

**File:** `eclipse-programs/programs/canonical_bridge/src/instructions/withdraw.rs`  
**Function:** `withdraw()` (line 31-75)

**Root Cause:**  
The withdraw function accepts a `relayer` account (line 26) but does not validate that this account matches the authorized `RELAYER_PUBKEY` constant. Unlike the deposit function which enforces `address = RELAYER_PUBKEY` on line 10 of deposit.rs, the withdraw function has no such constraint. Anyone can call withdraw and specify any account as the relayer.

**Impact:**  
Any user can call the withdraw function and receive their lamports back by transferring them to an arbitrary relayer address they control, without going through the legitimate bridging process. This breaks the bridge invariant that withdrawals must be authorized by cross-chain messages. Users can withdraw funds that were never properly deposited via Ethereum, draining the Solana side of the bridge.

**Recommendation:**  
Add the `address = RELAYER_PUBKEY` constraint to the relayer account in the Withdraw struct:
```rust
#[account(mut, address = RELAYER_PUBKEY)]
pub relayer: AccountInfo<'info>,
```

---

## High: Use of deprecated and predictable randomness source

**File:** `smart-contracts/src/v1/Mailbox.sol`  
**Function:** `generateRandomNonce()` (line 201-206)

**Root Cause:**  
Line 204 uses `block.difficulty` which was deprecated in favor of `block.prevrandao` after the Ethereum merge. More critically, even `block.prevrandao` can be manipulated by validators/miners to some extent, making it unsuitable as a source of randomness for security-critical operations like nonce generation.

**Impact:**  
Nonces generated using predictable block properties can be front-run or manipulated. An attacker who can predict the next nonce could potentially craft malicious messages with that nonce before legitimate messages, causing the legitimate messages to be rejected as duplicates. Validators can also influence `block.prevrandao` to some degree, potentially allowing them to cause nonce collisions.

**Recommendation:**  
1. Use a proper randomness source like Chainlink VRF for unpredictable nonces
2. Alternatively, use a combination of sender address, timestamp, and an incrementing counter that's guaranteed to be unique
3. Update to `block.prevrandao` as a minimum fix, but note it's still not cryptographically secure randomness

---

## High: Treasury uses transfer() which can fail with smart contract recipients

**File:** `smart-contracts/src/v1/Treasury.sol`  
**Function:** `withdraw()` (line 23-26)

**Root Cause:**  
Line 25 uses `transfer()` which forwards only 2300 gas. This is insufficient for recipients that are smart contracts with non-trivial fallback/receive functions. The 2300 gas stipend was designed to prevent reentrancy but is now considered an anti-pattern.

**Impact:**  
Withdrawals to smart contract addresses (like multi-sig wallets, contract-based wallets, or other protocols) will fail if their receive function requires more than 2300 gas. This locks funds in the Treasury permanently for those recipients. As gas costs change over time, even simple operations may exceed 2300 gas in future hard forks.

**Recommendation:**  
Replace `transfer()` with a low-level call and proper error handling:
```solidity
(bool success, ) = to.call{value: amount}("");
require(success, "Transfer failed");
```
The contract already has ReentrancyGuard protection via the owner (EtherBridge), so the 2300 gas limit is unnecessary.

---

## High: generateRandomNonce is public and callable by anyone

**File:** `smart-contracts/src/v1/Mailbox.sol`  
**Function:** `generateRandomNonce()` (line 201-206)

**Root Cause:**  
The `generateRandomNonce()` function is declared as `public` rather than `private` or `internal`, allowing anyone to call it and increment the `nonceCounter`. This was likely a mistake as external callers have no legitimate use for this function.

**Impact:**  
An attacker can repeatedly call `generateRandomNonce()` to increment the nonce counter, potentially causing it to overflow (though uint64 overflow requires 2^64 calls). More practically, incrementing the counter skips nonces, which could interfere with the bridge's ability to track and verify messages. If there's any code that expects sequential nonces, this could break message ordering.

**Recommendation:**  
Change the function visibility to `internal` or `private`:
```solidity
function generateRandomNonce() internal returns (uint64) {
```

---

## High: Registry unregisterContract fails to clean up contractType mapping

**File:** `smart-contracts/src/v1/Registry.sol`  
**Function:** `unregisterContract()` (line 39-48)

**Root Cause:**  
Lines 44-45 delete entries from `identifierAddress` and `addressIdentifier` mappings, but line 46 does not delete the corresponding entry from `addressContractType` mapping. This leaves stale contract type information in storage.

**Impact:**  
After unregistering a contract, `getContractType()` will still return the old contract type for that address instead of reverting. If a malicious contract is registered at that address later with a different identifier, it will inherit the previous contract's type. This could allow privilege escalation—for example, registering a malicious contract at an old MODULE address to gain module privileges.

**Recommendation:**  
Add cleanup of the contract type mapping:
```solidity
delete identifierAddress[identifier];
delete addressIdentifier[contractAddress];
delete addressContractType[contractAddress];  // Add this line
```

---

## High: No validation of withdrawal message authenticity in EtherBridge

**File:** `smart-contracts/src/v1/EtherBridge.sol`  
**Function:** `withdraw()` (line 137-151)

**Root Cause:**  
The withdraw function only checks that the caller is the router (via `onlyRouter` modifier) but does not verify that the withdrawal message actually originated from a legitimate cross-chain message. The function trusts that if the router calls it, the withdrawal is valid, but there's no cryptographic proof that the withdrawal was authorized on the Solana side.

**Impact:**  
If the router is compromised or has any vulnerability allowing arbitrary calls, an attacker could call `withdraw()` with fabricated `WithdrawMessage` data, draining the treasury without corresponding deposits or authorizations from the Solana side. The system has no way to verify the message came from a real Solana withdrawal transaction.

**Recommendation:**  
1. Implement signature verification of the withdrawal message, similar to how deposit messages are verified in Mailbox
2. Require proof of the Solana transaction (e.g., signature from the relayer over the withdrawal details)
3. Add nonce tracking for withdrawals to prevent replay attacks
4. Consider implementing a time-lock or multi-sig for large withdrawals

---

## Medium: Insufficient validation in Router.routeIncomingMessage

**File:** `smart-contracts/src/v1/Router.sol`  
**Function:** `routeIncomingMessage()` (line 47-63)

**Root Cause:**  
The function decodes an identifier from bytes (line 54) and looks up the corresponding address, but does not validate that the message payload is well-formed or that the identifier corresponds to a contract that expects this message format. The arbitrary call on line 61 forwards the raw message without any validation.

**Impact:**  
Malformed messages could cause unexpected behavior in module contracts. If a module contract doesn't properly validate its inputs, it could be exploited via crafted messages. The lack of standardized message format validation means each module must implement its own validation, increasing the attack surface.

**Recommendation:**  
1. Define and enforce a standard message format/schema
2. Validate message structure before routing
3. Consider implementing a message type registry
4. Add size limits to prevent excessive gas consumption

---

## Medium: Missing deposit fee transfer to relayer

**File:** `smart-contracts/src/v1/EtherBridge.sol`  
**Function:** `deposit()` (line 101-131)

**Root Cause:**  
Users pay a fee (line 101: `fee` parameter) which is included in `msg.value`, but the fee is never transferred to the relayer. Line 127 only transfers `message.amount` to the treasury. The fee remains in the EtherBridge contract balance but there's no mechanism to withdraw it or pay the relayer.

**Impact:**  
Relayers perform work processing deposits and withdrawals but receive no compensation. Fees accumulate in the EtherBridge contract with no way to extract them (no withdrawal function for the contract balance). This economically disincentivizes relayers from operating the bridge. The `getFeeBalance()` function can view the stuck fees but can't retrieve them.

**Recommendation:**  
1. Add a function to withdraw accumulated fees to the relayer address
2. Alternatively, transfer the fee directly to the relayer during deposit
3. Implement fee distribution logic in the withdraw flow as mentioned in the TODO comment on line 135

---

## Medium: Nonce collision risk across different users in Solana program

**File:** `eclipse-programs/programs/canonical_bridge/src/instructions/withdraw.rs`  
**Function:** `withdraw()` (line 31-75)

**Root Cause:**  
The withdrawal receipt PDA is derived using only the `withdrawal_nonce` (lines 18-20). There is no user-specific component in the seed, meaning all users share the same nonce space. If two users try to withdraw with the same nonce, the second will fail due to account collision.

**Impact:**  
The first user to use a particular nonce "claims" it, preventing any other user from using that nonce. Users must coordinate nonces off-chain to avoid collisions. In a bridge system, this could lead to transaction failures and poor user experience. A griefing attacker could front-run legitimate withdrawals by using their nonces first.

**Recommendation:**  
Include the user's public key in the PDA seed to ensure each user has their own nonce space:
```rust
seeds = [
    b"withdrawal",
    withdrawer.key().as_ref(),
    withdrawal_nonce.to_le_bytes().as_ref()
],
```

---

## Medium: No bounds checking on withdrawal nonce in Solana program

**File:** `eclipse-programs/programs/canonical_bridge/src/instructions/withdraw.rs`  
**Function:** `withdraw()` (line 31-75)

**Root Cause:**  
The `withdrawal_nonce` parameter is accepted without any validation that it's sequential or within expected bounds. Users can specify arbitrary nonces, and there's no central counter tracking the next expected nonce.

**Impact:**  
Users could skip nonces, use extremely large nonces, or use nonces in any arbitrary order. This makes it difficult to track which withdrawals have been processed and could complicate reconciliation between Ethereum and Solana. Nonce exhaustion attacks become possible where an attacker consumes large portions of the nonce space.

**Recommendation:**  
1. Implement a global withdrawal counter that increments sequentially
2. Validate that the provided nonce matches the expected next nonce
3. Alternatively, if out-of-order withdrawals are intentional, document this clearly and implement proper tracking

---

## Medium: Missing access control on EtherBridge.initialize

**File:** `smart-contracts/src/v1/EtherBridge.sol`  
**Function:** `initialize()` (line 81-96)

**Root Cause:**  
The initialize function is marked `external` with only the `initializer` modifier, which prevents double-initialization but does not restrict who can call it the first time. Anyone can call initialize if they deploy the contract or if it's deployed uninitialized.

**Impact:**  
If the contract is deployed as an implementation for a proxy but not immediately initialized, an attacker could front-run the legitimate initialization transaction and set themselves as the owner. While the `initializer` modifier prevents re-initialization, the first caller wins. This is a known vulnerability in upgradeable contract patterns.

**Recommendation:**  
1. Use a two-step initialization pattern where deployment and initialization are atomic
2. Add an access control check to ensure only a trusted deployer can initialize
3. Initialize in the same transaction as deployment
4. Consider using OpenZeppelin's `Initializable` with constructor initialization for the proxy

---

## Low: Inconsistent chain ID comparison allows mismatched lengths

**File:** `smart-contracts/src/v1/Mailbox.sol`  
**Modifiers:** `validEclipseChainId` (line 76-79), `validEthereumChainId` (line 82-85)

**Root Cause:**  
The modifiers cast both stored and provided chain IDs to `bytes32` and compare them. This padding/truncation behavior means that chain IDs of different lengths could potentially match if they align when padded/truncated. For example, the comparison `bytes32(chainId_) == bytes32(eclipseChainId)` will pass even if `chainId_` is shorter or longer than `eclipseChainId`, as long as the first 32 bytes match.

**Impact:**  
An attacker could potentially send messages with slightly malformed chain IDs that still pass validation. While the `chainIdMaxLength` modifier enforces a 32-byte maximum, it doesn't enforce minimum length or exact matching. This could allow messages with different chain ID representations to be accepted.

**Recommendation:**  
Compare the raw bytes without casting to ensure exact match:
```solidity
require(keccak256(chainId_) == keccak256(eclipseChainId), "Unsupported Eclipse chain id.");
```

---

## Low: Missing event emission for critical state changes

**File:** `smart-contracts/src/v1/Mailbox.sol`  
**Function:** `generateRandomNonce()` (line 201-206)

**Root Cause:**  
The nonce counter is incremented without emitting any event. Similarly, many critical operations like nonce updates in `receiveMessage` (line 145) and `mailOutgoingMessage` (line 164) don't emit standalone events for these state changes.

**Impact:**  
Off-chain monitoring systems cannot track nonce counter increments or detect anomalies in nonce generation. This makes it difficult to audit the system's behavior, detect attacks, or debug issues. Event logs are critical for cross-chain bridges to maintain transparency and auditability.

**Recommendation:**  
Add events for critical state changes:
```solidity
event NonceGenerated(uint64 indexed nonce);
event NonceConsumed(uint64 indexed nonce, bool isSend);
```

---

## Low: Solana deposit does not emit event for cross-chain tracking

**File:** `eclipse-programs/programs/canonical_bridge/src/instructions/deposit.rs`  
**Function:** `deposit()` (line 29-57)

**Root Cause:**  
The deposit function creates a receipt account but does not emit a log message that can be tracked by off-chain relayers. Unlike the withdraw function which calls `log_outbox_message()` on line 71, the deposit function has no equivalent logging.

**Impact:**  
Off-chain systems cannot easily monitor deposit completions on the Solana side. While the deposit receipt account can be queried, emitting events is a standard practice for cross-chain bridges to enable efficient monitoring. This makes it harder to build reliable relayer infrastructure.

**Recommendation:**  
Add an event emission similar to the withdraw function:
```rust
msg!("Deposit completed: nonce={}, amount={}, recipient={}", 
     eth_deposit_nonce, amount, to_account.key());
```

---

## Informational: Typo in error message

**File:** `smart-contracts/src/v1/EtherBridge.sol`  
**Line:** 32

**Root Cause:**  
Line 32 contains a typo: "deposite" should be "deposit" in the error message.

**Impact:**  
Minor user experience issue with unclear error messages.

**Recommendation:**  
Fix the typo:
```solidity
require(amount <= MAX_DEPOSIT_AMOUNT, "Deposit amount must be less than equal to the max deposit amount");
```

---

## Informational: Unused Rent sysvar in Solana deposit

**File:** `eclipse-programs/programs/canonical_bridge/src/instructions/deposit.rs`  
**Function:** `Deposit` struct (line 7-25)

**Root Cause:**  
Line 23 declares a `rent: Sysvar<'info, Rent>` account but it's never used in the deposit function. Anchor automatically handles rent exemption for accounts created with `init`, making this declaration unnecessary.

**Impact:**  
Minimal - slightly increases transaction size and cognitive overhead for developers reading the code. May cause confusion about why rent is being checked.

**Recommendation:**  
Remove the unused rent sysvar:
```rust
// Remove line 23
// rent: Sysvar<'info, Rent>,
```

