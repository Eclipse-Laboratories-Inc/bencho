# Security Audit Report

## Critical: Incorrect balance check in Treasury.withdrawEth allows funds to become stuck

**File:** `smart-contracts/src/v1/Treasury.sol`  
**Function:** `withdrawEth` (lines 106-129)

**Root Cause:**  
The balance check on line 120-122 requires `amountWei + feeWei` to be available in the treasury, but only `amountWei` is actually sent out (lines 124-126 send `amountWei - feeWei` to the recipient and `feeWei` to the fee receiver). According to the interface documentation, `amountWei` represents the gross withdrawal amount, and `feeWei` should be deducted from it, not added to it.

**Impact:**  
1. Withdrawals will fail even when the treasury has sufficient funds (requires extra `feeWei` beyond what's needed)
2. Over time, `feeWei` amounts accumulate as "stuck" funds in the treasury that are required for the balance check but never withdrawn
3. This creates an ever-growing buffer requirement that serves no purpose and could eventually cause legitimate withdrawals to fail

**Recommendation:**  
Change line 120 from:
```solidity
uint256 totalAmount = amountWei + feeWei;
if (address(this).balance < totalAmount) {
```
to:
```solidity
if (address(this).balance < amountWei) {
```

---

## Critical: withdrawMsgIdProcessed mapping never checked, allowing duplicate withdrawal IDs

**File:** `smart-contracts/src/v1/CanonicalBridge.sol`  
**Function:** `_authorizeWithdraw` (lines 187-206)

**Root Cause:**  
The `withdrawMsgIdProcessed` mapping is set to `true` on line 199 but is never checked before authorizing a withdrawal. The code only verifies that the message hash is unknown (line 195), but different `WithdrawMessage` structs with the same `withdrawId` but different parameters (e.g., different amounts or destinations) will have different hashes.

**Impact:**  
An attacker with `WITHDRAW_AUTHORITY_ROLE` could authorize multiple withdrawals with the same `withdrawId` but different parameters:
- `withdrawId=1, amountWei=100, destination=attacker`
- `withdrawId=1, amountWei=1000, destination=attacker`

Both would be accepted since they have different message hashes, allowing the attacker to claim multiple withdrawals using a single legitimate withdrawal ID from the rollup.

**Recommendation:**  
Add a check before line 195:
```solidity
if (withdrawMsgIdProcessed[message.withdrawId]) {
    revert CanonicalBridgeTransactionRejected(message.withdrawId, "Withdraw ID already processed");
}
```

---

## Critical: Upgrader contract retains privileged Treasury roles after upgrade

**File:** `smart-contracts/src/v1/upgrader/Upgrader0to1.sol`  
**Function:** `executeUpgrade` (lines 90-204)

**Root Cause:**  
After the Treasury is reinitialized on line 115-118, the upgrader contract (as the owner) receives multiple admin roles including `EMERGENCY_ROLE`, `UPGRADER_ROLE`, `PAUSER_ROLE`, and `STARTER_ROLE` (granted in `Treasury.reinitialize`). However, the role revocation code on lines 159-165 only revokes `DEFAULT_ADMIN_ROLE` from the Treasury. The upgrader retains `EMERGENCY_ROLE`, `UPGRADER_ROLE`, `PAUSER_ROLE`, and `STARTER_ROLE` on the Treasury contract.

**Impact:**  
- The upgrader contract permanently retains the ability to pause/unpause the Treasury
- The upgrader can perform emergency withdrawals, draining all Treasury funds
- The upgrader can perform future upgrades without authorization
- If the upgrader's private keys are compromised or the contract has vulnerabilities, the entire Treasury is at risk

**Recommendation:**  
Add revocations after line 159:
```solidity
AccessControl(p.treasuryProxy).revokeRole(PAUSER_ROLE, address(this));
AccessControl(p.treasuryProxy).revokeRole(STARTER_ROLE, address(this));
AccessControl(p.treasuryProxy).revokeRole(UPGRADER_ROLE, address(this));
AccessControl(p.treasuryProxy).revokeRole(EMERGENCY_ROLE, address(this));
```

---

## High: Treasury address not validated in CanonicalBridge constructor

**File:** `smart-contracts/src/v1/CanonicalBridge.sol`  
**Function:** `constructor` (lines 84-98)

**Root Cause:**  
The `treasuryAddress` parameter is directly assigned to the immutable `TREASURY` variable on line 95 without any validation to ensure it's a valid contract address or non-zero.

**Impact:**  
- If set to `address(0)`, all deposits will fail permanently since the contract is immutable
- If set to an EOA instead of the Treasury contract, deposited funds will be sent to an address that cannot execute the `depositEth()` function properly
- The contract would need to be redeployed, and users might lose funds in the meantime

**Recommendation:**  
Add validation in the constructor:
```solidity
if (treasuryAddress == NULL_ADDRESS) revert CanonicalBridgeTransactionRejected(0, "Treasury address cannot be zero");
// Optionally check if it's a contract
if (treasuryAddress.code.length == 0) revert CanonicalBridgeTransactionRejected(0, "Treasury must be a contract");
```

---

## High: Inconsistent success variable usage in Treasury.withdrawEth

**File:** `smart-contracts/src/v1/Treasury.sol`  
**Function:** `withdrawEth` (lines 106-129)

**Root Cause:**  
Lines 124 and 126 both use the same `success` variable to capture transfer results. The second call on line 126 overwrites the first call's result on line 124. While the function reverts on failure (line 125, 127), the return value on line 128 only reflects the second transfer's success status.

**Impact:**  
- If the first transfer succeeds but the second fails, the function correctly reverts, but the logic is confusing and error-prone
- The returned `success` value only indicates whether the second transfer succeeded, not both
- Future modifications might incorrectly rely on the `success` return value

**Recommendation:**  
Use separate variables or check success inline:
```solidity
(bool success1,) = payable(to).call{value: amountWei - feeWei}("");
if (!success1) revert TreasuryTransferFailed();
(bool success2,) = payable(feeReceiver).call{value: feeWei}("");
if (!success2) revert TreasuryTransferFailed();
return true;
```

---

## High: No mechanism to handle pending withdrawals during upgrade

**File:** `smart-contracts/src/v1/upgrader/Upgrader0to1.sol`  
**Function:** `executeUpgrade` (lines 90-204)

**Root Cause:**  
The upgrade process deploys a new `CanonicalBridge` contract and updates the Treasury, but provides no mechanism to migrate or preserve pending withdrawal authorizations from the old bridge contract to the new one.

**Impact:**  
- All pending withdrawals in the old bridge become inaccessible after the upgrade
- Users who had authorized withdrawals waiting for the fraud window to expire will lose access to those funds
- No way to verify or claim withdrawals that were authorized in the old system
- Funds corresponding to old pending withdrawals remain locked in the Treasury

**Recommendation:**  
Implement a migration function in the new CanonicalBridge that allows importing authorized withdrawal hashes from the old bridge, or document a clear process for handling pending withdrawals before initiating the upgrade.

---

## Medium: emergencyWithdraw sends to msg.sender without recipient parameter

**File:** `smart-contracts/src/v1/Treasury.sol`  
**Function:** `emergencyWithdraw` (lines 133-145)

**Root Cause:**  
The function hardcodes the recipient as `msg.sender` on line 142, without allowing the caller to specify a destination address.

**Impact:**  
- Limits flexibility during emergency situations where funds need to be sent to a specific safe address
- If called from a multisig contract, funds are sent to the multisig rather than a designated recovery address
- Makes it harder to perform secure emergency operations where funds should bypass the caller

**Recommendation:**  
Add a recipient parameter:
```solidity
function emergencyWithdraw(address recipient, uint256 amount) 
    external
    virtual 
    override 
    addressInitialized(recipient)
    onlyRole(EMERGENCY_ROLE)
{
    if (address(this).balance < amount) revert InsufficientFunds(); 
    (bool success,) = payable(recipient).call{value: amount}("");
    if (!success) revert TreasuryTransferFailed(); 
    emit EmergencyTreasuryWithdraw(recipient, amount);
}
```

---

## Medium: No maximum limit on fraud window duration

**File:** `smart-contracts/src/v1/CanonicalBridge.sol`  
**Function:** `setFraudWindowDuration` (lines 263-266)

**Root Cause:**  
The function validates a minimum duration of 1 day (line 264) but does not enforce a maximum duration. An administrator could set an extremely large value.

**Impact:**  
- Fraud window could be set to years or decades, effectively locking all future withdrawals indefinitely
- Users would have to wait an unreasonable amount of time to claim withdrawals
- Could be used maliciously or accidentally to DoS the withdrawal system
- No safeguard against fat-finger errors (e.g., entering nanoseconds instead of seconds)

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

---

## Medium: feeReceiver required to be non-zero even when fee is zero

**File:** `smart-contracts/src/v1/Treasury.sol`  
**Function:** `withdrawEth` (lines 106-129)

**Root Cause:**  
The `addressInitialized(feeReceiver)` modifier on line 116 requires `feeReceiver` to be a non-zero address, even in cases where `feeWei` is zero and no fee payment is necessary.

**Impact:**  
- Forces callers to provide a dummy non-zero address for `feeReceiver` even when not charging a fee
- Wastes gas by unnecessarily sending a zero-value transaction to `feeReceiver` (line 126)
- Creates confusing transaction history with zero-value transfers
- Reduces flexibility for zero-fee withdrawals

**Recommendation:**  
Only validate and transfer to `feeReceiver` when `feeWei > 0`:
```solidity
if (feeWei > 0) {
    if (feeReceiver == NULL_ADDRESS) revert ZeroAddress();
    (success,) = payable(feeReceiver).call{value: feeWei}("");
    if (!success) revert TreasuryTransferFailed();
}
```

---

## Medium: Multiple parties receive DEFAULT_ADMIN_ROLE without clear precedence

**File:** `smart-contracts/src/v1/upgrader/Upgrader0to1.sol`  
**Function:** `executeUpgrade` (lines 90-204)

**Root Cause:**  
During the upgrade process, `DEFAULT_ADMIN_ROLE` is granted to multiple parties:
- Line 129: `msg.sender` on Treasury
- Line 130: `msg.sender` on CanonicalBridge  
- Line 137: `p.bridgeAdmin` on CanonicalBridge
- Line 145: `p.treasuryAdmin` on Treasury
- Treasury.reinitialize also grants it to the old owner

**Impact:**  
- Unclear governance structure with multiple admin authorities
- No single source of truth for who controls admin functions
- Difficult to revoke or update admin access when multiple parties hold the role
- Potential for conflicts if admins attempt contradictory actions
- Security risk if any one admin's keys are compromised

**Recommendation:**  
Document the multi-admin architecture clearly, or implement a single admin pattern. If multiple admins are intentional, use a timelock or multisig for critical operations and clearly define the precedence/hierarchy in documentation.

---

## Low: depositEth call uses encodedWithSignature instead of direct call

**File:** `smart-contracts/src/v1/CanonicalBridge.sol`  
**Function:** `deposit` (lines 137-154)

**Root Cause:**  
Line 148 uses `abi.encodeWithSignature("depositEth()")` for the function call instead of calling the interface method directly or using `abi.encodeCall`.

**Impact:**  
- More expensive in gas (runtime string hashing vs. compile-time selector)
- No compile-time type checking; typos in function signature won't be caught until runtime
- Error-prone if the function signature changes in the interface
- Less readable and maintainable

**Recommendation:**  
Use the interface directly:
```solidity
ITreasury(TREASURY).depositEth{value: amountWei}();
```
Or use abi.encodeCall for better type safety:
```solidity
(success,) = payable(address(TREASURY)).call{value: amountWei}(
    abi.encodeCall(ITreasury.depositEth, ())
);
```

---

## Low: withdrawMsgIdProcessed not reset when withdrawal is cancelled

**File:** `smart-contracts/src/v1/CanonicalBridge.sol`  
**Function:** `deleteWithdrawMessage` (lines 252-259)

**Root Cause:**  
When a withdrawal is cancelled via `deleteWithdrawMessage`, the `startTime` mapping is reset to 0 (line 257), but `withdrawMsgIdProcessed[message.withdrawId]` remains `true`.

**Impact:**  
- Once a `withdrawId` is used and then cancelled, that same ID cannot be reused even after cancellation
- May prevent legitimate retry of a cancelled withdrawal with the same ID from the rollup side
- Could lead to confusion if the same withdrawal needs to be reauthorized

**Recommendation:**  
If reuse of withdrawn IDs after cancellation is desired, add:
```solidity
withdrawMsgIdProcessed[message.withdrawId] = false;
```
Otherwise, document that withdrawal IDs are permanently consumed even after cancellation.

---

## Low: No expiration mechanism for authorized withdrawals

**File:** `smart-contracts/src/v1/CanonicalBridge.sol`  
**Function:** `_authorizeWithdraw`, `claimWithdrawal`

**Root Cause:**  
Once a withdrawal passes the fraud window and enters `PENDING` status, it remains claimable indefinitely with no expiration time.

**Impact:**  
- Old authorized withdrawals accumulate in contract storage without cleanup mechanism
- Users who lose access to their keys have funds permanently locked
- No way to reclaim funds from abandoned/forgotten withdrawals
- Storage bloat from old withdrawal authorizations

**Recommendation:**  
Add an expiration time to withdrawal messages:
```solidity
uint256 constant WITHDRAWAL_EXPIRATION = 90 days;

function withdrawMessageStatus(bytes32 messageHash) public view override returns (WithdrawStatus) {
    uint256 startTime_ = startTime[messageHash];
    if (startTime_ == 0) return WithdrawStatus.UNKNOWN;
    if (startTime_ == NEVER) return WithdrawStatus.CLOSED;
    if (startTime_ > block.timestamp) return WithdrawStatus.PROCESSING;
    if (block.timestamp > startTime_ + WITHDRAWAL_EXPIRATION) return WithdrawStatus.CLOSED;
    return WithdrawStatus.PENDING;
}
```

---

## Informational: Redundant NULL_ADDRESS constant definitions

**File:** Multiple files

**Root Cause:**  
Both `CanonicalBridge.sol` (line 20), `Treasury.sol` (line 28), and `Upgrader0to1.sol` (line 14) define their own `NULL_ADDRESS` constant, and `Treasury.sol` also has `OWNABLE_STORAGE_LOCATION` defined inline.

**Impact:**  
- Code duplication across contracts
- Slight increase in deployment gas costs
- Maintenance overhead if the pattern needs to change

**Recommendation:**  
Create a shared constants library:
```solidity
library Constants {
    address internal constant NULL_ADDRESS = address(0);
    bytes32 internal constant NULL_BYTES32 = bytes32(0);
}
```

---

## Informational: Version numbers claim 2.0.0 in v1 directory

**File:** `smart-contracts/src/v1/CanonicalBridge.sol` (lines 29-31), `Treasury.sol` (lines 29-31)

**Root Cause:**  
Both contracts report version `2.0.0` but are located in the `v1` directory structure.

**Impact:**  
- Confusion about actual version
- Mismatch between directory naming and reported version
- May indicate improper version tracking or directory structure

**Recommendation:**  
Align version numbers with directory structure, or document the versioning scheme (e.g., directory is deployment version, contract version is implementation version).

---

## Informational: Anyone can trigger withdrawal claim on behalf of recipient

**File:** `smart-contracts/src/v1/CanonicalBridge.sol`  
**Function:** `claimWithdrawal` (lines 210-232)

**Root Cause:**  
The `claimWithdrawal` function can be called by anyone (no access control), as long as the withdrawal is in `PENDING` status. Funds always go to `message.destination` (line 222-226).

**Impact:**  
- Third parties can claim withdrawals on behalf of users, potentially disrupting user workflows
- MEV opportunities where front-runners claim withdrawals to collect the fee as the transaction submitter
- Users cannot control the timing of when their withdrawal is claimed
- Could interfere with smart contract recipients that expect to claim at a specific time

**Recommendation:**  
If strict control is desired, add a check:
```solidity
if (msg.sender != message.destination && msg.sender != message.feeReceiver) {
    revert Unauthorized();
}
```
Otherwise, document this behavior clearly for users.

---

## Informational: No batch claim function for withdrawals

**File:** `smart-contracts/src/v1/CanonicalBridge.sol`

**Root Cause:**  
Users must call `claimWithdrawal` separately for each authorized withdrawal. No batch function exists similar to `authorizeWithdraws`.

**Impact:**  
- Higher gas costs for users claiming multiple withdrawals
- More transactions needed, increasing blockchain congestion
- Poor user experience compared to batch operations

**Recommendation:**  
Add a batch claim function:
```solidity
function claimWithdrawals(WithdrawMessage[] calldata messages) 
    external 
    whenNotPaused 
{
    for (uint256 i = 0; i < messages.length; i++) {
        claimWithdrawal(messages[i]);
    }
}
```

---

## Informational: Upgrader constructor grants roles to msg.sender without parameter

**File:** `smart-contracts/src/v1/upgrader/Upgrader0to1.sol`  
**Function:** `constructor` (lines 74-77)

**Root Cause:**  
The deployer of the Upgrader contract automatically receives `DEFAULT_ADMIN_ROLE` and `UPGRADER_ROLE` without ability to specify who should receive these roles.

**Impact:**  
- Deployer must be the intended admin, or roles must be transferred after deployment
- Extra transaction needed if deployer is not the intended admin
- Potential security risk if deployment is done by a temporary/compromised account

**Recommendation:**  
Accept an admin address parameter:
```solidity
constructor(address admin) {
    if (admin == NULL_ADDRESS) revert NullAddress();
    _grantRole(DEFAULT_ADMIN_ROLE, admin);
    _grantRole(UPGRADER_ROLE, admin);
}
```

---

## Informational: Missing slippage protection for withdrawal fees

**File:** `smart-contracts/src/v1/CanonicalBridge.sol`  
**Function:** `claimWithdrawal` (lines 210-232)

**Root Cause:**  
The `feeWei` amount is fixed when the withdrawal is authorized. Users cannot specify a maximum acceptable fee or update it before claiming.

**Impact:**  
- Users are locked into fee amounts determined at authorization time
- No protection if fee market changes between authorization and claim
- Cannot negotiate better fees during the fraud window period

**Recommendation:**  
Consider allowing fee updates during the PROCESSING period, or add a maximum fee check that users can specify.

---

## Informational: No circuit breaker for withdrawal amount limits

**File:** `smart-contracts/src/v1/CanonicalBridge.sol`, `Treasury.sol`

**Root Cause:**  
Besides the pause functionality, there is no mechanism to limit withdrawal amounts per transaction or per time period during emergencies.

**Impact:**  
- If a vulnerability is discovered, attacker could drain all funds in a single transaction before pause is activated
- No rate limiting to slow down an ongoing attack
- All-or-nothing approach (either fully operational or fully paused)

**Recommendation:**  
Implement a daily/hourly withdrawal limit that can be adjusted by admins:
```solidity
uint256 public dailyWithdrawalLimit;
uint256 public withdrawnToday;
uint256 public lastWithdrawalReset;

function _checkWithdrawalLimit(uint256 amount) internal {
    if (block.timestamp >= lastWithdrawalReset + 1 days) {
        withdrawnToday = 0;
        lastWithdrawalReset = block.timestamp;
    }
    require(withdrawnToday + amount <= dailyWithdrawalLimit, "Daily limit exceeded");
    withdrawnToday += amount;
}
```
