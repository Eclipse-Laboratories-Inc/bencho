# Security Audit Report: Canonical Bridge

## High: Predictable Nonce Generation Allows Message Replay and Front-Running

**Affected File**: `smart-contracts/src/v1/Mailbox.sol`  
**Function**: `generateRandomNonce()` (lines 244-250)

**Root Cause**: The `generateRandomNonce()` function uses predictable blockchain properties (blockhash, timestamp, coinbase) to generate nonces for cross-chain messages. These values are known in advance or manipulable by validators/miners, making the nonce predictable.

```solidity
$.lastNonce = uint256(
    keccak256(abi.encodePacked($.lastNonce, blockhash(block.number - 1), block.timestamp, block.coinbase))
);
return uint64($.lastNonce);
```

**Impact**: An attacker can predict future nonces and pre-populate the `receiveNonces` mapping by calling `receiveMessage` with predicted nonces, causing legitimate messages to fail. Validators can also manipulate block.timestamp and block.coinbase within acceptable ranges to influence nonce generation for front-running attacks.

**Recommendation**: Use a counter-based nonce system instead of pseudo-random generation, or implement a commit-reveal scheme. For cross-chain messaging, the nonce should be determined by the sender chain and verified on the receiver chain.

## High: Bump Parameter Not Validated in Solana Deposit Function

**Affected File**: `eclipse-programs/programs/canonical_bridge/src/instructions/deposit.rs`  
**Function**: `deposit()` (lines 31-62)

**Root Cause**: The `bump` parameter is passed as an argument but never validated against the actual derived bump from the PDA seeds. The Anchor framework derives the correct bump internally, but the passed parameter is stored without verification.

```rust
pub fn deposit(ctx: Context<Deposit>, eth_deposit_nonce: u64, amount: u64, bump: u8) -> Result<()> {
    // ...
    deposit_receipt.bump = bump;  // Stored without validation
```

**Impact**: A malicious relayer could pass an incorrect bump value that gets stored in the deposit receipt. This could cause issues when the deposit receipt is later used in operations that depend on the bump value, potentially leading to failed transactions or account derivation mismatches.

**Recommendation**: Either remove the bump parameter and use `ctx.bumps.deposit_receipt` from Anchor's derived bumps, or add explicit validation:
```rust
deposit_receipt.bump = ctx.bumps.deposit_receipt;
require!(bump == ctx.bumps.deposit_receipt, ErrorCode::InvalidBump);
```

## High: Low-Level Call Without Contract Existence Check

**Affected File**: `smart-contracts/src/v1/Mailbox.sol`  
**Function**: `receiveMessage()` (lines 195-211)

**Root Cause**: The function uses a low-level `call` to invoke the module at line 205 without verifying that the address contains contract code. If the module address is not a contract or has been destroyed, the call will silently succeed.

```solidity
address module = $.modulesById[bytes32(sender_)];
require(module != address(0), "Module does not exist.");
(bool success,) = module.call(message_);
require(success, "External call to module failed.");
```

**Impact**: If a module contract is destroyed (via `selfdestruct`) or if the mapping points to an EOA, the low-level call returns true without executing any logic. This allows messages to be marked as received without proper processing, potentially allowing relayer to bypass message delivery while consuming nonces.

**Recommendation**: Add a contract existence check before the call:
```solidity
require(module.code.length > 0, "Module is not a contract");
```
Or use a safer interface-based approach with explicit function selectors.

## High: No Cross-Chain Amount Verification Between Ethereum and Eclipse

**Affected Files**: 
- `smart-contracts/src/v1/EtherBridge.sol` (deposit function)
- `eclipse-programs/programs/canonical_bridge/src/instructions/deposit.rs`

**Root Cause**: The Ethereum `EtherBridge.deposit()` function sends a message containing the deposit amount, but the Eclipse `deposit()` function accepts an `amount` parameter from the relayer without any verification against what was actually deposited on Ethereum. There is no cryptographic proof or signature verification linking the two amounts.

**Impact**: A malicious or compromised relayer can credit users on Eclipse with arbitrary amounts that don't correspond to their Ethereum deposits. Users could deposit 1 ETH on Ethereum but receive 1000 ETH worth on Eclipse, or vice versa, leading to economic attacks and loss of funds.

**Recommendation**: Implement cryptographic verification of cross-chain messages. Options include:
1. Have the relayer submit a Merkle proof or signature from Ethereum validators
2. Implement a multi-signature scheme requiring multiple independent relayers to agree on amounts
3. Add a challenge period where discrepancies can be disputed

## High: Missing Withdrawal Message Validation in EtherBridge

**Affected File**: `smart-contracts/src/v1/EtherBridge.sol`

