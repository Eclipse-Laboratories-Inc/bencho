# Smart Contract Security Audit Report

## Critical: Missing WITHDRAW_AUTHORITY_ROLE Grant in Deployment Script

**File:** `smart-contracts/script/v1/deploy/DeployV1.s.sol`  
**Function:** `run()`

**Root Cause:**  
The deployment script at line 50 only grants `DEPOSITOR_ROLE` to the `CanonicalBridge` contract on the `Treasury`, but fails to grant `WITHDRAW_AUTHORITY_ROLE`. This is critical because `CanonicalBridge.claimWithdrawal()` calls `Treasury.withdrawEth()` which requires the caller to have `WITHDRAW_AUTHORITY_ROLE` (enforced by the `onlyRole(WITHDRAW_AUTHORITY_ROLE)` modifier at Treasury.sol:117).

**Impact:**  
All withdrawal claims will fail, making the bridge completely non-functional. Users can deposit funds but cannot withdraw them, effectively locking all funds permanently. This is a complete system failure.

**Recommendation:**  
Add the missing role grant after line 50:
```solidity
_treasuryV1.grantRole(_treasuryV1.WITHDRAW_AUTHORITY_ROLE(), address(canonicalBridgeV1));
```

Note that `Upgrader0to1.sol` correctly grants this role at lines 129-130, so only the deployment script is affected.

## High: Checks-Effects-Interactions Pattern Violation in claimWithdrawal

**File:** `smart-contracts/src/v1/CanonicalBridge.sol`  
**Function:** `claimWithdrawal()`

**Root Cause:**  
At lines 230-241, the function modifies state (`startTime[messageHash] = NEVER`) and emits events before making an external call to `Treasury.withdrawEth()`. This violates the Checks-Effects-Interactions (CEI) pattern.

**Impact:**  
While direct reentrancy is prevented by the `nonReentrant` modifier, this creates a window for cross-function reentrancy attacks. During the external call to the Treasury, the malicious recipient's receive function could call back into other CanonicalBridge functions. The contract state would show the withdrawal as "CLOSED" while the actual fund transfer is still in progress, potentially allowing exploitation of functions that depend on this state or the Treasury balance.

**Recommendation:**  
Move the state change and event emission after the external call:
```solidity
bool success = ITreasury(TREASURY).withdrawEth(
    message.destination,
    message.amountWei,
    message.feeReceiver,
    message.feeWei
);
if (!success) revert WithdrawFailed();

startTime[messageHash] = NEVER;
emit WithdrawClaimed(message.destination, message.from, messageHash, message);
```

## High: Missing Reentrancy Protection on emergencyWithdraw

**File:** `smart-contracts/src/v1/Treasury.sol`  
**Function:** `emergencyWithdraw()`

**Root Cause:**  
The `emergencyWithdraw()` function at lines 132-144 makes an external call via low-level `call` to transfer ETH but lacks the `nonReentrant` modifier, while the regular `withdrawEth()` function has this protection.

**Impact:**  
A malicious admin with `EMERGENCY_ROLE` could potentially exploit reentrancy by having their contract's receive function call back into `emergencyWithdraw()` or other state-changing functions. While this requires a malicious privileged user, it violates defense-in-depth principles and could be exploited if the private key is compromised or in a complex multi-contract attack scenario.

**Recommendation:**  
Add the `nonReentrant` modifier to the function:
```solidity
function emergencyWithdraw(uint256 amount) 
    external
    virtual 
    override
    nonReentrant  // Add this
    onlyRole(EMERGENCY_ROLE)
```

## High: Dangerous Use of Low-Level Call with Function Signature String

**File:** `smart-contracts/src/v1/CanonicalBridge.sol`  
**Function:** `deposit()`

**Root Cause:**  
At line 150, the code uses `abi.encodeWithSignature("depositEth()")` with a low-level call instead of using the interface. If the Treasury contract has a fallback function or if the function signature doesn't match exactly, the call could succeed without actually calling `depositEth()`.

**Impact:**  
- If the Treasury is upgraded and `depositEth()` signature changes, deposits will silently fail while still emitting `Deposited` events
- Funds would be transferred to Treasury but the `depositEth()` function wouldn't execute, potentially bypassing access control or event emissions in the Treasury
- Creates a mismatch between on-chain events and actual state

