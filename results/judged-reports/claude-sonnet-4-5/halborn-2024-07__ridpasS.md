# Security Audit Report

## Critical: Arbitrary External Call to Module Contracts

**File:** `Mailbox.sol`  
**Function:** `receiveMessage` (lines 187-222)

**Root Cause:**  
The `receiveMessage` function performs an unchecked low-level call to a module address with arbitrary calldata:

```solidity
address module = $.modulesById[bytes32(sender_)];
require(module != address(0), "Module does not exist.");
(bool success,) = module.call(message_);
```

The `sender_` parameter comes from the trusted relayer and is used to determine which module receives the call. The `message_` contains arbitrary calldata that is directly forwarded to the module. This creates a critical vulnerability where:
1. The relayer has complete control over which module is called
2. The relayer can craft arbitrary calldata to invoke any function on the module
3. There is no cryptographic verification that the message actually originated from Eclipse

**Impact:**  
A compromised or malicious trusted relayer can call any function on any registered module with arbitrary parameters, potentially draining funds, manipulating state, or executing privileged operations. This completely breaks the security model of the cross-chain bridge.

**Recommendation:**  
Implement cryptographic verification of messages using signatures or Merkle proofs. The message should include a signature from an Eclipse validator set or a proof that can be verified on-chain. Additionally, consider implementing function selectors allowlist for each module.

## Critical: Missing Withdrawal Mechanism

**File:** `EtherBridge.sol`, `Treasury.sol`  
**Function:** N/A - missing functionality

**Root Cause:**  
The EtherBridge contract implements a `deposit` function that locks user funds in the Treasury, but there is no corresponding withdrawal function that allows users to retrieve their funds back to Ethereum. While `Treasury.emergencyWithdraw` exists, it can only be called by the owner and sends funds to the owner's address, not to users.

**Impact:**  
Users can deposit ether into the bridge but have no mechanism to withdraw it back to Ethereum through the provided smart contracts. Funds are effectively locked unless the owner manually returns them via `emergencyWithdraw`, creating a trust assumption and potential loss of funds.

**Recommendation:**  
Implement a withdrawal function that:
1. Accepts withdrawal messages from Eclipse via the Mailbox
2. Verifies the message authenticity (see previous finding)
3. Transfers the requested amount from Treasury to the user's Ethereum address
4. Implements proper access controls and replay protection

## Critical: Weak Nonce Generation Vulnerable to Manipulation

**File:** `Mailbox.sol`  
**Function:** `generateRandomNonce` (lines 257-264)

**Root Cause:**  
The nonce generation function uses predictable and manipulatable block properties:

```solidity
$.lastNonce = uint256(
    keccak256(abi.encodePacked($.lastNonce, blockhash(block.number - 1), block.timestamp, block.coinbase))
);
return uint64($.lastNonce);
```

Block validators/miners can influence `block.timestamp` (within bounds) and `block.coinbase`, and they know `blockhash(block.number - 1)` at the time of block creation.

**Impact:**  
A malicious block producer could potentially:
1. Predict future nonces and precompute attacks
2. Manipulate block parameters to cause nonce collisions
3. Selectively include/exclude transactions to control nonce generation
4. Create scenarios where specific nonces are generated to exploit other vulnerabilities

**Recommendation:**  
Use a verifiable random function (VRF) like Chainlink VRF, or implement a commit-reveal scheme. Alternatively, use a counter-based nonce system with proper monotonic incrementing guarantees.

## High: Nonce Collision Causes Permanent Transaction Failure

**File:** `Mailbox.sol`  
**Function:** `sendMessage` (lines 225-247)

**Root Cause:**  
When a nonce collision occurs in `sendMessage`, the function simply reverts without attempting to generate a new nonce:

```solidity
uint64 outboundNonce = generateRandomNonce();
if ($.sendNonces[outboundNonce] == true) {
    revert("Nonce collision");
}
$.sendNonces[outboundNonce] = true;
```

**Impact:**  
If `generateRandomNonce()` produces a nonce that has already been used:
1. The transaction permanently fails with no retry mechanism
2. Users lose gas fees for failed transactions
3. Bridge operations can be disrupted
4. This creates a denial-of-service vector, especially if nonce generation is predictable

**Recommendation:**  
Implement a loop to generate a new nonce on collision (with a maximum retry limit to prevent infinite loops), or switch to a monotonically incrementing counter-based nonce system.

## High: Missing Cross-Contract Initialization Validation

**File:** `EtherBridge.sol`  
**Function:** `initialize` (lines 71-89)

**Root Cause:**  
The EtherBridge initialization accepts a `treasuryAddress_` parameter but doesn't verify that:
1. The Treasury contract has `etherBridgeAddress` set to this EtherBridge's address
2. The Treasury is properly initialized and functional

