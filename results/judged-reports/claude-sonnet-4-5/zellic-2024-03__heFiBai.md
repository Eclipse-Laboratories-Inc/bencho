# Security Audit Report

## Critical: Arbitrary External Call Without Gas Limit in Router

**File:** `smart-contracts/src/v1/Router.sol`  
**Function:** `routeIncomingMessage` (line 47-63)

**Root Cause:**  
The router performs an arbitrary low-level call to a module contract without specifying a gas limit:
```solidity
(bool success,) = actualAddress.call(message);
require(success, "External call failed");
```

**Impact:**  
An attacker can craft a malicious module contract that consumes all available gas, causing a denial of service. Additionally, this enables arbitrary code execution with all remaining gas, which could be used to perform complex attacks including reentrancy (though ReentrancyGuard is present on the router itself, the called contract may have vulnerabilities).

**Recommendation:**  
Add an explicit gas limit to the call or use a safer pattern:
```solidity
(bool success,) = actualAddress.call{gas: gaslimit}(message);
```

## High: Public Function Allows Nonce Manipulation

**File:** `smart-contracts/src/v1/Mailbox.sol`  
**Function:** `generateRandomNonce` (line 201-206)

**Root Cause:**  
The `generateRandomNonce()` function is declared as `public` instead of `internal` or `private`. This allows anyone to call it and increment the `nonceCounter`, manipulating the internal state used for generating nonces.

**Impact:**  
An attacker can repeatedly call this function to advance the nonce counter, potentially causing legitimate nonce generation to produce predictable values or exhaust the nonce space. This could interfere with message sending operations and make the system vulnerable to nonce-based attacks.

**Recommendation:**  
Change the visibility to `internal` or `private`:
```solidity
function generateRandomNonce() internal returns (uint64) {
```

## High: Use of Deprecated block.difficulty

**File:** `smart-contracts/src/v1/Mailbox.sol`  
**Function:** `generateRandomNonce` (line 204)

**Root Cause:**  
The code uses `block.difficulty` as a source of randomness:
```solidity
uint256 largeNonce = uint256(keccak256(abi.encodePacked(block.timestamp, block.difficulty, msg.sender, nonceCounter)));
```

**Impact:**  
On Ethereum's Proof-of-Stake network (post-merge), `block.difficulty` has been replaced with `prevrandao`. While the opcode still exists for backwards compatibility, using `block.difficulty` is deprecated and may not provide the intended randomness. This weakens the unpredictability of nonces.

**Recommendation:**  
Replace `block.difficulty` with `block.prevrandao`:
```solidity
uint256 largeNonce = uint256(keccak256(abi.encodePacked(block.timestamp, block.prevrandao, msg.sender, nonceCounter)));
```

## High: Treasury Re-initialization Vulnerability

**File:** `smart-contracts/src/v1/EtherBridge.sol`  
**Function:** `initialize` (line 95)

**Root Cause:**  
The EtherBridge initialization calls `treasury.initialize()` on an already deployed Treasury contract without checking if it's already initialized:
```solidity
address payable treasuryAddress = payable(registry.getAddress("Treasury"));
treasury = Treasury(treasuryAddress);
treasury.initialize();
```

