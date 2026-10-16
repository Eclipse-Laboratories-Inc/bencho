# claimWithdrawal performs the treasury call before closing the withdrawal

## Summary

`CanonicalBridge.claimWithdrawal` pays the user by calling `Treasury.withdrawEth` and only then sets the withdrawal status to closed.

The treasury delivers ether to `message.destination` with a low-level call. During that call the withdrawal is still `PENDING`, so the destination observes an open claim. The status write and the `WithdrawClaimed` event need to happen before the external call.

## Expected behavior

When `message.destination` receives the ether, `withdrawMessageStatus` for that message is already `CLOSED`. A claim that was authorized and whose fraud window has elapsed still pays `amountWei - feeWei` exactly once. Unauthorized claims still revert.
