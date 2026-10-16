# Security Audit Report

## Critical: Missing WITHDRAW_AUTHORITY_ROLE Grant in Deployment Script

**File:** `smart-contracts/script/v1/deploy/DeployV1.s.sol`  
**Function:** `run()` (lines 24-69)

**Root Cause:**  
The deployment script fails to grant `WITHDRAW_AUTHORITY_ROLE` to the `CanonicalBridge` contract on the `Treasury`. While the script grants `DEPOSITOR_ROLE` at line 50, it omits the critical `WITHDRAW_AUTHORITY_ROLE` grant.

**Impact:**  
All withdrawal claims will fail. When users call `CanonicalBridge.claimWithdrawal()`, it attempts to call `Treasury.withdrawEth()` (line 234 in CanonicalBridge.sol), which requires `WITHDRAW_AUTHORITY_ROLE` (line 117 in Treasury.sol). Without this role, the transaction will revert with an access control error, making the bridge completely non-functional for withdrawals.

**Recommendation:**  
Add the following after line 50 in DeployV1.s.sol:
```solidity
_treasuryV1.grantRole(_treasuryV1.WITHDRAW_AUTHORITY_ROLE(), address(canonicalBridgeV1));
```

## High: No Maximum Fraud Window Duration

**File:** `smart-contracts/src/v1/CanonicalBridge.sol`  
**Function:** `setFraudWindowDuration()` (lines 268-271)

**Root Cause:**  
The function validates that the fraud window duration is at least `MIN_FRAUD_WINDOW_DURATION` (1 day) but does not enforce a maximum limit. An admin with `FRAUD_WINDOW_SETTER_ROLE` can set an arbitrarily large value.

**Impact:**  
A malicious or compromised admin could set `fraudWindowDuration` to an extremely large value (e.g., `type(uint256).max - block.timestamp`), effectively freezing all future withdrawals indefinitely. Since `startTime` is calculated as `block.timestamp + fraudWindowDuration` (line 196), withdrawals would never reach `PENDING` status and could never be claimed.

**Recommendation:**  
Add a maximum fraud window duration check:
```solidity
uint256 private constant MAX_FRAUD_WINDOW_DURATION = 30 days;

function setFraudWindowDuration(uint256 durationSeconds) public onlyRole(FRAUD_WINDOW_SETTER_ROLE) {
    if (durationSeconds < MIN_FRAUD_WINDOW_DURATION) revert DurationTooShort();
    if (durationSeconds > MAX_FRAUD_WINDOW_DURATION) revert DurationTooLong();
    _setFraudWindowDuration(durationSeconds);
}
```

## High: Withdrawal ID Reuse After Deletion

**File:** `smart-contracts/src/v1/CanonicalBridge.sol`  
**Function:** `deleteWithdrawMessage()` (lines 248-264)

**Root Cause:**  
When a withdrawal message is deleted, the function resets both `startTime[messageHash] = 0` (line 261) and `withdrawMsgIdProcessed[message.withdrawId] = 0` (line 262). This allows the withdrawal ID to be reused for a different message.

**Impact:**  
The `withdrawMsgIdProcessed` mapping is designed to ensure each withdrawal ID from L2 is processed exactly once, preventing replay attacks. By allowing ID reuse after deletion:

1. A legitimate withdrawal with ID=X can be deleted by an admin
2. The same ID=X can be authorized for a completely different withdrawal message
3. This breaks the L1/L2 state consistency and the uniqueness guarantee
4. Users whose withdrawals are deleted may find their withdrawal IDs "stolen" by different messages
5. The original legitimate withdrawal becomes unprocessable

**Recommendation:**  
Do not reset `withdrawMsgIdProcessed` when deleting a message. Only reset `startTime`:
```solidity
function deleteWithdrawMessage(WithdrawMessage calldata message) external override validWithdrawMessage(message) onlyRole(WITHDRAW_CANCELLER_ROLE) {
    bytes32 messageHash = withdrawMessageHash(message);
    WithdrawStatus status = withdrawMessageStatus(messageHash);
    if (status != WithdrawStatus.PENDING && status != WithdrawStatus.PROCESSING) {
        revert CannotCancel();
    }
    startTime[messageHash] = 0;
    // Do NOT reset withdrawMsgIdProcessed to preserve ID uniqueness
    emit WithdrawMessageDeleted(msg.sender, message);
}
```

