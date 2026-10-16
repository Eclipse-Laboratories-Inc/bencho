# Security Audit Report

## Critical: Unsafe bytes-to-bytes32 conversion allows module confusion

**File:** `smart-contracts/src/v1/Mailbox.sol:213`

**Function:** `receiveMessage`

**Root Cause:** The code performs an unsafe cast `bytes32(sender_)` without validating that `sender_` is exactly 32 bytes. In Solidity 0.8.21, casting `bytes memory` to `bytes32` reads the first 32 bytes without length validation. If `sender_` is shorter than 32 bytes, this reads past the allocated memory which could cause unexpected behavior or revert. If `sender_` is longer than 32 bytes, only the first 32 bytes are used, potentially allowing an attacker to craft a `sender_` value that matches a valid module ID when truncated.

**Impact:** A malicious trusted relayer could send messages to unintended modules by crafting sender_ values that produce valid module IDs when unsafely converted. This could lead to unauthorized function calls on critical modules.

**Recommendation:** Add explicit length validation before the conversion:
```solidity
require(sender_.length == 32, "Invalid sender length");
address module = $.modulesById[bytes32(sender_)];
```
Alternatively, use `abi.decode(sender_, (bytes32))` which will revert on incorrect length.

## High: Weak randomness enables nonce prediction and collision attacks

**File:** `smart-contracts/src/v1/Mailbox.sol:257-264`

**Function:** `generateRandomNonce`

**Root Cause:** The nonce generation relies on `blockhash(block.number - 1)`, `block.timestamp`, and `block.coinbase` for randomness. In Ethereum PoS, validators control `block.coinbase` (fee recipient) and have limited influence over `block.timestamp` (within consensus rules). While `blockhash` provides some entropy, validators can predict all inputs to the hash function. This makes nonces predictable, especially for validators who know the previous block's hash.

