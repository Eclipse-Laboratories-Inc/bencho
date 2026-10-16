# OtterSec audit, 2024-10-31

## Informational: Treasury balance check counts the fee twice

Location: smart-contracts/src/v1/Treasury.sol: Treasury.withdrawEth

The fee is deducted from amountWei, but withdrawEth requires the balance to cover amountWei + feeWei. Withdrawals that the treasury can fully pay revert with InsufficientFunds.

## Informational: Cancelling a withdrawal leaves its id consumed

Location: smart-contracts/src/v1/CanonicalBridge.sol: CanonicalBridge.deleteWithdrawMessage

deleteWithdrawMessage clears the message's startTime but not withdrawMsgIdProcessed[withdrawId], so a cancelled withdrawal id can never be authorized again and the contract state is inconsistent.

## Informational: Zero fee receiver is not handled consistently

Location: smart-contracts/src/v1/CanonicalBridge.sol: validWithdrawMessage; smart-contracts/src/v1/Treasury.sol: withdrawEth

validWithdrawMessage accepts a zero feeReceiver, while Treasury.withdrawEth always tries to pay the fee to it. Either reject a zero fee receiver when authorizing or handle it in the treasury.

## Informational: claimWithdrawal updates state after the external call

Location: smart-contracts/src/v1/CanonicalBridge.sol: CanonicalBridge.claimWithdrawal

claimWithdrawal calls Treasury.withdrawEth, which sends ether to the destination, before setting startTime[messageHash] = NEVER. The state update should come before the external call (checks-effects-interactions) to rule out reentrancy.

## Informational: Unused variables

Location: smart-contracts/src/v1/Treasury.sol: StorageV1; role constants

Several variables, including Treasury's StorageV1 and some role constants, are never used and should be removed.

## Informational: Authorization does not check withdrawMsgIdProcessed

Location: smart-contracts/src/v1/CanonicalBridge.sol: CanonicalBridge._authorizeWithdraw

_authorizeWithdraw only rejects a message whose hash already exists; it does not check withdrawMsgIdProcessed, so the same withdrawal id can be reused in a different message.