## High: Upgrader Contract May Retain Admin Privileges

**File:** `smart-contracts/src/v1/upgrader/Upgrader0to1.sol`  
**Function:** `executeUpgrade()` (lines 86-200)

**Root Cause:**  
The upgrade function does not validate that the admin addresses (particularly `treasuryAdmin` and `bridgeAdmin`) are different from the upgrader contract's own address. If `treasuryAdmin` is set to `address(this)`, the upgrader receives roles at lines 141-145 which are never revoked.

**Impact:**  
If the deployer accidentally sets `treasuryAdmin = address(upgrader)`:
- The upgrader receives `PAUSER_ROLE`, `STARTER_ROLE`, `UPGRADER_ROLE`, and `EMERGENCY_ROLE` on the Treasury (lines 142-145)
- Only `DEFAULT_ADMIN_ROLE` is revoked from the upgrader (line 155)
- The upgrader retains permanent operational control over the Treasury
- Since the upgrader is not designed for ongoing operation, these privileges would be inaccessible but also irrevocable

**Recommendation:**  
Add validation to prevent admin addresses from being the upgrader contract:
```solidity
function executeUpgrade(UpgradeParams calldata p) external ... {
    // Existing validations...
    
    if (p.treasuryAdmin == address(this)) revert InvalidAdmin();
    if (p.bridgeAdmin == address(this)) revert InvalidAdmin();
    if (p.bridgeTroll == address(this)) revert InvalidAdmin();
    if (p.trustedRelayer == address(this)) revert InvalidAdmin();
    
    // Continue with upgrade...
}
```

## High: Insecure Ownership Storage Assumption in Reinitialize

**File:** `smart-contracts/src/v1/Treasury.sol`  
**Function:** `reinitialize()` (lines 71-91)

**Root Cause:**  
The function reads `oldOwner` from a hardcoded storage slot (line 77) assuming the previous contract version used OpenZeppelin's `Ownable` pattern with that exact storage layout. There is no validation that this assumption is correct.

**Impact:**  
If the previous Treasury version:
- Used a different storage layout
- Stored the owner at a different location
- Had corrupted or zero data at that slot

Then either:
1. The function reverts if `oldOwner == NULL_ADDRESS` (line 78-80), preventing the upgrade
2. Worse, it grants `DEFAULT_ADMIN_ROLE` and operational roles to an arbitrary address read from that storage slot, potentially to address(0) (if it bypasses the check due to a race condition) or to an unrelated address

**Recommendation:**  
Add explicit version checking before upgrade, or pass the expected old owner as a parameter and validate against storage:
```solidity
function reinitialize(address expectedOldOwner) external virtual override reinitializer(2) {
    address oldOwner = _getOwnableStorage()._owner;
    if (oldOwner != expectedOldOwner) revert OwnerMismatch();
    if (oldOwner == NULL_ADDRESS) revert InvalidInitialization();
    // Continue...
}
```

## Medium: Emergency Withdraw Missing Reentrancy Protection

**File:** `smart-contracts/src/v1/Treasury.sol`  
**Function:** `emergencyWithdraw()` (lines 132-144)

**Root Cause:**  
The `emergencyWithdraw` function makes an external call to send ETH (line 141) but does not have the `nonReentrant` modifier, unlike `withdrawEth` which does (line 113).

**Impact:**  
While `emergencyWithdraw` is access-controlled to `EMERGENCY_ROLE`, if this role is granted to a contract:
1. The contract could reenter `emergencyWithdraw` during the ETH transfer
2. Multiple withdrawals could be executed before the balance check is reevaluated
3. This allows draining more than the specified `amount` per call

Note: The `EMERGENCY_ROLE` is already trusted to withdraw all funds, but reentrancy violates the contract's invariants and could interfere with other operations or events.

**Recommendation:**  
Add the `nonReentrant` modifier to maintain consistency:
```solidity
function emergencyWithdraw(uint256 amount) 
    external
    virtual 
    override 
    nonReentrant  // Add this
    onlyRole(EMERGENCY_ROLE)
{
    if (address(this).balance < amount) revert InsufficientFunds(); 
    (bool success,) = payable(msg.sender).call{value: amount}("");
    if (!success) revert TreasuryTransferFailed(); 
    emit EmergencyTreasuryWithdraw(msg.sender, amount);
}
```