**Impact:** 
1. Validators or sophisticated attackers can predict future nonces, potentially identifying nonce collisions before they occur
2. Attackers could manipulate block properties (if they're validators) to force nonce collisions, causing DOS
3. Weakened replay protection if nonces can be predicted

**Recommendation:** Use a cryptographically secure randomness source like Chainlink VRF, or maintain a simple incrementing counter instead of pseudo-random nonces. For replay protection, a monotonically increasing counter is more reliable:
```solidity
function generateNonce() internal returns (uint64) {
    StorageV1 storage $ = _getStorageV1();
    $.lastNonce += 1;
    return uint64($.lastNonce);
}
```

## High: Centralized trusted relayer creates single point of failure

**File:** `smart-contracts/src/v1/Mailbox.sol:186-222`

**Function:** `receiveMessage`

**Root Cause:** Only addresses with `TRUSTED_RELAYER_ROLE` can call `receiveMessage`. This relayer has complete control over which module receives messages and what data is sent. The relayer controls the `sender_` parameter (which selects the module) and the `message_` parameter (arbitrary calldata executed on the module via low-level call).

**Impact:** If the trusted relayer's private key is compromised:
1. Attacker can call arbitrary functions on any registered module with arbitrary parameters
2. Attacker can drain funds or manipulate state if modules trust calls from the mailbox
3. All cross-chain message integrity depends on this single key
4. No multi-signature or redundancy mechanism exists

**Recommendation:** 
1. Implement multi-signature verification requiring multiple relayers to sign messages
2. Add message authentication from the source chain (e.g., Merkle proofs, signatures)
3. Consider implementing rate limits or monetary caps per module
4. Add emergency pause mechanism if relayer compromise is detected

## High: Nonce collision causes permanent DOS of sendMessage

**File:** `smart-contracts/src/v1/Mailbox.sol:236-240`

**Function:** `sendMessage`

**Root Cause:** When `generateRandomNonce()` produces a nonce that already exists in `sendNonces` mapping, the transaction reverts with "Nonce collision". Due to weak randomness (see previous finding), collisions become more likely over time. With 64-bit nonces, birthday paradox suggests collisions after approximately 2^32 operations, but predictable randomness accelerates this.

**Impact:**
1. Legitimate sendMessage calls will permanently fail if nonce collision occurs
2. No recovery mechanism exists - transaction simply reverts
3. Attackers (especially validators) could deliberately cause collisions to DOS the bridge
4. High-throughput bridges are particularly vulnerable as collision probability increases

**Recommendation:** 
1. Use an incrementing counter instead of pseudo-random nonces (eliminates collision risk)
2. If randomness is required, implement retry logic to generate new nonce on collision
3. Add monitoring to detect collision attempts

## Medium: blockhash returns zero for unavailable blocks

**File:** `smart-contracts/src/v1/Mailbox.sol:261`

**Function:** `generateRandomNonce`

**Root Cause:** The function uses `blockhash(block.number - 1)`. The `blockhash` function only works for the most recent 256 blocks and returns 0 for older blocks or blocks that don't exist. At block 1, `block.number - 1 = 0`, and `blockhash(0)` may return zero or unpredictable values depending on the chain. Additionally, in the extremely unlikely event the function is called at block 0, there would be arithmetic underflow (though 0.8.21 prevents this with revert).

**Impact:** Reduced entropy at genesis/early blocks, making initial nonces more predictable. This is a limited-scope issue but degrades security during contract initialization period.

**Recommendation:** Add validation to ensure blockhash is available:
```solidity
require(block.number > 1, "Insufficient block height");
bytes32 blockHash = blockhash(block.number - 1);
require(blockHash != bytes32(0), "Blockhash unavailable");
```

## Medium: Missing interface validation when adding modules

**File:** `smart-contracts/src/v1/Mailbox.sol:151-164`

**Function:** `addModule`

**Root Cause:** When a new module is added via `addModule`, the contract grants `MODULE_ROLE` and registers the module address, but doesn't verify that the module implements the expected message-receiving interface. If an incorrect address (e.g., EOA, incompatible contract, or wrong contract) is registered, messages sent to it will fail.

**Impact:**
1. Messages routed to incompatible modules will fail, locking user funds in treasury
2. Admin error could break critical bridge functionality
3. No validation prevents registration of malicious contracts

**Recommendation:** Consider adding interface detection:
```solidity
require(IERC165(module).supportsInterface(type(IModule).interfaceId), "Invalid module interface");
```
Or at minimum, add comprehensive testing and documentation about module requirements.

## Medium: No message expiration enables indefinite delay attacks

**File:** `smart-contracts/src/v1/Mailbox.sol:186-222`

**Function:** `receiveMessage`

**Root Cause:** Messages have no expiration timestamp. Once a nonce is generated, the corresponding message can be delayed arbitrarily by the trusted relayer and delivered at any future time. The only protection is the nonce-based replay prevention, which only prevents duplicate delivery.

**Impact:**
1. Trusted relayer can delay messages indefinitely, which may be harmful if messages contain time-sensitive operations
2. Users cannot enforce delivery deadlines
3. Old messages with outdated information could be delivered when no longer relevant
4. Griefing attack where relayer holds messages until most unfavorable time for users

**Recommendation:** Add expiration timestamp to security parameters:
```solidity
struct EthereumSecurityParam {
    uint64 nonce;
    uint256 deadline;
}
```
Then validate in receiveMessage:
```solidity
require(block.timestamp <= secParam.deadline, "Message expired");
```

## Medium: Unbounded storage growth from nonce mappings

**File:** `smart-contracts/src/v1/Mailbox.sol:57-58`

**Storage:** `receiveNonces` and `sendNonces` mappings

**Root Cause:** Every message sent or received adds an entry to the respective nonce mapping that is never removed. Over the lifetime of a high-throughput bridge, this could be millions of storage slots. While Solidity mappings are sparse and only used slots consume gas, there's no cleanup mechanism.

**Impact:**
1. Perpetual storage growth without bounds
2. No way to reclaim storage or reduce state size
3. Over years of operation, this represents significant blockchain state bloat
4. Gas costs for each transaction remain constant, but global state size grows

**Recommendation:** Consider implementing a time-based cleanup mechanism or using a different replay protection scheme:
```solidity
mapping(uint64 => uint256) receiveNonceTimestamp;

function isNonceExpired(uint64 nonce) internal view returns (bool) {
    return block.timestamp > receiveNonceTimestamp[nonce] + NONCE_EXPIRY_TIME;
}
```
Or use a bitmap for sequential nonces to reduce storage per nonce.

## Medium: Validator manipulation of randomness sources

**File:** `smart-contracts/src/v1/Mailbox.sol:261`

**Function:** `generateRandomNonce`

**Root Cause:** In Proof-of-Stake Ethereum, validators have direct control over `block.coinbase` (their fee recipient address) and bounded control over `block.timestamp` (can manipulate within consensus rules, typically ±15 seconds). A validator calling `sendMessage` can compute the resulting nonce before submitting the transaction and potentially manipulate these parameters.

**Impact:**
1. Validators can predict nonces for their own transactions
2. Sophisticated validators could manipulate timestamp/coinbase to avoid or cause nonce collisions
3. Undermines the randomness assumption, making nonces partially controllable

**Recommendation:** Use external randomness source (Chainlink VRF) or switch to simple incrementing counter, which is more predictable but doesn't claim to be random and has zero collision risk.

## Low: Missing return data validation on module calls

**File:** `smart-contracts/src/v1/Mailbox.sol:215-216`

**Function:** `receiveMessage`

**Root Cause:** The low-level call to the module `(bool success,) = module.call(message_)` only checks the success boolean but discards any return data. If modules return error information or status codes, this information is lost.

**Impact:**
1. Module errors are not propagated to the caller or logs
2. Debugging failed message processing is more difficult
3. Modules cannot signal partial failures or warnings

**Recommendation:** If modules are expected to return meaningful data, validate it:
```solidity
(bool success, bytes memory returnData) = module.call(message_);
require(success, "External call to module failed");
// Optionally validate or log returnData
```

## Low: Treasury receive allows owner deposits bypassing accounting

**File:** `smart-contracts/src/v1/Treasury.sol:83-87`

**Function:** `receive`

**Root Cause:** The treasury's `receive()` function accepts ether from both `etherBridgeAddress` and `owner()`. While the EtherBridge deposits are tracked via events and bridge accounting, owner deposits are not part of the bridge deposit flow and could cause accounting discrepancies.

**Impact:**
1. Owner can directly fund treasury outside of normal bridge flow
2. May cause confusion in accounting systems expecting all treasury funds to come from bridge deposits
3. Could complicate auditing of total bridged value vs treasury balance

**Recommendation:** If owner funding is intentional, emit a distinct event:
```solidity
if (msg.sender == owner()) {
    emit OwnerDeposit(msg.sender, msg.value);
} else {
    emit TreasuryDeposit(msg.sender, msg.value);
}
```
This maintains the feature while improving transparency.

## Low: Deposit violates checks-effects-interactions pattern

**File:** `smart-contracts/src/v1/EtherBridge.sol:111-116`

**Function:** `deposit`

**Root Cause:** The function calls `mailbox.sendMessage()` (external interaction that modifies state by storing a nonce) before transferring funds to the treasury. The standard checks-effects-interactions pattern recommends completing all state changes before external calls.

**Impact:**
1. While protected by `nonReentrant` modifier and atomic transactions, this pattern is harder to audit
2. If future modifications remove reentrancy guard, could enable reentrancy attacks
3. Sets poor precedent for code maintainability

**Recommendation:** Reorder operations to match checks-effects-interactions:
```solidity
// Create message
bytes memory encodedMessage = abi.encode(message);

// Lock funds in treasury first (interactions)
(bool success,) = payable(address($.treasuryProxy)).call{value: amountWei}("");
require(success, "Transfer failed");

// Then send message (interactions)
success = $.mailboxProxy.sendMessage("", $.etherBridgeId, encodedMessage, "");
require(success, "Unable to forward deposit message to Mailbox");
```
Note: Both are interactions, so order matters less, but treasury transfer should logically come first.

## Low: No withdrawal mechanism in EtherBridge

**File:** `smart-contracts/src/v1/EtherBridge.sol`

**Root Cause:** The EtherBridge contract only implements `deposit` functionality. There is no corresponding `withdraw` function to return funds from Eclipse to Ethereum. Users can deposit but cannot withdraw through this contract.

**Impact:**
1. Bridge appears to be one-way only
2. If withdrawal module is not implemented elsewhere, funds are permanently locked
3. Users may deposit without realizing withdrawals aren't supported

**Recommendation:** If withdrawals are intended to be handled by a separate module that receives messages from Eclipse via the mailbox:
1. Document this architecture clearly
2. Implement and audit the withdrawal module
3. Ensure proper access controls on Treasury.emergencyWithdraw (currently owner-only)

## Informational: Sender address not included in MessageSent event

**File:** `smart-contracts/src/v1/Mailbox.sol:244`

**Function:** `sendMessage`

**Root Cause:** The `MessageSent` event emitted in `sendMessage` includes `receiver_`, `chainId`, `message_`, and `param`, but not the sender's address. The sender can only be inferred from the transaction origin, not from the event data.

**Impact:**
1. Off-chain systems cannot easily identify which module sent a message by only reading events
2. Event data is incomplete for audit trails
3. Must correlate transaction sender with events for full picture

**Recommendation:** Include sender in event:
```solidity
emit MessageSent(msg.sender, receiver_, encodeChainId($.eclipseChainId), message_, param);
```
Update the event definition accordingly in IMailbox.

## Informational: Empty chain ID parameter passed to sendMessage

**File:** `smart-contracts/src/v1/EtherBridge.sol:111`

**Function:** `deposit`

**Root Cause:** The call to `$.mailboxProxy.sendMessage("", $.etherBridgeId, encodedMessage, "")` passes empty string for the first parameter (destination chainId). Looking at Mailbox.sendMessage implementation, this parameter is unnamed and unused, so passing empty string has no effect.

**Impact:** None - the parameter is ignored. However, this indicates poor API design where parameters are present but not used.

**Recommendation:** Either:
1. Remove unused parameters from the interface (breaking change)
2. Use the parameter for validation
3. Document why the parameter exists but is unused

## Informational: Potential integer truncation in amountGwei conversion

**File:** `smart-contracts/src/v1/EtherBridge.sol:105-107`

**Function:** `deposit`

**Root Cause:** The conversion `uint256 amountGwei = amountWei / WEI_PER_LAMPORT` produces a uint256, which is then assigned to `DepositMessage.amountGwei`. If the struct field `amountGwei` were a smaller type (e.g., uint128 or uint64), large amounts could overflow when assigned to the struct.

**Impact:** Based on the interface, `amountGwei` is uint256, so no overflow occurs. However, if the struct definition ever changes to a smaller type without updating this code, silent truncation could occur.

**Recommendation:** Add explicit type checking or use SafeCast:
```solidity
uint256 amountGwei = amountWei / WEI_PER_LAMPORT;
require(amountGwei <= type(uint128).max, "Amount too large"); // if struct uses uint128
```

## Informational: Missing comprehensive role management events

**File:** `smart-contracts/src/v1/Mailbox.sol:151-184`

**Functions:** `addModule`, `removeModule`

**Root Cause:** While `addModule` and `removeModule` use OpenZeppelin's `_grantRole` and `_revokeRole` (which emit RoleGranted/RoleRevoked events), there are no events specifically for module registration/deregistration that include the module ID mapping.

**Impact:**
1. Event listeners must correlate role events with module IDs through transaction data
2. No dedicated event makes off-chain tracking of module registry more complex

**Recommendation:** Add custom events:
```solidity
event ModuleAdded(bytes32 indexed moduleId, address indexed module);
event ModuleRemoved(bytes32 indexed moduleId, address indexed module);
```
Emit these in `addModule` and `removeModule` functions.

## Informational: UUPS upgrade authorization is centralized

**File:** `smart-contracts/src/v1/Treasury.sol:80`, `Mailbox.sol:250`, `EtherBridge.sol:132`

**Functions:** `_authorizeUpgrade`

**Root Cause:** All three contracts use UUPS upgradeable pattern with single-address authorization (Treasury uses `onlyOwner`, others use `onlyAuthority`). A compromised admin key can upgrade contracts to malicious implementations.

**Impact:**
1. Single key compromise enables complete system takeover
2. Owner/admin can rug pull by upgrading to drain funds
3. No timelock or multi-sig requirement for upgrades

**Recommendation:**
1. Use multi-signature wallet for owner/admin roles
2. Implement timelock for upgrades to give users warning
3. Consider using TransparentUpgradeableProxy with separate admin contract
4. Add upgrade announcement events and delay periods

## Informational: Missing input validation for minimum deposit edge cases

**File:** `smart-contracts/src/v1/EtherBridge.sol:27-28, 49-54`

**Constants and modifier:** `MIN_DEPOSIT`, `validDepositAmount`

**Root Cause:** The minimum deposit is hardcoded as `MIN_DEPOSIT = 2_000_000 * 1_000_000_000 = 2e15 wei = 0.002 ether`. While this prevents spam, there's no upper bound check or validation that the amount doesn't exceed reasonable limits.

**Impact:**
1. Users could accidentally deposit unreasonably large amounts (e.g., typo adding extra zeros)
2. No sanity checks for maximum deposit amounts
3. While not a security issue, could improve UX

**Recommendation:** Consider adding optional maximum deposit limit or warnings:
```solidity
uint256 public constant MAX_DEPOSIT = 1000 ether; // example
require(msg.value <= MAX_DEPOSIT, "Deposit exceeds maximum");
```
Or implement this as a soft check with a warning event.

## Low: Mailbox lacks emergency pause functionality

**File:** `smart-contracts/src/v1/Mailbox.sol`

**Root Cause:** Unlike Treasury and EtherBridge which inherit from `PausableUpgradeable` and implement `pause()`/`unpause()` functions, the Mailbox contract has no pause mechanism. In emergency situations (e.g., relayer key compromise, critical bug discovered), there's no way to halt message processing without upgrading the contract.

**Impact:**
1. Cannot quickly stop malicious message processing if trusted relayer is compromised
2. No emergency brake for the core messaging infrastructure
3. Must rely on slower upgrade process to stop attacks in progress
4. Modules can still send messages even if Treasury/Bridge are paused

**Recommendation:** Add Pausable functionality to Mailbox:
```solidity
import "openzeppelin-contracts-upgradeable/contracts/utils/PausableUpgradeable.sol";

contract Mailbox is ..., PausableUpgradeable {
    function pause() external onlyAuthority {
        _pause();
    }
    
    function unpause() external onlyAuthority {
        _unpause();
    }
    
    function receiveMessage(...) external whenNotPaused {
        // existing code
    }
    
    function sendMessage(...) external whenNotPaused {
        // existing code
    }
}
```
