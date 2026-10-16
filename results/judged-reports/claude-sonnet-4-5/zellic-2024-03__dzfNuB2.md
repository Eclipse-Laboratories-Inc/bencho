# Security Audit Report

## Critical: Incorrect Deposit Amount Transferred to Treasury

**File:** `smart-contracts/src/v1/EtherBridge.sol`  
**Function:** `deposit()` (lines 101-131)

**Root Cause:**  
The deposit function converts the deposit amount to lamports (line 113: `lamportAmount = amount / WEI_PER_GWEI`) but then transfers `message.amount` (which is `lamportAmount`) as wei to the treasury (line 127). This transfers only 1 billionth of the intended amount.

**Impact:**  
Users deposit ether but only a tiny fraction (1/1,000,000,000th) is actually locked in the treasury. The bridge becomes insolvent as withdrawals will fail due to insufficient funds. This is a critical fund loss vulnerability.

**Recommendation:**  
Change line 127 to transfer the original `amount` parameter instead of `message.amount`:
```solidity
(bool success,) = payable(address(treasury)).call{value: amount}("");
```

## Critical: Unvalidated Withdrawal Amount in Solana Program

**File:** `eclipse-programs/programs/canonical_bridge/src/instructions/withdraw.rs`  
**Function:** `withdraw()` (lines 31-75)

**Root Cause:**  
The withdraw function accepts an `amount` parameter from the user (line 31) and transfers it from the withdrawer to the relayer (line 42) without validating that the user has equivalent funds locked on Ethereum. There's no cross-chain verification of the withdrawal legitimacy.

**Impact:**  
Users can withdraw arbitrary amounts from Eclipse without having deposited equivalent funds on Ethereum. This allows unlimited fund drainage from the relayer's account and breaks the bridge's 1:1 backing guarantee.

**Recommendation:**  
Implement a mechanism to verify that the withdrawal amount corresponds to a validated deposit on Ethereum, either through the relayer signature verification or merkle proof validation before allowing the transfer.

## Critical: Treasury Initialization Can Be Front-Run

**File:** `smart-contracts/src/v1/EtherBridge.sol`, `smart-contracts/src/v1/Treasury.sol`  
**Function:** `EtherBridge.initialize()` (line 95), `Treasury.initialize()` (line 13)

**Root Cause:**  
The EtherBridge contract calls `treasury.initialize()` on an already-deployed Treasury contract at line 95. However, `Treasury.initialize()` can be called by anyone (it only has the `initializer` modifier which prevents double-initialization, but not the first initialization). A front-runner can initialize the Treasury with themselves as owner before EtherBridge does.

**Impact:**  
An attacker can become the owner of the Treasury contract, allowing them to withdraw all deposited funds through `Treasury.withdraw()` which has `onlyOwner` access control. This results in complete fund theft.

**Recommendation:**  
Deploy the Treasury contract from within EtherBridge's initialize function using `new Treasury()` and initialize it atomically, or pass the intended owner address to `Treasury.initialize()` and validate it matches the expected caller.

## Critical: Weak Nonce Generation Enables Replay Attacks

**File:** `smart-contracts/src/v1/Mailbox.sol`  
**Function:** `generateRandomNonce()` (lines 201-206)

**Root Cause:**  
The function uses `block.difficulty` as an entropy source (line 204), which has been deprecated since The Merge and always returns 0 on post-merge Ethereum. Additionally, casting to `uint64` truncates the hash to 64 bits, significantly reducing the entropy space and increasing collision probability.

**Impact:**  
Predictable or colliding nonces enable replay attacks where an attacker can reuse the same nonce to replay messages. Combined with the relayer-controlled nonce values in `receiveMessage`, this could allow message replay across different contexts.

**Recommendation:**  
Replace `block.difficulty` with `block.prevrandao` and use a full uint256 for nonces, or implement a sequential counter-based nonce system. Also consider using Chainlink VRF or similar for cryptographically secure randomness if true randomness is required.

## Critical: Unvalidated Deposit Amount in Solana Program

**File:** `eclipse-programs/programs/canonical_bridge/src/instructions/deposit.rs`  
**Function:** `deposit()` (lines 29-57)

**Root Cause:**  
The deposit function accepts an `amount` parameter (line 32) and transfers it from the relayer to the recipient (line 43-54) without validating that this amount matches what was actually deposited on the Ethereum side. The relayer is trusted to provide the correct amount.