## Medium: String-Based Function Selector in Deposit

**File:** `smart-contracts/src/v1/CanonicalBridge.sol`  
**Function:** `deposit()` (line 150)

**Root Cause:**  
The function uses `abi.encodeWithSignature("depositEth()")` which is a string-based encoding that is not checked at compile time.

**Impact:**  
- If there's a typo in the function signature string, all deposits will fail silently
- The error would only be discovered at runtime
- String-based selectors are more expensive in gas than selector-based encoding
- The failure message "failed to transfer funds to the treasury" is misleading as the funds were sent but the call failed

**Recommendation:**  
Use the interface-based call or selector-based encoding:
```solidity
// Option 1: Direct interface call
ITreasury(TREASURY).depositEth{value: amountWei}();

// Option 2: Selector-based encoding
(success,) = payable(address(TREASURY)).call{value: amountWei}(
    abi.encodeWithSelector(ITreasury.depositEth.selector)
);
```

## Medium: Fee Can Equal Withdrawal Amount

**File:** `smart-contracts/src/v1/CanonicalBridge.sol`  
**Function:** `validWithdrawMessage` modifier (lines 63-83)

**Root Cause:**  
The modifier validates that `message.feeWei > message.amountWei` (lines 76-78) but allows `message.feeWei == message.amountWei`.

**Impact:**  
When the fee equals the withdrawal amount:
- Treasury.withdrawEth sends `amountWei - feeWei = 0` to the destination (line 123)
- Treasury.withdrawEth sends `feeWei = amountWei` to the fee receiver (line 125)
- The intended recipient receives nothing while the fee receiver gets everything

This could occur due to:
1. Malicious relayer manipulation (if relayers can set fees)
2. Incorrect fee calculation on L2
3. Edge case bugs in withdrawal processing

Users would see their withdrawal "succeed" but receive 0 ETH.

**Recommendation:**  
Enforce that fees must be strictly less than the amount and leave something for the recipient:
```solidity
if (message.feeWei >= message.amountWei) {
    revert CanonicalBridgeTransactionRejected(message.withdrawId, "fee must be less than amount");
}
```

## Medium: Unchecked Treasury Address in Constructor

**File:** `smart-contracts/src/v1/CanonicalBridge.sol`  
**Function:** Constructor (lines 86-100)

**Root Cause:**  
The constructor accepts `treasuryAddress` and sets it as the immutable `TREASURY` (line 97) but only validates that it is non-zero (implied by the modifier, though not shown). There is no validation that it is a contract or implements the `ITreasury` interface.

**Impact:**  
If an incorrect address is provided during deployment:
- Deposits will fail when trying to call `depositEth()` on a non-contract or incompatible contract
- Withdrawals will fail when trying to call `withdrawEth()`
- The bridge becomes permanently non-functional since `TREASURY` is immutable
- The entire bridge would need to be redeployed

**Recommendation:**  
Validate that the treasury address is a contract and optionally validate it supports the expected interface:
```solidity
constructor(address owner, address treasuryAddress) {
    if (treasuryAddress == NULL_ADDRESS) revert ZeroAddress();
    if (treasuryAddress.code.length == 0) revert NotContract();
    
    // Optional: validate interface support
    try ITreasury(treasuryAddress).DEPOSITOR_ROLE() returns (bytes32) {
        // Interface check passed
    } catch {
        revert InvalidTreasury();
    }
    
    // Continue with existing logic...
}
```

## Medium: Unused Storage Variable Declared

**File:** `smart-contracts/src/v1/Treasury.sol`  
**Lines:** 40-43

**Root Cause:**  
The contract declares a `StorageV1` struct with an `etherBridgeAddress` field but never uses it anywhere in the code. There is no getter, setter, or any reference to this variable.

**Impact:**  
- The declared storage slot is wasted
- Future developers might inadvertently use this slot, not realizing it was meant for something else
- If future upgrades add fields to this struct, they might conflict with accidentally used storage
- Creates confusion about the contract's intended functionality