**Root Cause**: The `EtherBridge` contract has no function to receive and process withdrawal messages from Eclipse. While deposits work from Ethereum to Eclipse, there's no corresponding withdrawal implementation to send funds back to users on Ethereum.

**Impact**: Users can deposit ETH and send it to Eclipse, but there's no mechanism to withdraw it back to Ethereum. Funds are effectively locked unless the Treasury owner performs an emergency withdrawal. This breaks the bridge functionality and could trap user funds permanently.

**Recommendation**: Implement a `processWithdrawal()` function in `EtherBridge` that:
1. Can only be called by the Mailbox contract
2. Validates withdrawal messages from Eclipse
3. Verifies nonces to prevent replay
4. Withdraws funds from Treasury and sends to the destination address

## Medium: Unbounded Loops in Common Container Modifiers Enable DoS

**Affected File**: `smart-contracts/src/v1/CommonContainer.sol`  
**Functions**: `addressArrayInitialized`, `bytesArrayInitialized`, `bytes32ArrayInitialized` (lines 25-60)

**Root Cause**: The modifiers iterate over entire arrays without any length limit. Each iteration performs a storage read and comparison.

```solidity
modifier addressArrayInitialized(address[] memory _addresses) {
    for (uint256 i = 0; i < _addresses.length; i++) {
        require(_addresses[i] != address(0), "AddressChecks: zero address in array");
    }
    _;
}
```

**Impact**: An attacker could pass extremely large arrays to functions using these modifiers, causing transactions to run out of gas. In the `Mailbox.initialize()` function, this could prevent initialization entirely or make adding many modules prohibitively expensive.

**Recommendation**: 
1. Add maximum array length limits (e.g., 50-100 elements)
2. Consider removing zero-address checks for arrays, relying instead on per-element validation when items are actually used
3. Avoid using loops in modifiers; perform validation in function bodies where gas costs are more predictable

## Medium: Nonce Replay Protection Allows Permanent DoS

**Affected File**: `smart-contracts/src/v1/Mailbox.sol`  
**Function**: `receiveMessage()` (lines 197-200)

**Root Cause**: The nonce replay protection uses a simple boolean mapping that permanently marks nonces as used. Combined with predictable nonce generation, an attacker can frontrun and consume future nonces.

```solidity
require($.receiveNonces[secParam.nonce] == false, "Message with this nonce already received.");
$.receiveNonces[secParam.nonce] = true;
```

**Impact**: An attacker who can predict nonces (see previous finding) can pre-consume them by sending dummy messages, causing all subsequent legitimate messages with those nonces to fail permanently. This creates a persistent DoS condition for the bridge.

**Recommendation**: 
1. Implement sequential nonce checking (nonce = lastNonce + 1) instead of allowing arbitrary nonces
2. Add nonce expiration where old nonces can be reused after a time period
3. Use a sliding window approach with nonce ranges

## Medium: Destination Address Not Validated in Solana Withdraw

**Affected File**: `eclipse-programs/programs/canonical_bridge/src/instructions/withdraw.rs`  
**Function**: `withdraw()` (lines 36-89)

**Root Cause**: The `destination_address` parameter is accepted as a String without any validation that it's a valid Ethereum address. Invalid addresses are stored and logged but will fail when processed on Ethereum.

```rust
pub fn withdraw(
    ctx: Context<Withdraw>,
    destination_address: String,  // No validation
    withdrawal_nonce: u64,
    amount: u64,
    bump: u8,
) -> Result<()> {
```

**Impact**: Users can initiate withdrawals to invalid Ethereum addresses. Their funds get locked on Eclipse (transferred to relayer), but the withdrawal cannot be processed on Ethereum. Users lose their funds permanently without any way to recover them.

**Recommendation**: Add validation for Ethereum addresses:
1. Check the string is exactly 42 characters (0x + 40 hex chars)
2. Validate it starts with "0x"
3. Verify all characters after "0x" are valid hexadecimal
4. Consider maintaining a mapping of pending withdrawals that can be cancelled within a time window

## Medium: Empty ChainId Parameter Ignored in sendMessage

**Affected File**: `smart-contracts/src/v1/Mailbox.sol`  
**Function**: `sendMessage()` (lines 215-234)

**Root Cause**: The `sendMessage()` function accepts a `chainId_` parameter but completely ignores it, always using the stored `ethereumChainId`. The EtherBridge calls it with an empty string (line 120 of EtherBridge.sol).

```solidity
function sendMessage(bytes memory, bytes memory receiver_, bytes memory message_, bytes memory)
    // chainId_ parameter is not used at all
```

**Impact**: This creates confusion about the intended destination chain and could lead to messages being sent to wrong chains if the function signature is changed. The ignored parameter also violates the IMailbox interface expectations.

**Recommendation**: Either:
1. Remove the unused parameter and update the interface
2. Use the parameter to validate the destination chain
3. Support multi-chain destinations by using the parameter