Similarly, the EtherBridge doesn't verify that the Mailbox recognizes it as a valid module.

**Impact:**  
If the Treasury's `etherBridgeAddress` is set incorrectly or not set at all, the EtherBridge's `deposit` function will fail when trying to send ether to the Treasury because the Treasury's `receive()` function checks:

```solidity
require(msg.sender == $.etherBridgeAddress || msg.sender == owner(), "Unauthorized source");
```

This would result in all deposits failing until the configuration is fixed.

**Recommendation:**  
Add validation in the EtherBridge `initialize` function:
```solidity
// Verify Treasury accepts deposits from this bridge
(bool success,) = payable(treasuryAddress_).call{value: 0}("");
require(success, "Treasury not configured for this bridge");
```

Also verify the bridge is registered as a module in the Mailbox.

## High: Receive Nonce Replay Across Forks or Chain Reorganizations

**File:** `Mailbox.sol`  
**Function:** `receiveMessage` (lines 187-222)

**Root Cause:**  
The nonce tracking in `receiveMessage` only checks if a nonce has been used before:

```solidity
require($.receiveNonces[secParam.nonce] == false, "Message with this nonce already received.");
$.receiveNonces[secParam.nonce] = true;
```

However, there is no additional context (like block number, timestamp, or message hash) tied to the nonce. This creates vulnerabilities in edge cases.

**Impact:**  
1. If Ethereum undergoes a chain reorganization after a message is processed, the message could potentially be replayed
2. If the contract is upgraded and storage is not properly migrated, nonces could be reset
3. Nonces alone don't provide sufficient replay protection without additional context

**Recommendation:**  
Include additional replay protection by also hashing the message content and storing that hash, or include block number/timestamp bounds in the security parameters.

## High: Unbounded Gas Forwarding to External Modules

**File:** `Mailbox.sol`  
**Function:** `receiveMessage` (line 215)

**Root Cause:**  
The function forwards all remaining gas to the module via a low-level call:

```solidity
(bool success,) = module.call(message_);
```

This forwards all available gas and any msg.value to a potentially untrusted module contract.

**Impact:**  
1. A malicious or buggy module can consume all available gas, causing the transaction to fail
2. The module receives any ether sent with `receiveMessage` without explicit authorization
3. Gas griefing attacks are possible where modules intentionally waste gas
4. Unexpected ether transfers could occur if relayer sends value

**Recommendation:**  
1. Specify a gas limit for the external call: `module.call{gas: 200000}(message_)`
2. Don't forward msg.value unless explicitly intended: ensure receiveMessage doesn't accept unexpected ether
3. Validate that msg.value is zero or explicitly handle ether forwarding with proper accounting

## Medium: Treasury Pause Mechanism Can Block All Deposits

**File:** `Treasury.sol`  
**Function:** `receive` (lines 83-87)

**Root Cause:**  
The Treasury's `receive()` function has a `whenNotPaused` modifier:

```solidity
receive() external payable virtual whenNotPaused {
    StorageV1 storage $ = _getStorageV1();
    require(msg.sender == $.etherBridgeAddress || msg.sender == owner(), "Unauthorized source");
    emit TreasuryDeposit(msg.sender, msg.value);
}
```

When the Treasury is paused, it cannot receive ether from anyone, including the EtherBridge.

**Impact:**  
If the Treasury owner calls `pause()`:
1. All EtherBridge deposits will fail because the Treasury's receive function reverts
2. Users attempting to deposit funds will lose gas and their transactions will fail
3. The bridge becomes non-functional until the Treasury is unpaused
4. This creates a single point of failure controlled by one address

**Recommendation:**  
Consider whether the pause mechanism should apply to deposits from the authorized EtherBridge. If the goal is to pause only owner deposits, modify the logic:
```solidity
receive() external payable virtual {
    StorageV1 storage $ = _getStorageV1();
    if (msg.sender == owner()) {
        require(!paused(), "Owner deposits paused");
    }
    require(msg.sender == $.etherBridgeAddress || msg.sender == owner(), "Unauthorized source");
    emit TreasuryDeposit(msg.sender, msg.value);
}
```

## Medium: Emergency Withdraw Allows Unrestricted Fund Draining

**File:** `Treasury.sol`  
**Function:** `emergencyWithdraw` (lines 63-69)

**Root Cause:**  
The `emergencyWithdraw` function allows the owner to withdraw any amount of ether from the Treasury at any time with no restrictions, timelocks, or governance:

```solidity
function emergencyWithdraw(uint256 amount) external virtual override onlyOwner nonReentrant {
    require(address(this).balance >= amount, "Insufficient funds");
    (bool success,) = msg.sender.call{value: amount}("");
    require(success, "Failed to send Ether");
    emit EmergencyTreasuryWithdraw(msg.sender, amount);
}
```

**Impact:**  
1. The owner can drain all user funds at any time without justification
2. Users have to completely trust the owner not to abuse this function
3. No accounting is maintained for user vs owner funds
4. If the owner key is compromised, all funds can be stolen immediately

**Recommendation:**  
1. Implement a timelock mechanism requiring a delay between announcing and executing withdrawals
2. Add a maximum withdrawal limit per time period
3. Implement multi-signature requirements for large withdrawals
4. Maintain separate accounting for user deposits vs owner funds
5. Emit detailed events and consider requiring a governance vote for emergency actions

## Medium: Module Address Management Lacks Proper Validation

**File:** `Mailbox.sol`  
**Functions:** `addModule`, `removeModule` (lines 151-184)

**Root Cause:**  
The module management functions have several issues:

1. `addModule` prevents adding a module if `$.modulesById[moduleId]` is already set, but the same address can be registered under multiple module IDs
2. `removeModule` revokes the MODULE_ROLE for an address even if that address is still registered under other module IDs
3. No validation that the module address is a contract or has expected interface

**Impact:**  
1. If address A is registered under both moduleId1 and moduleId2, calling `removeModule(moduleId1, A)` will revoke MODULE_ROLE, preventing A from calling `sendMessage` even though it's still registered under moduleId2
2. An EOA (externally owned account) could be registered as a module, which doesn't make sense
3. The mapping can become inconsistent with the role assignments

**Recommendation:**  
1. Maintain a reference count for how many module IDs map to each address
2. Only revoke MODULE_ROLE when the reference count reaches zero
3. Add validation that module addresses are contracts
4. Consider maintaining a reverse mapping from address to module IDs for easier management

## Medium: Mailbox Accepts Ether Without Proper Handling

**File:** `Mailbox.sol`  
**Functions:** `receiveMessage`, `sendMessage` (lines 187-247)

**Root Cause:**  
Both `receiveMessage` and `sendMessage` are marked as `payable` and accept ether, but there is no mechanism to withdraw or account for ether sent to the Mailbox contract. Any ether sent directly to these functions (not forwarded to modules) will be locked in the contract.

**Impact:**  
1. Ether sent to the Mailbox by mistake will be permanently locked
2. If the relayer accidentally sends value with `receiveMessage`, it gets forwarded to the module without accounting
3. There's no function to recover mistakenly sent ether
4. The contract's ether balance can grow without purpose

**Recommendation:**  
1. If these functions aren't intended to receive ether, remove the `payable` modifier
2. If ether forwarding is intentional, document it clearly and add accounting mechanisms
3. Add a function to recover accidentally sent ether (only for amounts not intended for modules)

## Low: Missing Events for Critical Admin Operations

**File:** `Mailbox.sol`  
**Functions:** `addModule`, `removeModule` (lines 151-184)

**Root Cause:**  
The `addModule` and `removeModule` functions modify critical contract state but don't emit events:

```solidity
function addModule(bytes32 moduleId, address module) external ... {
    $.modulesById[moduleId] = module;
    _grantRole(MODULE_ROLE, module);
    // No event emitted
}
```

**Impact:**  
1. Off-chain monitoring systems cannot track module changes
2. Users cannot easily verify which modules are authorized
3. Forensic analysis after a security incident is more difficult
4. Transparency is reduced

**Recommendation:**  
Add events for module management:
```solidity
event ModuleAdded(bytes32 indexed moduleId, address indexed module);
event ModuleRemoved(bytes32 indexed moduleId, address indexed module);
```

Emit these events in the respective functions.

## Low: No Rate Limiting on Deposits or Messages

**File:** `EtherBridge.sol`, `Mailbox.sol`  
**Functions:** `deposit`, `sendMessage`

**Root Cause:**  
There are no rate limits or maximum caps on:
1. Number of deposits per block/time period
2. Total deposit amount per block/time period  
3. Number of messages sent per block/time period

**Impact:**  
1. Spam attacks could flood the system with small deposits, clogging the Eclipse chain
2. Large deposits could exceed Eclipse's capacity to process
3. Message spam could overwhelm the relayer or Eclipse processing
4. No protection against griefing attacks

**Recommendation:**  
Implement rate limiting:
1. Maximum number of deposits per block/time window
2. Maximum total deposit amount per time period
3. Minimum cooldown between deposits from the same address
4. Consider implementing a fee mechanism that scales with usage