**Recommendation:**  
Either remove the unused storage declaration or implement the intended functionality:
```solidity
// If not needed, remove:
// struct StorageV1 {
//     address etherBridgeAddress;
// }

// Or if it should track the bridge:
function setEtherBridge(address bridge) external onlyRole(DEFAULT_ADMIN_ROLE) {
    // Implementation
}
```

## Low: Block Number Stored But Never Used

**File:** `smart-contracts/src/v1/CanonicalBridge.sol`  
**Line:** 206

**Root Cause:**  
The function stores `withdrawMsgIdProcessed[message.withdrawId] = block.number` but this block number is never read anywhere. The only check is whether the value is non-zero (line 202).

**Impact:**  
- Wastes gas storing a full `uint256` block number when a boolean would suffice
- Creates confusion about whether the block number has some significance
- If block 0 is somehow processed (impossible in practice), the check would incorrectly pass

**Recommendation:**  
Either use the block number for something (e.g., auditing, time-based validations) or change to a boolean:
```solidity
mapping(uint64 withdrawMessageId => bool processed) public withdrawMsgIdProcessed;

// In _authorizeWithdraw:
if (withdrawMsgIdProcessed[message.withdrawId]) {
    revert CanonicalBridgeTransactionRejected(message.withdrawId, "Message Id already exists");
}
withdrawMsgIdProcessed[message.withdrawId] = true;
```

## Low: Centralizzation Risk with Trusted Relayer

**File:** `smart-contracts/src/v1/CanonicalBridge.sol`  
**Function:** `authorizeWithdraw()` (lines 175-184)

**Root Cause:**  
The `WITHDRAW_AUTHORITY_ROLE` (typically a relayer) has complete control over withdrawal message contents including amounts, recipients, and fees. There is no cryptographic proof or verification of L2 state.

**Impact:**  
A malicious or compromised relayer could:
- Change withdrawal recipients to steal funds
- Inflate fees to themselves
- Authorize withdrawals that never occurred on L2
- Refuse to relay legitimate withdrawals (censorship)

This is a trust assumption inherent to the design, but users should be aware of this centralization risk.

**Recommendation:**  
Document this trust assumption clearly. Consider:
- Implementing a multi-signature requirement for withdrawals
- Adding cryptographic proofs of L2 state (e.g., Merkle proofs against a published L2 state root)
- Implementing a challenge mechanism where users can dispute incorrect withdrawals
- Using multiple independent relayers with a consensus mechanism

## Low: Emergency Role Can Fail on Contract Recipients

**File:** `smart-contracts/src/v1/Treasury.sol`  
**Function:** `emergencyWithdraw()` (lines 132-144)

**Root Cause:**  
The function sends ETH to `msg.sender` (line 141) without checking if the recipient can receive ETH. If `EMERGENCY_ROLE` is granted to a contract without a `receive()` or `fallback()` function, withdrawals will always fail.

**Impact:**  
Emergency withdrawals would be impossible if the role is held by an incompatible contract, potentially locking funds during critical situations. This defeats the purpose of the emergency mechanism.

**Recommendation:**  
Either:
1. Allow specifying a recipient address:
```solidity
function emergencyWithdraw(uint256 amount, address payable recipient) external virtual override onlyRole(EMERGENCY_ROLE) {
    if (address(this).balance < amount) revert InsufficientFunds();
    (bool success,) = recipient.call{value: amount}("");
    if (!success) revert TreasuryTransferFailed();
    emit EmergencyTreasuryWithdraw(recipient, amount);
}
```

2. Or document that `EMERGENCY_ROLE` should only be granted to EOAs or compatible contracts.

## Low: Version Numbers Not Enforced

**Files:** `smart-contracts/src/v1/Treasury.sol` (lines 29-31), `smart-contracts/src/v1/CanonicalBridge.sol` (lines 29-31)

**Root Cause:**  
Both contracts declare version constants (2.0.0) but there is no enforcement mechanism to ensure these are updated during upgrades or that they match expected values.

**Impact:**  
- After future upgrades, the version numbers might not reflect the actual contract version
- No programmatic way to verify contract versions before upgrade
- Confusion about which version is actually deployed

**Recommendation:**  
Implement version validation in upgrade functions:
```solidity
function _authorizeUpgrade(address newImplementation) internal view virtual override onlyRole(UPGRADER_ROLE) {
    // Optionally validate new implementation version is higher
    Version memory newVersion = Treasury(newImplementation).getVersionComponents();
    Version memory currentVersion = this.getVersionComponents();
    require(
        newVersion.major > currentVersion.major || 
        (newVersion.major == currentVersion.major && newVersion.minor > currentVersion.minor),
        "Version must increase"
    );
}
```