**Recommendation:**  
Use the interface instead of low-level call:
```solidity
ITreasury(TREASURY).depositEth{value: amountWei}();
if (address(TREASURY).balance < amountWei) revert CanonicalBridgeTransactionRejected(0, "failed to transfer funds to the treasury");
```

## Medium: Non-Atomic Dual Transfer Pattern in withdrawEth

**File:** `smart-contracts/src/v1/Treasury.sol`  
**Function:** `withdrawEth()`

**Root Cause:**  
At lines 123-126, the function performs two separate external calls to transfer funds: first to the recipient, then to the fee receiver. If the first call succeeds but consumes significant gas (e.g., expensive receive function), the second call might fail due to out-of-gas, causing the entire transaction to revert.

**Impact:**  
Legitimate withdrawals could fail if the recipient address has an expensive receive function. This creates unpredictable behavior and poor user experience. Additionally, it wastes gas when the second transfer fails since the entire transaction reverts after the first transfer completes.

**Recommendation:**  
Consider either:
1. Check gas remaining before the second transfer and require sufficient gas
2. Use a pull-payment pattern where fee receiver claims fees separately
3. Document gas requirements clearly for integrators

## Medium: Privileged Role Assignment to Deployer in reinitialize

**File:** `smart-contracts/src/v1/Treasury.sol`  
**Function:** `reinitialize()`

**Root Cause:**  
At line 90, the function grants `DEFAULT_ADMIN_ROLE` to `msg.sender` (the deployer/caller) in addition to the old owner. This centralizes control and creates a trust assumption.

**Impact:**  
The deployer or upgrade executor gains full administrative control over the Treasury alongside the original owner. If the deployer's address is compromised or the deployer is malicious, they could:
- Grant themselves operational roles (EMERGENCY_ROLE, UPGRADER_ROLE, etc.)
- Upgrade the contract to a malicious implementation
- Pause/unpause the contract arbitrarily

This violates the principle of least privilege and creates an unnecessary attack surface.

**Recommendation:**  
Remove the automatic grant to `msg.sender` or make it optional with an additional parameter:
```solidity
function reinitialize(bool grantCallerAdmin) external virtual override reinitializer(2) {
    address oldOwner = _getOwnableStorage()._owner;
    if (oldOwner == NULL_ADDRESS) {
        revert InvalidInitialization();
    }
    emit TreasuryReinitialized(msg.sender, oldOwner);
    _grantRole(DEFAULT_ADMIN_ROLE, oldOwner);
    _grantRole(PAUSER_ROLE, oldOwner);
    _grantRole(STARTER_ROLE, oldOwner);
    _grantRole(UPGRADER_ROLE, oldOwner);
    _grantRole(EMERGENCY_ROLE, oldOwner);
    
    if (grantCallerAdmin) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }
}
```

## Medium: No Upper Bound on Fraud Window Duration

**File:** `smart-contracts/src/v1/CanonicalBridge.sol`  
**Function:** `setFraudWindowDuration()`

**Root Cause:**  
At lines 268-271, the function only validates a minimum duration but no maximum. An admin with `FRAUD_WINDOW_SETTER_ROLE` could set an arbitrarily large value, including values close to `type(uint256).max`.

**Impact:**  
If fraud window is set to an extremely large value (e.g., years or decades), all withdrawals would be stuck in PROCESSING state indefinitely, effectively bricking the withdrawal mechanism. While this requires a malicious or compromised admin, it's a single point of failure.

**Recommendation:**  
Add a maximum bound:
```solidity
uint256 private constant MAX_FRAUD_WINDOW_DURATION = 30 days;

function setFraudWindowDuration(uint256 durationSeconds) public onlyRole(FRAUD_WINDOW_SETTER_ROLE) {
    if (durationSeconds < MIN_FRAUD_WINDOW_DURATION) revert DurationTooShort();
    if (durationSeconds > MAX_FRAUD_WINDOW_DURATION) revert DurationTooLong();
    _setFraudWindowDuration(durationSeconds);
}
```

## Medium: deleteWithdrawMessage Enables Griefing of PROCESSING Withdrawals

**File:** `smart-contracts/src/v1/CanonicalBridge.sol`  
**Function:** `deleteWithdrawMessage()`