## Low: Precision Loss in Wei to Gwei Conversion

**File:** `EtherBridge.sol`  
**Function:** `deposit` (line 105)

**Root Cause:**  
The deposit function validates that `msg.value % WEI_PER_LAMPORT == 0` to prevent precision loss, but this requirement is only enforced by a modifier and could be bypassed if the contract is upgraded without this check.

**Impact:**  
If the validation is removed in a future upgrade, users could lose fractional gwei amounts due to integer division:
```solidity
uint256 amountGwei = amountWei / WEI_PER_LAMPORT;
```

**Recommendation:**  
Add a comment explaining why this validation is critical and must be maintained in all future versions. Consider adding the check directly in the function body as a belt-and-suspenders approach.

## Low: Unbounded Loop in Initialization

**File:** `Mailbox.sol`  
**Function:** `initialize` (lines 137-142)

**Root Cause:**  
The initialization function loops through all modules without a gas limit check:

```solidity
for (uint256 i = 0; i < params.modules.length; i++) {
    bytes32 id = params.ids[i];
    address module = params.modules[i];
    _grantRole(MODULE_ROLE, module);
    $.modulesById[id] = module;
}
```

**Impact:**  
If too many modules are passed during initialization, the transaction could run out of gas and fail, making the contract undeployable with the desired configuration.

**Recommendation:**  
1. Document a maximum recommended number of modules
2. Consider initializing modules in batches via a separate function
3. Add a require statement limiting the array length: `require(params.modules.length <= MAX_MODULES, "Too many modules")`

## Informational: Centralization Risk with Trusted Relayer

**File:** `Mailbox.sol`  
**Function:** `receiveMessage`

**Root Cause:**  
The entire bridge security model relies on a single trusted relayer address. This creates a single point of failure and complete trust assumption.

**Impact:**  
1. If the relayer private key is compromised, the entire bridge is compromised
2. If the relayer goes offline, the bridge stops functioning
3. No redundancy or decentralization
4. Users must trust the relayer not to act maliciously

**Recommendation:**  
1. Implement a multi-relayer system with consensus requirements (e.g., 2-of-3 or 3-of-5)
2. Use threshold signatures for relayer operations
3. Implement slashing mechanisms for malicious relayers
4. Add fraud proofs or optimistic verification
5. Consider integrating with established bridge protocols (LayerZero, Axelar, Wormhole)

## Informational: Owner Can Transfer Ownership During Pending State

**File:** `Treasury.sol`  
**Function:** Inherited from `Ownable2StepUpgradeable`

**Root Cause:**  
The Treasury uses `Ownable2StepUpgradeable` which implements two-step ownership transfer. However, during the pending state (after `transferOwnership` is called but before `acceptOwnership`), the current owner retains full control and can call `transferOwnership` again to a different address.

**Impact:**  
1. The pending owner could be front-run or have their ownership revoked
2. Creates uncertainty during ownership transfers
3. Could be used to create confusion or in social engineering attacks

**Recommendation:**  
This is expected behavior for two-step ownership transfer, but document the process clearly. Consider adding a `cancelOwnershipTransfer` function for explicitly canceling pending transfers.

## Informational: No Validation of Constructor Arguments

**File:** All contracts  
**Function:** `initialize`

**Root Cause:**  
While the `initialize` functions use modifiers like `addressInitialized` to validate addresses are non-zero, there's no validation that the addresses are actually deployed contracts or have the expected interfaces.

**Impact:**  
1. The contracts could be initialized with incorrect addresses
2. EOAs could be set as contract addresses, causing silent failures
3. Wrong contract types could be set, causing failures later

**Recommendation:**  
Add validation that addresses are contracts:
```solidity
require(address(mailboxAddress_).code.length > 0, "Mailbox must be a contract");
```

Consider using interface checks where possible.

## Informational: Lack of Input Sanitization for Chain IDs

**File:** `Mailbox.sol`  
**Function:** `initialize` (lines 145-146)

**Root Cause:**  
Chain IDs are accepted as strings and converted to bytes32 via keccak256:

```solidity
$.ethereumChainId = generateChainId(params.ethereumChainId);
$.eclipseChainId = generateChainId(params.eclipseChainId);
```

There's no validation that these strings are reasonable or that the resulting chain IDs are distinct.

**Impact:**  
1. Typos in chain ID strings could cause the bridge to be misconfigured
2. If both chain IDs are set to the same value, cross-chain messages could be confused
3. Empty strings are prevented by the modifier but other invalid inputs are not

**Recommendation:**  
1. Validate that ethereumChainId != eclipseChainId
2. Consider using numeric chain IDs that can be validated against known values
3. Add checks that the string representations match expected formats
