# Security Audit Report

## Critical: Incorrect Balance Check in Treasury.withdrawEth Causes Fund Lockup

**File:** `Treasury.sol`  
**Function:** `withdrawEth` (lines 106-129)

**Root Cause:**  
The balance check at line 120 validates that the treasury has `amountWei + feeWei`:
```solidity
uint256 totalAmount = amountWei + feeWei;
if (address(this).balance < totalAmount) {
    revert InsufficientFunds();
}
```

However, the actual transfers only send `amountWei` total:
- Line 124: sends `amountWei - feeWei` to `to`
- Line 126: sends `feeWei` to `feeReceiver`
- Total sent: `(amountWei - feeWei) + feeWei = amountWei`

**Impact:**  
1. Withdrawals require `amountWei + feeWei` balance but only withdraw `amountWei`, causing `feeWei` to accumulate as stuck funds over time
2. Legitimate withdrawals will revert when treasury has sufficient funds (`>= amountWei`) but less than `amountWei + feeWei`
3. This creates an accounting discrepancy where the required balance exceeds actual needs

**Recommendation:**  
Change line 120 to check only the actual amount needed:
```solidity
if (address(this).balance < amountWei) {
    revert InsufficientFunds();
}
```

## Critical: Withdraw ID Replay Attack - withdrawMsgIdProcessed Never Checked

**File:** `CanonicalBridge.sol`  
**Function:** `_authorizeWithdraw` (line 199), `authorizeWithdraw`, `authorizeWithdraws`

**Root Cause:**  
Line 199 sets `withdrawMsgIdProcessed[message.withdrawId] = true` but this mapping is never checked in any function. The contract only validates uniqueness based on `withdrawMessageHash`, not `withdrawId`.

**Impact:**  
1. The same `withdrawId` can be reused in multiple different withdraw messages with different parameters (amount, destination, etc.)
2. This defeats the purpose of having unique withdraw IDs from the rollup
3. An attacker with WITHDRAW_AUTHORITY_ROLE could authorize multiple withdrawals with the same ID by varying other fields (destination, amount, fee)
4. This breaks the invariant that each rollup withdrawal ID should only be processed once

**Recommendation:**  
Add a check before setting the mapping:
```solidity
if (withdrawMsgIdProcessed[message.withdrawId]) {
    revert CanonicalBridgeTransactionRejected(message.withdrawId, "Withdraw ID already processed");
}
```

## High: Missing Fee Validation in Treasury Allows Underflow DoS

**File:** `Treasury.sol`  
**Function:** `withdrawEth` (lines 106-129)

**Root Cause:**  
The Treasury contract does not validate that `feeWei <= amountWei`. It relies on the caller (CanonicalBridge) to perform this validation (CanonicalBridge.sol line 77-79). However, Treasury exposes `withdrawEth` to any address with `WITHDRAW_AUTHORITY_ROLE`.

**Impact:**  
1. If any contract other than CanonicalBridge receives `WITHDRAW_AUTHORITY_ROLE`, it could call `withdrawEth` with `feeWei > amountWei`
2. Line 124 would attempt `amountWei - feeWei`, causing integer underflow and revert
3. This allows DoS of the withdrawal system
4. Defense-in-depth is violated by relying on caller validation

**Recommendation:**  
Add validation in Treasury.withdrawEth:
```solidity
if (feeWei > amountWei) {
    revert InvalidFeeAmount();
}
```

## High: Inconsistent Role Name Between CanonicalBridge and Treasury

**File:** `CanonicalBridge.sol` (line 35), `Treasury.sol` (line 34), `Upgrader0to1.sol` (line 16)

**Root Cause:**  
CanonicalBridge defines:
```solidity
bytes32 public constant WITHDRAW_AUTHORITY_ROLE = keccak256("WithdrawAuthority");
```

Treasury defines:
```solidity
bytes32 public constant WITHDRAW_AUTHORITY_ROLE = keccak256("WithdrawalAuthority");
```

Note "WithdrawAuthority" vs "WithdrawalAuthority" - these produce different keccak256 hashes despite having the same variable name.

**Impact:**  
1. The role granted to CanonicalBridge in the Upgrader (line 134) uses the Treasury's role definition
2. This creates confusion and potential for role management errors
3. Developers may incorrectly assume these are the same role when they are cryptographically different
4. Future integrations may grant the wrong role hash

**Recommendation:**  
Standardize the role name string across all contracts. Use either "WithdrawAuthority" or "WithdrawalAuthority" consistently.

## High: Front-Running Risk in claimWithdrawal Function

**File:** `CanonicalBridge.sol`  
**Function:** `claimWithdrawal` (lines 210-232)

