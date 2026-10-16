# Withdrawal messages accept a zero fee receiver

## Summary

`validWithdrawMessage` rejects a zero `from`, a zero `destination`, a zero amount, a zero id, and a fee larger than the amount. It does not reject a zero `feeReceiver`.

`Treasury.withdrawEth` will later refuse a zero fee receiver, but the bridge still authorizes the message and starts the fraud window. Those authorizations cannot be claimed and have to be cancelled.

## Expected behavior

`authorizeWithdraw` reverts when `message.feeReceiver` is the zero address, before the message is stored. A message with a nonzero fee receiver is still authorized.