## Informational: Redundant Success Variable Reuse

**File:** `smart-contracts/src/v1/Treasury.sol`  
**Function:** `withdrawEth()` (lines 106-128)

**Root Cause:**  
The same `success` variable is reused for both ETH transfers (lines 123 and 125) and also serves as the return value.

**Impact:**  
While functionally correct (due to revert-on-failure), this pattern:
- Makes the code slightly harder to audit
- Could be confusing if either check is removed in the future
- The return value is always `true` when reached (since failures revert)

**Recommendation:**  
Use separate variables for clarity or acknowledge that the return is always true:
```solidity
function withdrawEth(...) external ... returns (bool) {
    if (address(this).balance < amountWei) {
        revert InsufficientFunds();
    }
    
    (bool success1,) = payable(to).call{value: amountWei - feeWei}("");
    if (!success1) revert TreasuryTransferFailed();
    
    (bool success2,) = payable(feeReceiver).call{value: feeWei}("");
    if (!success2) revert TreasuryTransferFailed();
    
    emit TreasuryWithdrawal(msg.sender, to, amountWei, feeReceiver, feeWei);
    return true; // Explicit return for clarity
}
```

## Informational: Deployer Receives Automatic Admin Role

**File:** `smart-contracts/src/v1/upgrader/Upgrader0to1.sol`  
**Lines:** 125-126

**Root Cause:**  
The upgrade function automatically grants `DEFAULT_ADMIN_ROLE` to `msg.sender` with a comment "REVOKE manually if caller is not an authoritative multisig."

**Impact:**  
- Requires manual post-deployment action that could be forgotten
- If the deployer is a regular EOA or compromised, they have full admin control
- Creates a window where an untrusted party has admin privileges

**Recommendation:**  
Either:
1. Require explicit confirmation parameter:
```solidity
function executeUpgrade(UpgradeParams calldata p, bool grantCallerAdmin) external ... {
    // ...
    if (grantCallerAdmin) {
        AccessControl(p.treasuryProxy).grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        AccessControl(newCanonicalBridge).grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }
    // ...
}
```

2. Or don't grant to `msg.sender` at all, relying only on the specified admins.

## Informational: Potential Gas Griefing in Withdrawal Claims

**File:** `smart-contracts/src/v1/Treasury.sol`  
**Function:** `withdrawEth()` (lines 123, 125)

**Root Cause:**  
The external calls to transfer ETH do not limit gas, forwarding all available gas to the recipient contracts.

**Impact:**  
- A malicious recipient could have a `receive()` function that consumes excessive gas
- While this doesn't steal funds (the call either succeeds or fails), it could waste the caller's gas
- For users claiming their own withdrawals, they would grief themselves
- For third-party relayers claiming on behalf of users, this could be a DoS vector

**Recommendation:**  
Consider adding gas limits to the external calls:
```solidity
(success,) = payable(to).call{value: amountWei - feeWei, gas: 10000}("");
```

However, this could break compatibility with some valid recipient contracts. Document expected recipient behavior instead.

## Informational: Same Address Can Be Destination and Fee Receiver

**File:** `smart-contracts/src/v1/CanonicalBridge.sol`  
**Validation:** `validWithdrawMessage` modifier

**Root Cause:**  
There is no validation preventing `message.destination` from equaling `message.feeReceiver`.

**Impact:**  
If both addresses are the same:
- Treasury makes two separate transfers to the same address
- Total received is still correct: `(amountWei - feeWei) + feeWei = amountWei`
- But it wastes gas making two transfers instead of one
- Events and accounting treat them separately even though they're the same recipient

**Recommendation:**  
Either accept this as valid (user pays their own fees) or optimize for the common case:
```solidity
if (message.destination == message.feeReceiver) {
    // Single transfer optimization
    Treasury.withdrawEth(message.destination, message.amountWei, message.destination, 0);
} else {
    // Current two-transfer flow
    Treasury.withdrawEth(message.destination, message.amountWei, message.feeReceiver, message.feeWei);
}
```