## Medium: No Maximum Withdrawal Amount Check in Solana

**Affected File**: `eclipse-programs/programs/canonical_bridge/src/instructions/withdraw.rs`  
**Function**: `withdraw()` (lines 36-89)

**Root Cause**: The withdraw function accepts any amount value without validating it against reasonable limits or checking if the relayer actually has sufficient funds on Ethereum to honor the withdrawal.

**Impact**: Users can request withdrawals for amounts larger than what's available in the Treasury on Ethereum. These withdrawals will fail when processed on Ethereum, but the user's funds are already transferred to the relayer on Eclipse. This can lead to stuck withdrawals and loss of user funds.

**Recommendation**: 
1. Implement a maximum withdrawal limit
2. Add a mechanism to track the Ethereum Treasury balance on Eclipse
3. Consider implementing a withdrawal queue with balance verification
4. Add ability to cancel failed withdrawals and return funds to users

## Low: Bump Parameter Not Validated in Solana Withdraw Function

**Affected File**: `eclipse-programs/programs/canonical_bridge/src/instructions/withdraw.rs`  
**Function**: `withdraw()` (line 41)

**Root Cause**: Similar to the deposit function, the `bump` parameter is passed but not validated against Anchor's derived bump.

```rust
withdrawal_receipt.bump = bump;  // Not validated
```

**Impact**: Incorrect bump values could be stored, causing issues with account derivation in future operations that depend on the withdrawal receipt.

**Recommendation**: Use `ctx.bumps.withdrawal_receipt` instead of the passed parameter, or add validation.

## Low: Centralized Control Through Single Relayer

**Affected Files**:
- `eclipse-programs/programs/canonical_bridge/src/lib.rs` (RELAYER_PUBKEY constants)
- `smart-contracts/src/v1/Mailbox.sol` (TRUSTED_RELAYER_ROLE)

**Root Cause**: The entire bridge system relies on a single trusted relayer address for all cross-chain message passing. This relayer has complete control over what messages are delivered and in what order.

**Impact**: A compromised or malicious relayer can:
- Censor messages by refusing to relay them
- Reorder messages for front-running opportunities  
- Create economic attacks by manipulating amounts (see amount verification issue)
- Single point of failure if relayer is offline

**Recommendation**: 
1. Implement multi-relayer system with consensus mechanism
2. Add economic incentives and penalties for relayers
3. Implement fraud proofs or challenge periods
4. Consider using decentralized oracle networks

## Low: Inefficient String Operations in Solana Withdraw

**Affected File**: `eclipse-programs/programs/canonical_bridge/src/instructions/withdraw.rs`  
**Function**: `withdraw()` (lines 52, 71, 80)

**Root Cause**: Multiple string clones and allocations occur during the withdraw operation:

```rust
withdrawal_receipt.destination_address = destination_address.clone();
// ... later
destination_address: destination_address.clone(),
```

**Impact**: String operations are expensive on Solana in terms of compute units. Multiple clones and the unbounded string length for destination addresses can consume significant compute budget, potentially causing transactions to fail or be more expensive than necessary.

**Recommendation**:
1. Store destination addresses as fixed-size byte arrays (20 bytes for Ethereum)
2. Avoid cloning strings multiple times; use references where possible
3. Add length limits to string parameters

## Low: Hardcoded Chain Identifiers in Withdraw Message

**Affected File**: `eclipse-programs/programs/canonical_bridge/src/instructions/withdraw.rs`  
**Function**: `withdraw()` (lines 80-81)

**Root Cause**: The chain ID and receiver are hardcoded as strings:

```rust
let withdrawal_message = WithdrawalMessageSent {
    chain_id: String::from("Eclipse"),
    receiver: String::from("EtherBridge"),
    message,
    data,
};
```

**Impact**: This makes the program inflexible and tightly coupled to specific chain and contract names. If chain names change or multiple destination chains are supported, the code must be redeployed.

**Recommendation**: Store chain identifiers and receiver addresses in the Configuration account, allowing runtime updates by the authority.

## Low: Missing Event Emission in EtherBridge Pause Functions

**Affected File**: `smart-contracts/src/v1/EtherBridge.sol`  
**Functions**: `pause()` and `unpause()` (lines 131-138)

**Root Cause**: The pause and unpause functions don't emit specific events, only relying on OpenZeppelin's internal Paused/Unpaused events.

**Impact**: Off-chain monitoring systems and users have reduced visibility into when deposits are paused. The OpenZeppelin events don't provide bridge-specific context.

**Recommendation**: Emit custom events:
```solidity
event DepositsPaused(address indexed admin);
event DepositsUnpaused(address indexed admin);
```

## Low: Treasury Receive Function Restricts Future Flexibility

