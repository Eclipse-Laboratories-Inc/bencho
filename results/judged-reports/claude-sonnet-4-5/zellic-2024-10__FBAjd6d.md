# Smart Contract Security Audit Report

## Critical: Reentrancy vulnerability in emergencyWithdraw function

**File:** `smart-contracts/src/v1/Treasury.sol`  
**Function:** `emergencyWithdraw` (lines 132-144)

**Root Cause:**  
The `emergencyWithdraw` function performs an external call to transfer ETH to `msg.sender` but lacks the `nonReentrant` modifier. This allows a malicious contract with the EMERGENCY_ROLE to recursively call `emergencyWithdraw` and drain the entire treasury balance in a single transaction.

**Impact:**  
An attacker with EMERGENCY_ROLE (or who compromises a key with this role) can drain all funds from the treasury through reentrancy. While the role itself already permits withdrawals, reentrancy enables atomic complete draining, bypassing monitoring systems that track per-transaction withdrawal amounts.

**Attack Scenario:**
1. Attacker contract with EMERGENCY_ROLE calls `emergencyWithdraw(50 ETH)` on treasury with 100 ETH balance
2. Treasury sends 50 ETH to attacker contract
3. Attacker's `receive()` function triggers and calls `emergencyWithdraw(50 ETH)` again
4. Balance check passes (50 < 50 is false), sends remaining 50 ETH
5. Treasury is fully drained in one transaction

**Recommendation:**  
Add the `nonReentrant` modifier to the `emergencyWithdraw` function:
```solidity
function emergencyWithdraw(uint256 amount) 
    external
    virtual 
    override
    nonReentrant  // Add this
    onlyRole(EMERGENCY_ROLE)
{
    // ... existing code
}
```

## Critical: Unprotected reinitialize function allows privilege escalation

**File:** `smart-contracts/src/v1/Treasury.sol`  
**Function:** `reinitialize` (lines 71-91)

**Root Cause:**  
The `reinitialize()` function lacks access control and grants `DEFAULT_ADMIN_ROLE` to `msg.sender` (line 90). If the UUPS upgrade is performed using `upgradeTo()` instead of `upgradeToAndCall()`, the reinitialize function remains uncalled, allowing anyone to invoke it and become an admin.

**Impact:**  
If the upgrade is performed incorrectly (using `upgradeTo` without immediately calling `reinitialize`), an attacker can front-run the legitimate initialization and grant themselves full administrative control over the treasury, including the ability to withdraw all funds, pause operations, and perform future upgrades.

**Recommendation:**  
Add access control to the `reinitialize` function to restrict who can call it:
```solidity
function reinitialize()
    external
    virtual
    override
    reinitializer(2)
    onlyRole(UPGRADER_ROLE)  // Add this check
{
    // ... existing code
}
```
Alternatively, ensure the function can only be called via `upgradeToAndCall` by checking that the caller has the UPGRADER_ROLE or is the contract itself (via delegatecall).

## Critical: Missing WITHDRAW_AUTHORITY_ROLE grant breaks withdrawals

**File:** `smart-contracts/script/v1/deploy/DeployV1.s.sol`  
**Function:** `run` (lines 24-69)

**Root Cause:**  
The deployment script grants `DEPOSITOR_ROLE` to the CanonicalBridge (line 50) but fails to grant `WITHDRAW_AUTHORITY_ROLE`. The bridge's `claimWithdrawal` function calls `ITreasury(TREASURY).withdrawEth()` which requires `WITHDRAW_AUTHORITY_ROLE` (Treasury.sol line 117).

**Impact:**  
All withdrawal claims will fail with an access control revert. Users who deposit funds to the bridge will be unable to withdraw them, resulting in locked funds and a completely non-functional bridge.

**Recommendation:**  
Add the missing role grant after line 50:
```solidity
_treasuryV1.grantRole(_treasuryV1.DEPOSITOR_ROLE(), address(canonicalBridgeV1));
_treasuryV1.grantRole(_treasuryV1.WITHDRAW_AUTHORITY_ROLE(), address(canonicalBridgeV1)); // Add this
```

## High: Missing fee validation in withdrawEth allows underflow

**File:** `smart-contracts/src/v1/Treasury.sol`  
**Function:** `withdrawEth` (lines 106-128)

**Root Cause:**  
The function does not validate that `feeWei <= amountWei` before performing the subtraction on line 123. While the CanonicalBridge validates this in its `validWithdrawMessage` modifier, other addresses with `WITHDRAW_AUTHORITY_ROLE` could call this function directly with invalid parameters.

