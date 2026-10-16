# Withdrawals pay lamports as if they were wei

## Summary

Eclipse withdrawals arrive at `EtherBridge.withdraw` with an amount expressed in lamports. The bridge is supposed to convert that amount back to wei before moving funds out of the treasury (1 lamport = 1 gwei = 1e9 wei).

`withdraw` currently forwards `message.amount` straight to `Treasury.withdraw`. A user who withdrew 5 lamports on Eclipse receives 5 wei on Ethereum instead of 5 gwei.

## Expected behavior

`Treasury.withdraw` is called with `message.amount * 1e9` wei, and the recipient's balance increases by that wei amount. The withdrawal must still revert when the converted wei amount exceeds the treasury balance or the maximum withdrawal.

## Notes

The router is the only authorized caller. Other deposit-path bugs are out of scope.