**Root Cause:**  
At lines 258-259, the function allows deletion of withdrawals in PROCESSING status (i.e., still within the fraud window). While access-controlled, this enables a malicious or compromised `WITHDRAW_CANCELLER_ROLE` holder to repeatedly grief users.

**Impact:**  
A malicious canceller could:
1. Wait for withdrawals to be authorized
2. Delete them just before they become PENDING
3. Force users to re-initiate withdrawals on L2
4. Repeat indefinitely, preventing legitimate withdrawals

This creates a poor user experience and potential censorship vector.

**Recommendation:**  
Consider only allowing cancellation of PENDING withdrawals (after fraud window), not PROCESSING ones, unless there's a specific fraud detection use case. Alternatively, add a time delay or require multiple signatures for cancellation:
```solidity
if (status != WithdrawStatus.PENDING) {
    revert CannotCancel();
}
```

## Medium: No ETH Recovery Mechanism in CanonicalBridge

**File:** `smart-contracts/src/v1/CanonicalBridge.sol`  
**Functions:** N/A (missing functionality)

**Root Cause:**  
The CanonicalBridge contract has no receive/fallback function and no admin function to recover ETH that might be sent directly to it (e.g., via selfdestruct from another contract, or mistaken direct transfers).

**Impact:**  
Any ETH sent directly to the CanonicalBridge (not through the `deposit()` function) will be permanently locked with no way to recover it. This includes:
- ETH from selfdestructed contracts
- Mistaken direct transfers
- Coinbase rewards if the address becomes a block proposer

**Recommendation:**  
Add an admin-controlled recovery function:
```solidity
function recoverStuckEth(address to, uint256 amount) 
    external 
    onlyRole(DEFAULT_ADMIN_ROLE) 
{
    if (to == NULL_ADDRESS) revert ZeroAddress();
    (bool success,) = payable(to).call{value: amount}("");
    if (!success) revert TransferFailed();
    emit EthRecovered(to, amount);
}
```

## Medium: Treasury Address Not Validated in Constructor

**File:** `smart-contracts/src/v1/CanonicalBridge.sol`  
**Function:** `constructor()`

**Root Cause:**  
At line 97, the `TREASURY` immutable variable is set without validation that the address is actually a contract or implements the `ITreasury` interface.

**Impact:**  
If an incorrect address is provided during deployment:
- The CanonicalBridge will be permanently deployed with the wrong treasury
- All deposits will fail or send ETH to the wrong address
- The contract would need to be redeployed, causing delays and potential fund loss
- Since TREASURY is immutable, this cannot be fixed post-deployment

**Recommendation:**  
Add validation in the constructor:
```solidity
constructor(address owner, address treasuryAddress) {
    if (treasuryAddress == NULL_ADDRESS) revert ZeroAddress();
    if (treasuryAddress.code.length == 0) revert NotContract();
    
    // Verify it implements required interface
    try ITreasury(treasuryAddress).DEPOSITOR_ROLE() returns (bytes32) {
        // Interface check passed
    } catch {
        revert InvalidTreasuryAddress();
    }
    
    TREASURY = treasuryAddress;
    // ... rest of constructor
}
```

## Low: Fee Can Equal Total Amount Leaving Recipient With Zero

**File:** `smart-contracts/src/v1/CanonicalBridge.sol`  
**Function:** `_authorizeWithdraw()` (modifier: `validWithdrawMessage`)

**Root Cause:**  
At line 76, the modifier only checks `message.feeWei > message.amountWei` but allows `message.feeWei == message.amountWei`.

**Impact:**  
A withdrawal message could be created where the fee equals the total amount, meaning the destination receives nothing and the fee receiver gets everything. While this might be intentional in some edge cases, it's more likely an error and creates poor user experience.

**Recommendation:**  
Add a strict inequality check or a maximum fee percentage:
```solidity
if (message.feeWei >= message.amountWei) {
    revert CanonicalBridgeTransactionRejected(message.withdrawId, "message.fee must be less than amount");
}
```

Or implement a maximum fee ratio:
```solidity
uint256 constant MAX_FEE_BPS = 1000; // 10%
if (message.feeWei > (message.amountWei * MAX_FEE_BPS) / 10000) {
    revert CanonicalBridgeTransactionRejected(message.withdrawId, "fee exceeds maximum");
}
```