**Impact:**  
If the Treasury contract is already initialized (which it likely is if it's been deployed and registered), this call will revert due to the `initializer` modifier, causing the entire EtherBridge initialization to fail. This prevents the bridge from being properly set up. Additionally, if the Treasury somehow isn't initialized, calling `initialize()` from EtherBridge would make the EtherBridge contract the owner of the Treasury, not the intended owner.

**Recommendation:**  
Remove the `treasury.initialize()` call from EtherBridge. The Treasury should be initialized separately during deployment:
```solidity
address payable treasuryAddress = payable(registry.getAddress("Treasury"));
treasury = Treasury(treasuryAddress);
// Remove: treasury.initialize();
```

## High: Missing Relayer Validation in Solana Withdraw

**File:** `eclipse-programs/programs/canonical_bridge/src/instructions/withdraw.rs`  
**Function:** `withdraw` (line 31-75)

**Root Cause:**  
The withdraw instruction accepts a relayer account but does not validate that it matches the expected `RELAYER_PUBKEY`:
```rust
#[account(mut)]
/// CHECK: we transfer into this account
pub relayer: AccountInfo<'info>,
```

**Impact:**  
A malicious user could specify any account as the "relayer" recipient, effectively allowing them to redirect withdrawal fees to an arbitrary address. This bypasses the intended fee mechanism where the legitimate relayer should receive compensation for processing withdrawals.

**Recommendation:**  
Add a constraint to validate the relayer address:
```rust
#[account(mut, address = RELAYER_PUBKEY)]
pub relayer: AccountInfo<'info>,
```

## Medium: Incomplete Cleanup in Registry Unregistration

**File:** `smart-contracts/src/v1/Registry.sol`  
**Function:** `unregisterContract` (line 39-48)

**Root Cause:**  
When unregistering a contract, the function deletes entries from `identifierAddress` and `addressIdentifier` mappings but fails to delete the entry from `addressContractType`:
```solidity
delete identifierAddress[identifier];
delete addressIdentifier[contractAddress];
// Missing: delete addressContractType[contractAddress];
```

**Impact:**  
After unregistration, the contract address still has an associated contract type in storage. This creates an inconsistent state where `getContractType()` would still return a value for an unregistered address, potentially causing logic errors in contracts that check contract types. An attacker could exploit this to make contracts believe an unregistered address is still a valid module/router/mailbox.

**Recommendation:**  
Add cleanup for the contract type mapping:
```solidity
delete addressContractType[contractAddress];
```

## Medium: Use of transfer() Can Cause Withdrawal Failures

**File:** `smart-contracts/src/v1/Treasury.sol`  
**Function:** `withdraw` (line 23-26)

**Root Cause:**  
The withdrawal function uses `transfer()` to send Ether:
```solidity
to.transfer(amount);
```

**Impact:**  
The `transfer()` function forwards only 2300 gas, which is insufficient if the recipient is a contract with a non-trivial `receive()` or `fallback()` function. This can cause legitimate withdrawals to fail, locking funds in the Treasury. Since EIP-1884 increased the gas cost of SLOAD, even simple recipient contracts may fail.

**Recommendation:**  
Use `call` with proper error handling and reentrancy protection (already present via onlyOwner):
```solidity
(bool success, ) = to.call{value: amount}("");
require(success, "Transfer failed");
```

## Medium: Hash Collision Risk with abi.encodePacked

**File:** `smart-contracts/src/v1/Mailbox.sol`  
**Function:** `receiveMessage` (line 138)

**Root Cause:**  
The signature verification uses `abi.encodePacked` for hashing:
```solidity
bytes32 hash = keccak256(abi.encodePacked(eclipseChainId_, sender_, message_, secParam.nonce));
```

**Impact:**  
`abi.encodePacked` can lead to hash collisions when encoding dynamic types like bytes. For example, `abi.encodePacked(bytes("ab"), bytes("c"))` produces the same result as `abi.encodePacked(bytes("a"), bytes("bc"))`. An attacker could potentially craft messages that produce the same hash despite having different semantic meanings.

**Recommendation:**  
Use `abi.encode` instead for unambiguous encoding:
```solidity
bytes32 hash = keccak256(abi.encode(eclipseChainId_, sender_, message_, secParam.nonce));
```

## Medium: Incorrect Fund Transfer in Deposit

**File:** `smart-contracts/src/v1/EtherBridge.sol`  
**Function:** `deposit` (line 127-128)

**Root Cause:**  
When depositing, the contract sends `message.amount` (in lamports/gwei) to the treasury instead of the original `amount` (in wei):
```solidity
uint256 lamportAmount = amount / WEI_PER_GWEI;
// ...
(bool success,) = payable(address(treasury)).call{value: message.amount}("");
```

**Impact:**  
The treasury receives significantly less funds than intended. For example, a deposit of 1.5 ether (1,500,000 gwei) would only transfer 1,500,000 wei (0.0000015 ether) to the treasury. The remaining ~1.4999985 ether stays in the EtherBridge contract as "fees" even though the full amount should be in the treasury. Users lose the majority of their deposited funds.

**Recommendation:**  
Send the original `amount` to the treasury:
```solidity
(bool success,) = payable(address(treasury)).call{value: amount}("");
```

## Medium: Missing Withdrawal Nonce Validation in Solana

**File:** `eclipse-programs/programs/canonical_bridge/src/instructions/withdraw.rs`  
**Function:** `withdraw` (line 31-75)

**Root Cause:**  
The withdrawal function creates a receipt with a user-provided `withdrawal_nonce` but doesn't validate it against any stored state. While the PDA derivation uses the nonce as a seed (preventing duplicate nonces via the `init` constraint), there's no validation that this nonce corresponds to an actual bridge message from Ethereum.

**Impact:**  
A user could initiate withdrawals with arbitrary nonces without a corresponding deposit or authorization from Ethereum. While the funds come from the user's own account, this breaks the bridge's accounting and could lead to inconsistent state between Eclipse and Ethereum.

**Recommendation:**  
Implement a mechanism to validate that the withdrawal nonce corresponds to an authorized bridge message, either through signature verification or by checking against a list of valid nonces received from the Ethereum side.

## Low: Hardcoded Gas Limit May Be Insufficient

**File:** `smart-contracts/src/v1/EtherBridge.sol`  
**Function:** `deposit` (line 124)

**Root Cause:**  
The deposit function uses a hardcoded gas limit when routing the message:
```solidity
router.routeOutgoingMessage{gas: MIN_DEPOSIT_GAS_ONLY_ROUTING}(encodedMessage);
```

**Impact:**  
If the routing logic or mailbox operations become more complex in the future (e.g., due to upgrades), the hardcoded 300,000 gas limit may become insufficient, causing all deposits to fail. Conversely, if operations become more efficient, this wastes gas.

**Recommendation:**  
Either remove the gas limit and let the call use all available gas (with appropriate safety measures), or make the gas limit configurable:
```solidity
router.routeOutgoingMessage(encodedMessage);
```

## Low: No Amount Validation in Solana Deposit

**File:** `eclipse-programs/programs/canonical_bridge/src/instructions/deposit.rs`  
**Function:** `deposit` (line 29-57)

**Root Cause:**  
The deposit function accepts an `amount` parameter but performs no validation on it:
```rust
pub fn deposit(
  ctx: Context<Deposit>,
  eth_deposit_nonce: u64,
  amount: u64,
  bump: u8,
) -> Result<()> {
```

**Impact:**  
The relayer could specify an incorrect amount (higher or lower than what was actually deposited on Ethereum), leading to accounting discrepancies. While the relayer is a trusted entity, this lack of validation creates a single point of failure and doesn't protect against relayer bugs or compromise.

**Recommendation:**  
Add validation or cross-reference the amount against the deposit message received from Ethereum. Consider emitting an event with the amount for off-chain verification.

## Low: Missing Event Emission in Solana Deposit

**File:** `eclipse-programs/programs/canonical_bridge/src/instructions/deposit.rs`  
**Function:** `deposit` (line 29-57)

**Root Cause:**  
The deposit function doesn't emit any events after completing the transfer, making it difficult to track deposits off-chain.

**Impact:**  
Lack of events reduces transparency and makes it harder to monitor bridge operations, audit deposits, or build indexers. This could hinder debugging and reconciliation between Ethereum and Eclipse chains.

**Recommendation:**  
Add event emission using Anchor's `emit!` macro:
```rust
emit!(DepositCompleted {
    to: ctx.accounts.to.key(),
    amount,
    eth_deposit_nonce,
});
```

## Low: Registry Allows Silent Overwriting of Contracts

**File:** `smart-contracts/src/v1/Registry.sol`  
**Function:** `registerContract` (line 24-35)

**Root Cause:**  
The `registerContract` function allows re-registering an identifier or address without warning or requiring explicit overwrite authorization:
```solidity
identifierAddress[identifier] = contractAddress;
addressIdentifier[contractAddress] = identifier;
addressContractType[contractAddress] = contractType;
```

**Impact:**  
An owner (or compromised owner account) could accidentally overwrite critical contract addresses (like Router or Mailbox) without realizing it, potentially breaking the entire bridge system. This creates operational risk during upgrades or reconfigurations.

**Recommendation:**  
Add checks to prevent accidental overwrites:
```solidity
require(identifierAddress[identifier] == address(0), "Identifier already registered");
require(bytes(addressIdentifier[contractAddress]).length == 0, "Address already registered");
```

## Informational: Typo in Error Message

**File:** `smart-contracts/src/v1/EtherBridge.sol`  
**Line:** 32

**Root Cause:**  
Error message contains a typo: "deposite" instead of "deposit":
```solidity
require(amount <= MAX_DEPOSIT_AMOUNT, "Deposit amount must be less than equal to the max deposite amount");
```

**Impact:**  
Minor quality issue that could cause confusion when debugging. No security impact.

**Recommendation:**  
Fix the typo:
```solidity
require(amount <= MAX_DEPOSIT_AMOUNT, "Deposit amount must be less than equal to the max deposit amount");
```

## Informational: Inefficient Storage Layout in WithdrawalReceipt

**File:** `eclipse-programs/programs/canonical_bridge/src/state.rs`  
**Function:** `WithdrawalReceipt::size` (line 38-40)

**Root Cause:**  
The size is hardcoded to 1024 bytes with a TODO comment:
```rust
pub fn size() -> usize {
    1024  // TODO: optimize here
}
```

**Impact:**  
Allocating 1024 bytes when the actual struct likely needs much less wastes rent costs for users. This is inefficient and increases the cost of withdrawals.

**Recommendation:**  
Calculate the actual required size:
```rust
pub fn size() -> usize {
    8 +  // discriminator
    8 +  // withdrawal_nonce
    4 + 200 +  // String with max reasonable length
    8 +  // amount
    1   // bump
}
```

## Informational: Missing Input Validation on Chain IDs

**File:** `smart-contracts/src/v1/Mailbox.sol`  
**Function:** `initialize` (line 98-115)

**Root Cause:**  
The initialization accepts chain IDs without validating that they are different:
```solidity
ethereumChainId = _ethereumChainId;
eclipseChainId = _eclipseChainId;
```

**Impact:**  
If both chain IDs are set to the same value (due to deployment error), the bridge would accept messages from itself as if they came from the other chain, potentially creating circular message flows or enabling replay attacks.

**Recommendation:**  
Add validation:
```solidity
require(keccak256(_ethereumChainId) != keccak256(_eclipseChainId), "Chain IDs must be different");
```

## Informational: No Pause Mechanism

**File:** All contracts

**Root Cause:**  
None of the bridge contracts implement a pause mechanism to halt operations in case of an emergency.

**Impact:**  
If a critical vulnerability is discovered or if the bridge needs to be halted for maintenance, there's no way to stop operations without upgrading all contracts. This could lead to continued exploitation during an incident response.

**Recommendation:**  
Implement OpenZeppelin's Pausable pattern on critical functions:
```solidity
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";

function deposit(...) external whenNotPaused {
    // ...
}
```

## Informational: Centralization Risk with Single Relayer

**File:** `smart-contracts/src/v1/Mailbox.sol` and `eclipse-programs/programs/canonical_bridge/src/lib.rs`

**Root Cause:**  
The entire bridge system relies on a single relayer address for message passing. In Mailbox.sol, only this relayer can call `receiveMessage`. In the Solana program, the relayer is hardcoded.

**Impact:**  
If the relayer's private key is lost or compromised, the bridge becomes non-functional or can be exploited. This is a single point of failure that creates significant operational and security risks.

**Recommendation:**  
Implement a multi-relayer system with:
- A set of approved relayers instead of a single address
- A threshold signature scheme requiring multiple relayers to sign off on messages
- The ability to add/remove relayers through governance

## Informational: No Rate Limiting

**File:** `smart-contracts/src/v1/EtherBridge.sol` and Solana program

**Root Cause:**  
There are no rate limits on deposits or withdrawals beyond the per-transaction min/max amounts.

**Impact:**  
While individual transactions are capped, there's no protection against rapid successive transactions that could drain the treasury or overwhelm the relayer. This could be used for economic attacks or to create operational issues.

**Recommendation:**  
Implement rate limiting:
- Maximum total volume per time period
- Maximum number of transactions per user per time period
- Circuit breakers that pause operations if unusual activity is detected