**Impact:**  
Direct calls to `withdrawEth` with `feeWei > amountWei` will cause an arithmetic underflow revert (due to Solidity 0.8.21's overflow protection) with an unclear error message. This could be exploited to grief the system or indicate incorrect integration by other authorized contracts.

**Recommendation:**  
Add explicit validation with a clear error message:
```solidity
function withdrawEth(
    address to, 
    uint256 amountWei,
    address feeReceiver,
    uint256 feeWei
) 
    external
    nonReentrant
    whenNotPaused
    addressInitialized(to)
    addressInitialized(feeReceiver)
    onlyRole(WITHDRAW_AUTHORITY_ROLE)
    returns (bool success) 
{
    if (feeWei > amountWei) revert InvalidFee(); // Add this check
    if (address(this).balance < amountWei) {
        revert InsufficientFunds();
    }
    // ... rest of function
}
```

## High: Fraud window overflow enables permanent DoS

**File:** `smart-contracts/src/v1/CanonicalBridge.sol`  
**Function:** `_authorizeWithdraw` (lines 189-214)

**Root Cause:**  
Line 196 calculates `messageStartTime = block.timestamp + fraudWindowDuration` without checking for overflow. If `fraudWindowDuration` is set to a value near `type(uint256).max`, this addition will overflow and revert due to Solidity 0.8.21's built-in overflow protection.

**Impact:**  
An admin with `FRAUD_WINDOW_SETTER_ROLE` could set `fraudWindowDuration` to a value that causes `block.timestamp + fraudWindowDuration` to overflow, permanently preventing all future withdrawal authorizations and causing a complete DoS of the withdrawal functionality.

**Recommendation:**  
Add a maximum limit check in `setFraudWindowDuration`:
```solidity
uint256 private constant MAX_FRAUD_WINDOW_DURATION = 365 days;

function setFraudWindowDuration(uint256 durationSeconds) public onlyRole(FRAUD_WINDOW_SETTER_ROLE) {
    if (durationSeconds < MIN_FRAUD_WINDOW_DURATION) revert DurationTooShort();
    if (durationSeconds > MAX_FRAUD_WINDOW_DURATION) revert DurationTooLong(); // Add this
    _setFraudWindowDuration(durationSeconds);
}
```

## High: Unbounded loop in authorizeWithdraws enables gas DoS

**File:** `smart-contracts/src/v1/CanonicalBridge.sol`  
**Function:** `authorizeWithdraws` (lines 160-171)

**Root Cause:**  
The function iterates over an unbounded array of messages (line 168) without any upper limit check. A malicious or compromised relayer could submit a transaction with thousands of messages, causing the transaction to exceed the block gas limit.

**Impact:**  
- Legitimate relayer operations could fail if they accidentally submit too many messages
- Malicious relayer could grief the system by submitting large batches that can't be processed
- The function becomes unusable when batch sizes grow too large

**Recommendation:**  
Add a maximum batch size check:
```solidity
uint256 private constant MAX_BATCH_SIZE = 100;

function authorizeWithdraws(
    WithdrawMessage[] calldata messages
)
    external
    override
    whenNotPaused
    onlyRole(WITHDRAW_AUTHORITY_ROLE)
{
    if (messages.length > MAX_BATCH_SIZE) revert BatchTooLarge();
    for (uint256 i = 0; i < messages.length; i++) {
        _authorizeWithdraw(messages[i]);
    }
}
```

## High: No maximum fraud window allows permanent fund freezing

**File:** `smart-contracts/src/v1/CanonicalBridge.sol`  
**Function:** `setFraudWindowDuration` (lines 268-271)

**Root Cause:**  
The function only validates a minimum duration (line 269) but has no maximum limit. An admin could set `fraudWindowDuration` to an extremely large value (e.g., millions of years), effectively freezing all future withdrawals indefinitely.

**Impact:**  
A malicious or compromised admin with `FRAUD_WINDOW_SETTER_ROLE` could set the fraud window to a duration longer than any reasonable timeframe, permanently locking all deposited funds in the bridge. Users would be unable to withdraw for decades or centuries.

**Recommendation:**  
Add a maximum duration check:
```solidity
uint256 private constant MAX_FRAUD_WINDOW_DURATION = 30 days;

function setFraudWindowDuration(uint256 durationSeconds) public onlyRole(FRAUD_WINDOW_SETTER_ROLE) {
    if (durationSeconds < MIN_FRAUD_WINDOW_DURATION) revert DurationTooShort();
    if (durationSeconds > MAX_FRAUD_WINDOW_DURATION) revert DurationTooLong();
    _setFraudWindowDuration(durationSeconds);
}
```

## Medium: Unsafe low-level call in deposit function

**File:** `smart-contracts/src/v1/CanonicalBridge.sol`  
**Function:** `deposit` (lines 139-156)

**Root Cause:**  
Line 150 uses `abi.encodeWithSignature("depositEth()")` with a low-level call instead of calling the treasury through its interface. This is error-prone as typos in the signature string won't be caught at compile time.

**Impact:**  
If the function signature string has a typo or if the Treasury interface changes, the call will fail silently (revert with generic error). This makes the code harder to maintain and more prone to errors during upgrades.

**Recommendation:**  
Use the interface directly:
```solidity
function deposit(bytes32 recipient, uint256 amountWei)
    external
    payable
    virtual
    override
    whenNotPaused
    bytes32Initialized(recipient)
    validDepositAmount(amountWei)
    nonReentrant
{
    ITreasury(TREASURY).depositEth{value: amountWei}();
    
    uint256 amountGwei = amountWei / WEI_PER_LAMPORT;
    emit Deposited(msg.sender, recipient, amountWei, amountGwei);
}
```

## Medium: Withdrawal claims vulnerable to front-running

**File:** `smart-contracts/src/v1/CanonicalBridge.sol`  
**Function:** `claimWithdrawal` (lines 218-242)

**Root Cause:**  
The `claimWithdrawal` function has no access control (line 222), allowing anyone to claim a withdrawal once it's in PENDING status. An attacker can monitor the mempool and front-run legitimate claim transactions.

**Impact:**  
While funds still go to the correct `message.destination`, the original claimer wastes gas on a failed transaction. This creates a gas griefing vector where attackers can systematically front-run all claims, forcing legitimate users to pay for failed transactions.

**Recommendation:**  
Consider adding a permission check to allow only the destination address or relayers to claim:
```solidity
function claimWithdrawal(
    WithdrawMessage calldata message
)
    external
    override
    whenNotPaused
    nonReentrant
    validWithdrawMessage(message)
{
    if (msg.sender != message.destination && !hasRole(WITHDRAW_AUTHORITY_ROLE, msg.sender)) {
        revert Unauthorized();
    }
    // ... rest of function
}
```

## Medium: Deleted withdraw messages can be replayed

**File:** `smart-contracts/src/v1/CanonicalBridge.sol`  
**Function:** `deleteWithdrawMessage` (lines 248-264)

**Root Cause:**  
When a withdrawal message is deleted (lines 261-262), both `startTime[messageHash]` and `withdrawMsgIdProcessed[message.withdrawId]` are reset to 0. This allows the exact same message to be re-authorized in the future.

**Impact:**  
If a withdrawal is canceled due to suspected fraud, a malicious relayer can repeatedly re-authorize the same fraudulent withdrawal. While admins can continue canceling it, this creates an ongoing griefing attack that wastes admin time and gas, and increases the risk that a fraudulent withdrawal eventually succeeds.

**Recommendation:**  
Do not clear `withdrawMsgIdProcessed` when deleting a message:
```solidity
function deleteWithdrawMessage(
    WithdrawMessage calldata message
)
    external
    override
    validWithdrawMessage(message)
    onlyRole(WITHDRAW_CANCELLER_ROLE)
{
    bytes32 messageHash = withdrawMessageHash(message);
    WithdrawStatus status = withdrawMessageStatus(messageHash);
    if (status != WithdrawStatus.PENDING && status != WithdrawStatus.PROCESSING) {
        revert CannotCancel();
    }
    startTime[messageHash] = 0;
    // Do NOT clear: withdrawMsgIdProcessed[message.withdrawId] = 0;
    emit WithdrawMessageDeleted(msg.sender, message);
}
```

## Medium: Deployer retains permanent admin privileges

**File:** `smart-contracts/script/v1/deploy/DeployV1.s.sol`  
**Function:** `run` (lines 24-69)

**Root Cause:**  
The deployer wallet receives `DEFAULT_ADMIN_ROLE` on the CanonicalBridge (line 33) through the constructor, and this role is never revoked. Additionally, the deployer calls `reinitialize()` on the Treasury (line 39), granting them `DEFAULT_ADMIN_ROLE` on the Treasury as well (Treasury.sol line 90).

**Impact:**  
The deployer retains full administrative control over both contracts indefinitely, creating a centralization risk. If the deployer's private key is compromised or if the deployer is not the intended long-term admin, this poses a security vulnerability.

**Recommendation:**  
Add a cleanup step at the end of the deployment script to revoke the deployer's admin roles and transfer them to the intended admin address:
```solidity
// After all setup is complete
canonicalBridgeV1.revokeRole(canonicalBridgeV1.DEFAULT_ADMIN_ROLE(), deployerWallet.addr);
_treasuryV1.revokeRole(_treasuryV1.DEFAULT_ADMIN_ROLE(), deployerWallet.addr);

// Grant to intended admin
address intendedAdmin = vm.envAddress("ADMIN_ADDRESS");
canonicalBridgeV1.grantRole(canonicalBridgeV1.DEFAULT_ADMIN_ROLE(), intendedAdmin);
_treasuryV1.grantRole(_treasuryV1.DEFAULT_ADMIN_ROLE(), intendedAdmin);
```

## Medium: Upgrader grants admin with only manual revocation note

**File:** `smart-contracts/src/v1/upgrader/Upgrader0to1.sol`  
**Function:** `executeUpgrade` (lines 86-200)

**Root Cause:**  
Lines 125-126 grant `DEFAULT_ADMIN_ROLE` to `msg.sender` on both the treasury and bridge, with only a comment (line 124) noting "REVOKE manually if caller is not an authoritative multisig." There is no enforcement or automated revocation.

**Impact:**  
If the upgrader caller is a temporary deployment wallet rather than a multisig, and the manual revocation step is forgotten, an insecure address retains permanent admin privileges. This creates a centralization risk and potential security vulnerability.

**Recommendation:**  
Either:
1. Remove the automatic grant and require manual granting to the intended admin only
2. Add a parameter for the intended admin address and automatically revoke from msg.sender:
```solidity
// Add to UpgradeParams struct
address msgSenderAdmin;

// In executeUpgrade, after all checks pass
if (p.msgSenderAdmin != msg.sender) {
    AccessControl(p.treasuryProxy).revokeRole(DEFAULT_ADMIN_ROLE, msg.sender);
    AccessControl(newCanonicalBridge).revokeRole(DEFAULT_ADMIN_ROLE, msg.sender);
}
```

## Medium: Dual admin control after reinitialize

**File:** `smart-contracts/src/v1/Treasury.sol`  
**Function:** `reinitialize` (lines 71-91)

**Root Cause:**  
The function grants `DEFAULT_ADMIN_ROLE` to both the old owner (line 83) and the caller (line 90). This results in two addresses having full administrative control simultaneously.

**Impact:**  
Having multiple admins increases the attack surface - either address being compromised gives full control. Additionally, the two admins could perform conflicting actions, and there's no documented transition plan for when the old owner should be removed.

**Recommendation:**  
Document the dual-admin period clearly and add a function to cleanly transition admin privileges:
```solidity
// Add a function to complete the admin transition
function completeAdminTransition(address oldAdmin) 
    external 
    onlyRole(DEFAULT_ADMIN_ROLE) 
{
    if (!hasRole(DEFAULT_ADMIN_ROLE, oldAdmin)) revert NotAdmin();
    revokeRole(DEFAULT_ADMIN_ROLE, oldAdmin);
    emit AdminTransitionCompleted(oldAdmin, msg.sender);
}
```

## Medium: Emergency withdrawals bypass pause mechanism

**File:** `smart-contracts/src/v1/Treasury.sol`  
**Function:** `emergencyWithdraw` (lines 132-144)

**Root Cause:**  
The `emergencyWithdraw` function does not include the `whenNotPaused` modifier, unlike `depositEth` and `withdrawEth`. This allows emergency withdrawals even when the contract is paused.

**Impact:**  
If the contract is paused due to a security incident, emergency withdrawals can still proceed. This could be exploited if the EMERGENCY_ROLE is compromised during an incident, allowing funds to be drained while the system is supposedly frozen.

**Recommendation:**  
Consider whether emergency withdrawals should respect pause state. If they should (most secure):
```solidity
function emergencyWithdraw(uint256 amount) 
    external
    virtual 
    override
    whenNotPaused  // Add this
    onlyRole(EMERGENCY_ROLE)
{
    // ... existing code
}
```
If emergencies should work when paused, document this explicitly and ensure the EMERGENCY_ROLE is held by highly secure addresses only.

## Medium: Missing storage gap in upgradeable Treasury

**File:** `smart-contracts/src/v1/Treasury.sol`  
**Contract:** Treasury (lines 15-161)

**Root Cause:**  
The Treasury contract inherits from multiple OpenZeppelin upgradeable contracts but does not include a storage gap. If future versions add storage variables, they could conflict with storage used by parent contracts.

**Impact:**  
Future upgrades to Treasury (e.g., to v2 or v3) that add new storage variables could cause storage slot collisions if the parent contracts' storage layout changes or if new variables are added in the middle of the contract. This could lead to data corruption.

**Recommendation:**  
Add a storage gap at the end of the contract:
```solidity
contract Treasury is
    ITreasury,
    ISemVer,
    Initializable,
    AccessControlUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable,
    UUPSUpgradeable
{
    // ... existing code ...
    
    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[50] private __gap;
}
```

## Low: Version number inconsistency creates confusion

**File:** `smart-contracts/src/v1/Treasury.sol`  
**Lines:** 29, 94-96

**Root Cause:**  
The contract is located in `src/v1/` directory suggesting version 1, but declares `MAJOR_VERSION = 2` (line 29) and `getVersionComponents()` returns Version(2, 0, 0).

**Impact:**  
This creates confusion about the actual version of the contract. Integrators and auditors may be confused about whether this is v1 or v2, potentially leading to incorrect upgrade paths or integration issues.

**Recommendation:**  
Align the version number with the directory structure:
```solidity
uint8 private constant MAJOR_VERSION = 1; // Change from 2 to 1
uint8 private constant MINOR_VERSION = 0;
uint8 private constant PATCH_VERSION = 0;
```
Or if this truly is version 2.0.0, rename the directory from `v1/` to `v2/` and update all references.

## Low: StorageV1 struct declared but never used

**File:** `smart-contracts/src/v1/Treasury.sol`  
**Lines:** 40-43

**Root Cause:**  
The `StorageV1` struct is declared with an ERC7201 storage location annotation but is never actually used anywhere in the contract. The contract uses `OwnableStorage` instead (lines 24-26, 55-59).

**Impact:**  
This creates confusion about the contract's storage layout and could lead to errors if future developers attempt to use this struct. The unused struct wastes bytecode space and makes the code harder to understand.

**Recommendation:**  
Remove the unused struct:
```solidity
// Remove these lines:
// /// @custom:storage-location erc7201:eclipse.treasury.v1
// struct StorageV1 {
//     address etherBridgeAddress;
// }
```
Or if this struct is intended for future use, document why it's declared but unused.

## Informational: Unused constant PRECISION

**File:** `smart-contracts/src/v1/CanonicalBridge.sol`  
**Line:** 28

**Root Cause:**  
The constant `PRECISION = 1e18` is declared but never referenced anywhere in the contract.

**Impact:**  
Unused constants waste bytecode space and create confusion about the contract's intended precision handling.

**Recommendation:**  
Remove the unused constant:
```solidity
// Remove this line:
// uint256 private constant PRECISION = 1e18;
```

## Informational: Missing validation for treasury old owner

**File:** `smart-contracts/src/v1/upgrader/Upgrader0to1.sol`  
**Function:** `executeUpgrade` (lines 86-200)

**Root Cause:**  
After accepting ownership (line 108), the old owner is retrieved (line 107) and used to grant roles (lines 185-189), but there's no validation that `treasuryOldOwner` is not the zero address.

**Impact:**  
If the treasury somehow has a zero address as owner, roles would be granted to address(0), which is effectively burning those permissions. While unlikely, this could cause deployment failures.

**Recommendation:**  
Add a validation check:
```solidity
treasuryOldOwner = Ownable2StepUpgradeable(p.treasuryProxy).owner();
if (treasuryOldOwner == NULL_ADDRESS) {
    revert InvalidOldOwner();
}
Ownable2StepUpgradeable(p.treasuryProxy).acceptOwnership();
```

## Informational: No validation of implementation contract correctness

**File:** `smart-contracts/src/v1/upgrader/Upgrader0to1.sol`  
**Function:** `executeUpgrade` (lines 86-200)

**Root Cause:**  
The upgrader calls `upgradeToAndCall` with `p.newTreasuryImplementation` (line 111) but doesn't verify that this address contains the correct Treasury v1 implementation. A malicious admin could provide a backdoored implementation.

**Impact:**  
If a compromised or malicious admin provides an incorrect implementation address, the treasury could be upgraded to malicious code. While this requires compromised admin access, defense-in-depth suggests adding validation.

**Recommendation:**  
Add implementation validation:
```solidity
// Add at the start of executeUpgrade
bytes32 expectedCodeHash = keccak256(type(Treasury).runtimeCode);
bytes32 actualCodeHash;
assembly {
    actualCodeHash := extcodehash(p.newTreasuryImplementation)
}
if (actualCodeHash != expectedCodeHash) {
    revert InvalidImplementation();
}
```
Alternatively, deploy the implementation within the upgrader to ensure correctness.