**Root Cause:**  
The `claimWithdrawal` function has no caller restrictions - anyone can call it with a valid withdraw message. While funds still go to `message.destination`, this allows third parties to trigger withdrawals.

**Impact:**  
1. Users may want to delay claiming for tax optimization or timing reasons
2. Malicious actors can force withdrawals at inopportune times (griefing)
3. If `message.destination` is a contract that rejects ETH transfers, an attacker can DoS the withdrawal by repeatedly attempting to claim
4. Front-runners could extract MEV by timing claims or manipulating gas prices

**Recommendation:**  
Restrict claimWithdrawal to either the destination address or authorized relayers:
```solidity
if (msg.sender != message.destination && !hasRole(WITHDRAW_CLAIMER_ROLE, msg.sender)) {
    revert Unauthorized();
}
```

## High: Missing Lamport Divisibility Validation for Withdrawal Amounts

**File:** `CanonicalBridge.sol`  
**Function:** `validWithdrawMessage` modifier (lines 64-81)

**Root Cause:**  
Deposits are validated to be divisible by `WEI_PER_LAMPORT` (line 58), but withdrawal messages have no such validation for `amountWei` or `feeWei`.

**Impact:**  
1. Withdrawals with fractional lamport amounts could be authorized
2. This creates accounting inconsistencies between the L1 bridge and L2 rollup
3. Conversion between wei and lamports (line 152) may lose precision
4. Users could receive slightly different amounts than expected due to rounding

**Recommendation:**  
Add validation in the `validWithdrawMessage` modifier:
```solidity
if (message.amountWei % WEI_PER_LAMPORT != 0) {
    revert CanonicalBridgeTransactionRejected(message.withdrawId, "Fractional lamport not allowed");
}
if (message.feeWei % WEI_PER_LAMPORT != 0) {
    revert CanonicalBridgeTransactionRejected(message.withdrawId, "Fractional fee not allowed");
}
```

## Medium: Emergency Withdraw Sends to msg.sender Instead of Specified Address

**File:** `Treasury.sol`  
**Function:** `emergencyWithdraw` (lines 133-145)

**Root Cause:**  
Line 142 hardcodes the withdrawal destination as `msg.sender`:
```solidity
(bool success,) = payable(msg.sender).call{value: amount}("");
```

**Impact:**  
1. If the `EMERGENCY_ROLE` holder is a contract that cannot receive ETH, emergency withdrawals will always fail
2. Multisig wallets or governance contracts may not be able to receive ETH directly
3. This defeats the purpose of emergency withdrawals during critical situations
4. No flexibility to send funds to a recovery address

**Recommendation:**  
Add an address parameter:
```solidity
function emergencyWithdraw(uint256 amount, address payable to) external onlyRole(EMERGENCY_ROLE) {
    if (to == address(0)) revert ZeroAddress();
    if (address(this).balance < amount) revert InsufficientFunds();
    (bool success,) = to.call{value: amount}("");
    if (!success) revert TreasuryTransferFailed();
    emit EmergencyTreasuryWithdraw(to, amount);
}
```

## Medium: Upgrader Grants Permanent Admin Role to Caller with Manual Revocation Warning

**File:** `Upgrader0to1.sol`  
**Function:** `executeUpgrade` (lines 128-130)

**Root Cause:**  
Lines 128-130 grant `DEFAULT_ADMIN_ROLE` to `msg.sender` with only a comment suggesting manual revocation:
```solidity
// Give msg.sender DEFAULT_ADMIN_ROLE for safety. REVOKE manually if caller is not an authoritative multisig.
AccessControl(p.treasuryProxy).grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
AccessControl(newCanonicalBridge).grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
```

**Impact:**  
1. Upgrade caller receives permanent admin privileges on both contracts
2. Relies on manual off-chain action to revoke, which may be forgotten
3. Creates unnecessary privileged accounts that violate least-privilege principle
4. If caller's key is later compromised, attacker gains full admin access
5. No atomic revocation means there's always a window of excessive privilege

**Recommendation:**  
Either remove these role grants entirely (since specific admin addresses are provided in params), or implement automatic revocation at the end of the function, or use a timelock mechanism.

## Medium: No Maximum Fraud Window Duration Allows Indefinite Withdrawal Delays

**File:** `CanonicalBridge.sol`  
**Function:** `setFraudWindowDuration` (lines 263-266)

**Root Cause:**  
The function only validates a minimum duration (1 day) but has no maximum:
```solidity
if (durationSeconds < MIN_FRAUD_WINDOW_DURATION) revert DurationTooShort();
```

**Impact:**  
1. Malicious `FRAUD_WINDOW_SETTER_ROLE` could set fraud window to years or decades
2. This would effectively lock all new withdrawals indefinitely
3. Users would be unable to access their funds for unreasonable timeframes
4. No protection against accidental setting of extremely large values