## Low: Inefficient State Variable Usage in Upgrader

**File:** `smart-contracts/src/v1/upgrader/Upgrader0to1.sol`  
**Variable:** `treasuryOldOwner`

**Root Cause:**  
At line 24, `treasuryOldOwner` is declared as a state variable but is only used within the `executeUpgrade()` function (set at line 107, read at lines 185-189).

**Impact:**  
- Wastes gas by using SSTORE (20,000 gas) instead of memory
- Leaves stale data in storage after execution
- If `executeUpgrade()` is called multiple times (though it would fail), old data persists
- Makes the contract state less clean

**Recommendation:**  
Change to a local variable:
```solidity
function executeUpgrade(UpgradeParams calldata p) 
    external
    // ... modifiers ...
    returns (address newCanonicalBridge)
{
    checkTreasuryOwnership(p.treasuryProxy);
    checkPaused(p.treasuryProxy);
    checkPaused(p.oldEtherbridgeAddress);
    
    address treasuryOldOwner = Ownable2StepUpgradeable(p.treasuryProxy).owner(); // local var
    Ownable2StepUpgradeable(p.treasuryProxy).acceptOwnership();
    
    // ... rest of function ...
}
```

## Low: No Validation of Recipient Addresses' Receive Capability

**File:** `smart-contracts/src/v1/Treasury.sol`  
**Function:** `withdrawEth()`

**Root Cause:**  
The `addressInitialized` modifier (lines 49-52) only checks for `address(0)` but doesn't verify that the destination addresses can actually receive ETH. If `to` or `feeReceiver` are contracts without receive/fallback functions, the transfer will fail.

**Impact:**  
- Legitimate withdrawals will fail if recipient is a contract without receive capability
- No way to detect this beforehand, leading to failed transactions and wasted gas
- Poor user experience as users must retry with different addresses

**Recommendation:**  
While checking receive capability on-chain is difficult and gas-intensive, consider:
1. Adding clear documentation about this requirement
2. Implementing a try-catch pattern that provides clearer error messages:
```solidity
(success,) = payable(to).call{value: amountWei - feeWei}("");
if (!success) revert RecipientCannotReceiveETH(to);
(success,) = payable(feeReceiver).call{value: feeWei}("");
if (!success) revert FeeReceiverCannotReceiveETH(feeReceiver);
```

## Low: Upgrader Not Designed for Retry on Failure

**File:** `smart-contracts/src/v1/upgrader/Upgrader0to1.sol`  
**Function:** `executeUpgrade()`

**Root Cause:**  
The upgrade process is not idempotent. At line 108, the contract accepts ownership of the Treasury, transferring ownership from the old owner. If the function fails after this point (e.g., due to gas limit, revert in later steps), the ownership is transferred but the upgrade is incomplete with no clean way to retry.

**Impact:**  
- If upgrade fails mid-execution, Treasury ownership is with the Upgrader but upgrade is incomplete
- No rollback mechanism exists
- Retrying the upgrade would fail because ownership check at line 223 would fail (upgrader is already owner, not pending owner)
- Manual intervention required, potentially requiring a new upgrader contract

**Recommendation:**  
Design for idempotency or add explicit rollback capability:
```solidity
function rollback(address treasuryProxy, address originalOwner) 
    external 
    onlyRole(UPGRADER_ROLE) 
{
    Ownable2StepUpgradeable(treasuryProxy).transferOwnership(originalOwner);
}
```

Or make the upgrade function idempotent by checking current state before each operation.

## Low: Potential DoS with Large Withdraw Arrays

**File:** `smart-contracts/src/v1/CanonicalBridge.sol`  
**Function:** `authorizeWithdraws()`

**Root Cause:**  
At lines 168-170, the function iterates over an unbounded array of withdraw messages. Each iteration performs multiple storage writes (lines 205-206), making this expensive for large arrays.

**Impact:**  
- Very large arrays could exceed block gas limit, making the transaction fail
- Relayer could accidentally submit too many withdrawals at once
- No batching mechanism or pagination
- Failed transactions waste gas