**Affected File**: `smart-contracts/src/v1/Treasury.sol`  
**Function**: `receive()` (lines 72-76)

**Root Cause**: The receive function only accepts ETH from the EtherBridge or owner:

```solidity
receive() external payable virtual whenNotPaused {
    StorageV1 storage $ = _getStorageV1();
    require(msg.sender == $.etherBridgeAddress || msg.sender == owner(), "Unauthorized source");
    emit TreasuryDeposit(msg.sender, msg.value);
}
```

**Impact**: If the EtherBridge address needs to be upgraded or changed, the Treasury must also be upgraded to accept funds from the new address. This creates unnecessary coupling and upgrade complexity.

**Recommendation**: 
1. Add a function to update the authorized bridge address
2. Support multiple authorized bridge addresses
3. Consider removing the restriction entirely if emergency withdrawals provide sufficient protection

## Informational: Redundant Module Length Check in Mailbox Initialize

**Affected File**: `smart-contracts/src/v1/Mailbox.sol`  
**Function**: `initialize()` (lines 109-138)

**Root Cause**: The function checks module array lengths twice - once in the modifier at line 100-105 and again in the function body at line 118:

```solidity
function initialize(InitParams calldata params)
    public
    // ... modifiers including bytes32ArrayInitialized checking length != 0
{
    require(params.ids.length == params.modules.length, "Module ids and addresses must have equal length");
```

**Impact**: Minor gas inefficiency and code redundancy. No security impact.

**Recommendation**: Remove the redundant check since the `validateModuleArrays` modifier already performs this validation, or remove the modifier if not used elsewhere.

## Informational: Inconsistent Access Control Pattern Between Contracts

**Affected Files**: Multiple

**Root Cause**: The contracts use different access control patterns:
- `EtherBridge` uses `AccessControlUpgradeable` with `DEFAULT_ADMIN_ROLE`
- `Treasury` uses `Ownable2StepUpgradeable` with owner
- `Mailbox` uses both `AccessControlUpgradeable` with multiple roles

**Impact**: This inconsistency makes the codebase harder to audit and maintain. Different trust assumptions apply to different contracts.

**Recommendation**: Standardize on one access control pattern across all contracts, or document clearly why different patterns are used for different contracts. Consider using AccessControl everywhere for consistency and flexibility.

## Informational: Missing Input Validation for Amount in EtherBridge Deposit

**Affected File**: `smart-contracts/src/v1/EtherBridge.sol`  
**Function**: `deposit()` (lines 101-128)

**Root Cause**: While the function validates that `msg.value >= MIN_DEPOSIT` and equals `amountWei`, there's no upper limit check. Combined with the gwei conversion at line 114, extremely large deposits could cause issues.

```solidity
uint256 amountGwei = amountWei / WEI_PER_LAMPORT;
```

**Impact**: While Solidity 0.8.21 prevents overflow, sending extremely large amounts could create issues on the Eclipse side or exceed the uint64 size expected by the Solana program. The division could also lose precision for very large numbers.

**Recommendation**: Add a maximum deposit limit:
```solidity
uint256 public constant MAX_DEPOSIT = 1000 ether; // Or appropriate limit
require(msg.value <= MAX_DEPOSIT, "Deposit exceeds maximum");
```

## Informational: Configuration Size Overallocated in Solana Program

**Affected File**: `eclipse-programs/programs/canonical_bridge/src/state.rs`  
**Function**: `Configuration::size()` (lines 67-71)

**Root Cause**: The Configuration account allocates 1024 bytes but only needs 8 (discriminator) + 1 (bump) + 1 (deposits_paused) + 1 (withdrawals_paused) = 11 bytes.

```rust
impl Configuration {
    pub fn size() -> usize {
        1024  // Massive overallocation
    }
}
```

**Impact**: Users pay unnecessary rent for unused space. Each configuration initialization costs more than needed.

**Recommendation**: Calculate the exact size needed:
```rust
pub fn size() -> usize {
    8 + // discriminator
    1 + // bump
    1 + // deposits_paused
    1   // withdrawals_paused
}
```

## Informational: WithdrawalReceipt Size Also Overallocated

**Affected File**: `eclipse-programs/programs/canonical_bridge/src/state.rs`  
**Function**: `WithdrawalReceipt::size()` (lines 37-40)

**Root Cause**: Similar to Configuration, WithdrawalReceipt allocates 1024 bytes but likely needs far less for storing a nonce (8), amount (8), bump (1), and destination address (variable, but could be bounded).

**Impact**: Increased costs for users initiating withdrawals.

**Recommendation**: Calculate exact size based on actual fields:
```rust
pub fn size() -> usize {
    8 +  // discriminator
    8 +  // withdrawal_nonce
    42 + // destination_address (Ethereum address with 0x)
    8 +  // amount
    1    // bump
}
```