**Impact:**  
A compromised relayer can specify any amount in the deposit call, either crediting users with more funds than they deposited (draining the relayer's balance) or less (stealing user funds). This breaks the bridge's integrity.

**Recommendation:**  
Implement cryptographic verification (e.g., merkle proofs or signature over deposit details including amount) to ensure the relayer cannot arbitrarily modify the deposit amount.

## High: Missing Signature Prefix Enables Cross-Protocol Replay

**File:** `smart-contracts/src/v1/Mailbox.sol`  
**Function:** `receiveMessage()` (lines 138-139)

**Root Cause:**  
The signature verification at line 138-139 computes a raw keccak256 hash without the EIP-191 `"\x19Ethereum Signed Message:\n"` prefix. The hash is: `keccak256(abi.encodePacked(eclipseChainId_, sender_, message_, secParam.nonce))`.

**Impact:**  
Signatures can be replayed across different protocols or contracts that use the same signature scheme. An attacker might obtain a valid signature from another context (e.g., different contract, different chain) and replay it to this mailbox contract, bypassing intended authorization.

**Recommendation:**  
Use EIP-191 or EIP-712 structured data signing:
```solidity
bytes32 hash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", keccak256(abi.encodePacked(eclipseChainId_, sender_, message_, secParam.nonce))));
```

## High: Signature Malleability in ECDSA Verification

**File:** `smart-contracts/src/v1/Mailbox.sol`  
**Function:** `receiveMessage()` (line 139)

**Root Cause:**  
Using `ECDSA.recover()` directly is vulnerable to signature malleability. For any valid ECDSA signature (r, s, v), there exists another valid signature (r, -s mod n, v') that produces the same signer address. An attacker can modify the `s` value of a signature and create a different but equally valid signature.

**Impact:**  
While this doesn't bypass authentication (the recovered address is the same), it allows an attacker to create different signature values that verify correctly. This could interfere with nonce tracking or other mechanisms that rely on signature uniqueness, potentially enabling double-processing of messages.

**Recommendation:**  
Use OpenZeppelin's ECDSA library with proper malleability protection by checking that `s` is in the lower half of the curve order, or use the newer signature validation methods that include this check.

## High: Unsafe Use of transfer() for ETH Transfers

**File:** `smart-contracts/src/v1/Treasury.sol`  
**Function:** `withdraw()` (line 25)

**Root Cause:**  
The code uses `.transfer(amount)` which forwards only 2300 gas to the recipient. If the recipient is a contract with a fallback or receive function that consumes more than 2300 gas, the transfer will always fail, making funds permanently stuck.

**Impact:**  
Withdrawals to contracts with non-trivial receive logic will fail. Users' funds become permanently locked in the Treasury with no way to retrieve them, especially problematic for smart contract wallets or multi-sig contracts.

**Recommendation:**  
Replace `transfer()` with a low-level call and check the return value:
```solidity
(bool success, ) = to.call{value: amount}("");
require(success, "Transfer failed");
```

## High: Arbitrary External Call in Router

**File:** `smart-contracts/src/v1/Router.sol`  
**Function:** `routeIncomingMessage()` (line 61)

**Root Cause:**  
The router executes arbitrary calls to any address registered as a MODULE type: `(bool success,) = actualAddress.call(message)`. The `message` parameter is directly from the untrusted cross-chain message, and while the target is restricted to MODULE contracts, the calldata is completely controlled by the sender.

**Impact:**  
If any MODULE contract has a vulnerable function or unexpected behavior when called with attacker-controlled data, it could be exploited. The router effectively amplifies any vulnerability in any registered module. A malicious or compromised module registration could lead to arbitrary code execution.

**Recommendation:**  
Implement an interface that MODULE contracts must adhere to with a specific function signature, rather than allowing arbitrary calldata. Use proper interface calls instead of low-level `call()`:
```solidity
IModule(actualAddress).handleMessage(message);
```

## High: No Relayer Validation in Solana Withdraw

**File:** `eclipse-programs/programs/canonical_bridge/src/instructions/withdraw.rs`  
**Function:** `withdraw()` (lines 24-28, 42)

**Root Cause:**  
The `relayer` account in the Withdraw context is defined as `AccountInfo` with only a comment "CHECK: we transfer into this account" (lines 25-26). There's no validation that this is the authorized relayer pubkey. Users transfer funds to an arbitrary account specified in the transaction (line 42).

**Impact:**  
Users could specify any account as the "relayer", allowing funds to be sent to an attacker-controlled address instead of the legitimate relayer. This breaks the withdrawal flow and results in fund loss for users.

**Recommendation:**  
Add address validation to ensure the relayer matches the expected RELAYER_PUBKEY:
```rust
#[account(mut, address = RELAYER_PUBKEY)]
pub relayer: AccountInfo<'info>,
```

## Medium: Registry Allows Overwriting Contracts Without Validation

**File:** `smart-contracts/src/v1/Registry.sol`  
**Function:** `registerContract()` (lines 24-35)

**Root Cause:**  
The `registerContract` function allows overwriting existing registrations without any checks or warnings. A contract identifier can be reassigned to a different address, or an address can have its contract type changed from MODULE to ROUTER, etc.

**Impact:**  
Accidentally or maliciously overwriting a critical contract registration (e.g., changing the Mailbox address) would break the entire system. Contracts relying on registry lookups would suddenly interact with wrong contracts, leading to fund loss or system failure.

**Recommendation:**  
Add validation to prevent overwriting without explicit confirmation:
```solidity
require(identifierAddress[identifier] == address(0), "Contract already registered");
```
Or implement a separate `updateContract()` function with additional safeguards.

## Medium: Precision Loss in Wei to Lamport Conversion

**File:** `smart-contracts/src/v1/EtherBridge.sol`  
**Function:** `deposit()` (lines 113-114)

**Root Cause:**  
The conversion from wei to lamports uses integer division: `lamportAmount = amount / WEI_PER_GWEI`. Any deposit amount that is not an exact multiple of 1 gwei (1,000,000,000 wei) will lose the remainder.

**Impact:**  
Users lose small amounts of ether (up to 999,999,999 wei ≈ 0.000000001 ETH) on every deposit. While individually small, this adds up over many deposits. The lost wei remains in the contract balance without accounting, creating discrepancies.

**Recommendation:**  
Add a requirement that deposit amounts must be exact multiples of 1 gwei:
```solidity
require(amount % WEI_PER_GWEI == 0, "Amount must be a multiple of 1 gwei");
```
Or implement proper remainder handling.

## Medium: Registry Contract Type Orphaned on Unregister

**File:** `smart-contracts/src/v1/Registry.sol`  
**Function:** `unregisterContract()` (lines 39-48)

**Root Cause:**  
The unregister function deletes entries from `identifierAddress` and `addressIdentifier` mappings but does not delete from the `addressContractType` mapping (line 44-45 missing: `delete addressContractType[contractAddress]`).

**Impact:**  
After unregistering a contract, `getContractType()` will still return the old contract type for that address. If the address is later registered with a different identifier, it will have inconsistent type information, potentially causing validation bypasses.

**Recommendation:**  
Add deletion of contract type:
```solidity
delete addressContractType[contractAddress];
```

## Medium: Same Address Can Have Multiple Identifiers

**File:** `smart-contracts/src/v1/Registry.sol`  
**Function:** `registerContract()` (lines 24-35)

**Root Cause:**  
When registering a new identifier for an address that's already registered, the `addressIdentifier` mapping is overwritten (line 32) but the old identifier's mapping remains in `identifierAddress`. This creates a one-to-many relationship where one address maps to multiple identifiers.

**Impact:**  
This creates inconsistent state where `getAddress(oldIdentifier)` returns address X, but `getIdentifier(X)` returns the new identifier, not the old one. This violates the expected bijection and could cause routing errors.

**Recommendation:**  
Before registering, check if the address is already registered and clear the old identifier:
```solidity
string memory existingId = addressIdentifier[contractAddress];
if (bytes(existingId).length != 0) {
    delete identifierAddress[existingId];
}
```

## Medium: Fixed Gas Limit May Cause Routing Failures

**File:** `smart-contracts/src/v1/EtherBridge.sol`  
**Function:** `deposit()` (line 124)

**Root Cause:**  
The routing call has a hardcoded gas limit: `router.routeOutgoingMessage{gas: MIN_DEPOSIT_GAS_ONLY_ROUTING}(encodedMessage)` where `MIN_DEPOSIT_GAS_ONLY_ROUTING = 300_000`. If the routing logic becomes more complex or needs to interact with other contracts, this fixed limit could be insufficient.

**Impact:**  
Deposits could fail if routing requires more than 300,000 gas, locking user funds in the contract with no way to recover them. The transaction would revert after already receiving the user's ether.

**Recommendation:**  
Either increase the gas limit significantly, make it configurable by the owner, or remove the gas limit restriction and let it use all available gas.

## Medium: No Event Emission in Treasury Withdrawals

**File:** `smart-contracts/src/v1/Treasury.sol`  
**Function:** `withdraw()` (lines 23-26)

**Root Cause:**  
The withdraw function transfers funds but doesn't emit any event to log this action. This makes it difficult to track when and how much ether leaves the treasury.

**Impact:**  
Off-chain monitoring and auditing of treasury movements is difficult. Users and auditors cannot easily verify that withdrawals match expected cross-chain bridge operations. This reduces transparency and makes fraud detection harder.

**Recommendation:**  
Add an event and emit it:
```solidity
event Withdrawn(address indexed to, uint256 amount);
...
emit Withdrawn(to, amount);
```

## Medium: Hardcoded Relayer in Solana Program

**File:** `eclipse-programs/programs/canonical_bridge/src/lib.rs`  
**Function:** N/A (constants, line 11)

**Root Cause:**  
The relayer public key is hardcoded as a constant: `pub const RELAYER_PUBKEY: Pubkey = pubkey!("ec1vCnQKsQSnTbcTyc3SH2azcDXZquiFB3QqtRvm3Px")`. If this relayer's private key is compromised or needs to be rotated for operational reasons, the entire program must be upgraded.

**Impact:**  
If the relayer is compromised, there's no quick way to revoke its access. The attack window extends until a program upgrade can be deployed and executed. Additionally, routine key rotation (a security best practice) becomes extremely difficult.

**Recommendation:**  
Store the relayer pubkey in a program-owned account that can be updated by an admin authority, allowing relayer rotation without full program upgrade.

## Low: Unused Fee Amount Accumulates in EtherBridge

**File:** `smart-contracts/src/v1/EtherBridge.sol`  
**Function:** `deposit()` (lines 101-131)

**Root Cause:**  
The deposit function collects a fee (line 102) which remains in the EtherBridge contract (line 127 only transfers the deposit amount to treasury, not the fee). There's no mechanism to withdraw or utilize these accumulated fees, as shown by `getFeeBalance()` at line 162.

**Impact:**  
Fees accumulate indefinitely in the EtherBridge contract with no way to extract them. While not directly exploitable, this is poor fund management and the fees could eventually be lost if the contract is upgraded or deprecated.

**Recommendation:**  
Implement an owner-controlled function to withdraw accumulated fees for operational expenses or relayer compensation.

## Low: No Validation of Nonce Sequentiality

**File:** `smart-contracts/src/v1/Mailbox.sol`  
**Function:** `receiveMessage()` (lines 118-151)

**Root Cause:**  
The receive nonce validation only checks that a nonce hasn't been used before (line 136: `require(receiveNonces[secParam.nonce] == false)`). The relayer can choose to submit messages with nonces in any order, skip nonces, or use extremely high nonce values.

**Impact:**  
While duplicate prevention works correctly, non-sequential nonces make it harder to detect if messages are missing or being withheld by the relayer. Monitoring for censorship or message delays becomes more difficult.

**Recommendation:**  
Consider implementing sequential nonce validation or ranges to ensure messages are processed in order, unless out-of-order processing is a deliberate design choice.

## Informational: Withdrawal Nonce Can Be User-Selected

**File:** `eclipse-programs/programs/canonical_bridge/src/instructions/withdraw.rs`  
**Function:** `withdraw()` (lines 9-29)

**Root Cause:**  
The withdrawal nonce is provided by the user as a parameter (line 9) and used as a seed for the PDA (lines 17-20). While the `init` constraint ensures uniqueness, users control which nonce values are used.

**Impact:**  
Users could intentionally choose nonces to create specific PDA addresses, potentially for vanity addresses or to interfere with off-chain indexing systems that assume sequential nonces. This doesn't directly break security but could complicate monitoring.

**Recommendation:**  
Consider using a program-controlled sequential counter for withdrawal nonces rather than user-provided values to ensure predictability and simplify tracking.

## Informational: Missing Input Validation for Chain IDs

**File:** `smart-contracts/src/v1/Mailbox.sol`  
**Function:** `initialize()` (lines 98-115)

**Root Cause:**  
The initialize function accepts `_ethereumChainId` and `_eclipseChainId` as bytes with only a maximum length check (modifier `chainIdMaxLength` ensures ≤32 bytes). There's no validation that these are non-empty or properly formatted.

**Impact:**  
Empty chain IDs could be set, which would cause all chain validation modifiers to pass incorrectly since `bytes32(bytes("")) == bytes32(0)` could match any empty chain ID. This could lead to accepting messages from unintended chains.

**Recommendation:**  
Add validation to ensure chain IDs are non-empty:
```solidity
require(_ethereumChainId.length > 0, "Ethereum chain ID cannot be empty");
require(_eclipseChainId.length > 0, "Eclipse chain ID cannot be empty");
```