**Recommendation:**  
Add a reasonable maximum batch size:
```solidity
uint256 private constant MAX_BATCH_SIZE = 100;

function authorizeWithdraws(WithdrawMessage[] calldata messages) 
    external
    override
    whenNotPaused
    onlyRole(WITHDRAW_AUTHORITY_ROLE)
{
    if (messages.length > MAX_BATCH_SIZE) {
        revert BatchTooLarge();
    }
    for (uint256 i = 0; i < messages.length; i++) {
        _authorizeWithdraw(messages[i]);
    }
}
```

## Informational: Unused PRECISION Constant

**File:** `smart-contracts/src/v1/CanonicalBridge.sol`  
**Line:** 28

**Root Cause:**  
The constant `PRECISION = 1e18` is defined but never used anywhere in the contract.

**Impact:**  
- Code bloat
- May indicate incomplete implementation or removed functionality
- Could confuse developers

**Recommendation:**  
Remove the unused constant or document why it exists:
```solidity
// Remove this line if not needed:
// uint256 private constant PRECISION = 1e18;
```

## Informational: Block Number Check Could Theoretically Be Bypassed at Genesis

**File:** `smart-contracts/src/v1/CanonicalBridge.sol`  
**Function:** `_authorizeWithdraw()`

**Root Cause:**  
At line 202-204, the code checks if `withdrawMsgIdProcessed[message.withdrawId] != 0` to detect duplicate withdraw IDs. However, `block.number` could theoretically be 0 at the genesis block.

**Impact:**  
This is purely theoretical as:
- These contracts won't be deployed at genesis block
- Even if deployed at block 0, line 206 would set the value to 0, which is handled
- No practical impact in real deployment

**Recommendation:**  
For absolute correctness, use a different sentinel value:
```solidity
mapping (uint64 withdrawMessageId => uint256 blockNumberPlus1) public override withdrawMsgIdProcessed;

// In _authorizeWithdraw:
if (withdrawMsgIdProcessed[message.withdrawId] != 0) {
    revert CanonicalBridgeTransactionRejected(message.withdrawId, "Message Id already exists");
}
withdrawMsgIdProcessed[message.withdrawId] = block.number + 1;
```

## Informational: Consider Event Emission for Role Grants in Deployer

**File:** `smart-contracts/script/v1/deploy/DeployV1.s.sol`  
**Function:** `run()`

**Root Cause:**  
The deployment script grants multiple critical roles (lines 43-50) but only logs addresses to console, not emitting on-chain events.

**Impact:**  
- Harder to audit role assignments on-chain
- Must rely on transaction traces to verify deployment
- Off-chain monitoring tools can't easily detect role grants

**Recommendation:**  
While AccessControl emits RoleGranted events, consider adding additional logging or using a deployment event that summarizes the configuration for easier verification.

## Informational: Missing Zero-Value Check for Withdrawal Amount

**File:** `smart-contracts/src/v1/CanonicalBridge.sol`  
**Function:** `_authorizeWithdraw()`

**Root Cause:**  
While the `validWithdrawMessage` modifier checks that `amountWei != 0` at line 70-71, there's no similar check in the Treasury.withdrawEth() or emergencyWithdraw() functions.

**Impact:**  
- Zero-value withdrawals could be processed, wasting gas
- Emergency withdrawals of 0 wei serve no purpose but cost gas
- Minor efficiency issue

**Recommendation:**  
Add validation where appropriate:
```solidity
// In Treasury.withdrawEth:
if (amountWei == 0) revert InvalidAmount();

// In Treasury.emergencyWithdraw:
if (amount == 0) revert InvalidAmount();
```

## Informational: Documentation Inconsistency in Version Number

**File:** `smart-contracts/src/v1/Treasury.sol`, `smart-contracts/src/v1/CanonicalBridge.sol`  
**Lines:** 29-31 (Treasury), 29-31 (CanonicalBridge)

**Root Cause:**  
Both contracts are in the `v1` folder but declare `MAJOR_VERSION = 2`. This could be confusing.

**Impact:**  
- Potential confusion about which version is deployed
- Version in code doesn't match folder structure
- Could lead to deployment mistakes

**Recommendation:**  
Add documentation clarifying the versioning scheme:
```solidity
// Version 2.0.0 - This is v2 of the Treasury (upgraded from v0)
// Located in v1 folder for deployment organization
uint8 private constant MAJOR_VERSION = 2;
```

Or align folder structure with version numbers.