**Recommendation:**  
Add a maximum fraud window constant and validate it:
```solidity
uint256 private constant MAX_FRAUD_WINDOW_DURATION = 30 days;

function setFraudWindowDuration(uint256 durationSeconds) public onlyRole(FRAUD_WINDOW_SETTER_ROLE) {
    if (durationSeconds < MIN_FRAUD_WINDOW_DURATION) revert DurationTooShort();
    if (durationSeconds > MAX_FRAUD_WINDOW_DURATION) revert DurationTooLong();
    _setFraudWindowDuration(durationSeconds);
}
```

## Medium: Unsafe Use of abi.encodeWithSignature in deposit Function

**File:** `CanonicalBridge.sol`  
**Function:** `deposit` (line 148)

**Root Cause:**  
Line 148 uses string-based function signature encoding:
```solidity
(success,) = payable(address(TREASURY)).call{value: amountWei}(abi.encodeWithSignature("depositEth()"));
```

**Impact:**  
1. If the signature string is mistyped, the call silently sends ETH to Treasury's fallback function (if it exists)
2. No compile-time type checking of function signature
3. More gas-expensive than using interface calls
4. If Treasury doesn't have a fallback function, the call fails but error handling is unclear
5. Typos like "depositeEth()" would not be caught at compile time

**Recommendation:**  
Use the ITreasury interface for type-safe calls:
```solidity
bool success;
try ITreasury(TREASURY).depositEth{value: amountWei}() {
    success = true;
} catch {
    success = false;
}
if (!success) revert CanonicalBridgeTransactionRejected(0, "failed to transfer funds to the treasury");
```

## Medium: Withdraw Messages Have No Expiration Timestamp

**File:** `CanonicalBridge.sol`, `ICanonicalBridge.sol`  
**Struct:** `WithdrawMessage` (ICanonicalBridge.sol lines 24-31)

**Root Cause:**  
The `WithdrawMessage` struct has no expiration or deadline field. Once authorized, withdrawals remain valid forever unless explicitly cancelled.

**Impact:**  
1. Stale withdrawals from years ago could be claimed with outdated amounts or destinations
2. No automatic cleanup of old, forgotten withdrawals
3. In case of key compromise, old authorized withdrawals could be claimed by attackers
4. Exchange rate changes could make old withdrawal amounts economically exploitable
5. Storage costs accumulate indefinitely for unclaimed withdrawals

**Recommendation:**  
Add a deadline field to WithdrawMessage and validate it in claimWithdrawal:
```solidity
struct WithdrawMessage {
    bytes32 from;
    address destination;
    uint256 amountWei;
    uint64 withdrawId;
    address feeReceiver;
    uint256 feeWei;
    uint256 deadline; // Add this field
}
```

## Low: depositEth Function Accepts Zero-Value Deposits

**File:** `Treasury.sol`  
**Function:** `depositEth` (lines 100-102)

**Root Cause:**  
The function has no validation that `msg.value > 0`:
```solidity
function depositEth() external payable virtual override whenNotPaused onlyRole(DEPOSITOR_ROLE) {
    emit TreasuryDeposit(msg.sender, msg.value);
}
```

**Impact:**  
1. Allows meaningless zero-value transactions that waste gas
2. Emits useless events that pollute logs
3. Could be used for spam or to inflate transaction counts
4. No practical benefit to accepting zero deposits

**Recommendation:**  
Add validation:
```solidity
if (msg.value == 0) revert ZeroDeposit();
```

## Low: Missing Zero-Value Check in authorizeWithdraw

**File:** `CanonicalBridge.sol`  
**Function:** `validWithdrawMessage` modifier (line 71)

**Root Cause:**  
While the modifier checks `message.amountWei == 0` and reverts, it doesn't check if the net amount after fees is zero. If `amountWei == feeWei`, the user receives nothing.

**Impact:**  
1. Withdrawals where the entire amount goes to fees are allowed
2. User receives zero ETH but the withdrawal is marked as processed
3. Wastes gas and creates confusing transaction history
4. May not be the intended behavior

**Recommendation:**  
Add validation that net amount is non-zero:
```solidity
if (message.amountWei - message.feeWei == 0) {
    revert CanonicalBridgeTransactionRejected(message.withdrawId, "Net withdrawal amount is zero");
}
```

## Low: No Event Emitted for Fraud Window Duration Changes

**File:** `CanonicalBridge.sol`  
**Function:** `_setFraudWindowDuration` (lines 268-271)

**Root Cause:**  
The function emits `FraudWindowSet` event, but this event is already emitted. However, the impact is monitoring-related.

