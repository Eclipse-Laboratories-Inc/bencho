# Cancelling a withdrawal does not free its id

## Summary

Authorizing a withdrawal records `withdrawMsgIdProcessed[message.withdrawId]`. A later authorization with the same id is rejected even when the message body differs.

`deleteWithdrawMessage` clears `startTime` for that message, so the message hash looks unused, but it leaves `withdrawMsgIdProcessed` set. After a cancel, the id cannot be used again.

## Expected behavior

After `deleteWithdrawMessage` on a withdrawal that is still in the fraud window, `withdrawMsgIdProcessed[withdrawId]` is 0. The message hash is cleared as it is today. Only the withdraw-canceller role may delete.