Actually, reviewing the code, the event IS emitted at line 270. This is not an issue.

## Low: Potential DoS if Destination or FeeReceiver is a Reverting Contract

**File:** `Treasury.sol`  
**Function:** `withdrawEth` (lines 124, 126)

**Root Cause:**  
Lines 124 and 126 use low-level `call` to send ETH. If `to` or `feeReceiver` is a contract that reverts on receive, the entire withdrawal fails.

**Impact:**  
1. Malicious or buggy contracts can permanently block withdrawals
2. No mechanism to change the destination after authorization
3. Funds remain locked if destination contract is broken
4. This could be exploited to grief users by setting their withdrawal destination to a reverting contract (though this requires WITHDRAW_AUTHORITY_ROLE)

**Recommendation:**  
Implement a pull-over-push pattern where failed transfers are stored and can be claimed later, or allow admins to modify withdrawal destinations in exceptional circumstances.

## Informational: Inconsistent Comparison in withdrawMessageStatus

**File:** `CanonicalBridge.sol`  
**Function:** `withdrawMessageStatus` (line 118)

**Root Cause:**  
Line 118 uses `>` for comparison:
```solidity
if (startTime_ > block.timestamp) return WithdrawStatus.PROCESSING;
```

While this is functionally correct, using `>=` would be more consistent with the fraud window calculation at line 194:
```solidity
uint256 messageStartTime = block.timestamp + fraudWindowDuration;
```

**Impact:**  
Minimal - in the exact block where `startTime_ == block.timestamp`, the status returns PENDING instead of PROCESSING. This is a one-block difference and doesn't affect security.

**Recommendation:**  
For clarity and consistency, consider using `>=`:
```solidity
if (startTime_ >= block.timestamp) return WithdrawStatus.PROCESSING;
```

## Informational: Constructor Does Not Validate Treasury Address

**File:** `CanonicalBridge.sol`  
**Constructor:** (lines 84-98)

**Root Cause:**  
The constructor accepts `treasuryAddress` but doesn't validate it's non-zero or a contract:
```solidity
constructor(address owner, address treasuryAddress) {
    // ... grants roles ...
    TREASURY = treasuryAddress;
    emit Deployed(msg.sender, owner, treasuryAddress);
}
```

**Impact:**  
1. If deployed with zero address or EOA as treasury, all deposits will fail
2. Contract must be redeployed if wrong treasury address is used
3. No validation that treasury implements expected interface

**Recommendation:**  
Add validation:
```solidity
if (treasuryAddress == NULL_ADDRESS) revert ZeroAddress();
if (treasuryAddress.code.length == 0) revert NotContract();
```

## Informational: Missing Input Validation in Upgrader Parameter Reuse

**File:** `Upgrader0to1.sol`  
**Function:** `executeUpgrade`

**Root Cause:**  
The function doesn't validate that different admin addresses are actually different. For example, `bridgeAdmin`, `treasuryAdmin`, and `trustedRelayer` could all be the same address.

**Impact:**  
1. Excessive centralization if one address receives multiple admin roles
2. Single point of failure if that address is compromised
3. Defeats separation of duties principle
4. May not be the intended deployment configuration

**Recommendation:**  
Add validation to ensure key addresses are different:
```solidity
if (p.bridgeAdmin == p.treasuryAdmin || p.bridgeAdmin == p.trustedRelayer) {
    revert ExcessiveCentralization();
}
```

## Informational: Gas Optimization - Cache Array Length in Loop

**File:** `CanonicalBridge.sol`  
**Function:** `authorizeWithdraws` (lines 158-169)

**Root Cause:**  
Line 166 accesses `messages.length` on every iteration:
```solidity
for (uint256 i = 0; i < messages.length; i++) {
```

**Impact:**  
Slightly higher gas cost for each iteration. For large batches, this adds up.

**Recommendation:**  
Cache the length:
```solidity
uint256 len = messages.length;
for (uint256 i = 0; i < len; i++) {
```

## Informational: Consider Using Custom Errors Throughout for Gas Savings

**File:** Multiple files

**Root Cause:**  
Some functions use string-based `revert` messages while others use custom errors. String messages are more expensive.

**Impact:**  
Higher gas costs for reverts. Not a security issue but affects user experience.

**Recommendation:**  
Migrate all string-based reverts to custom errors for consistency and gas optimization.

## Informational: Missing Natspec Documentation for Some Functions

**File:** Multiple files

**Root Cause:**  
Some internal functions and modifiers lack complete NatSpec documentation.

**Impact:**  
Reduced code readability and maintainability. Makes auditing more difficult.

**Recommendation:**  
Add comprehensive NatSpec comments to all public and internal functions, especially those handling critical logic like withdrawals and role management.
