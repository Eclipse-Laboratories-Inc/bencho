# Treasury rejects a withdrawal whose fee is already inside the amount

## Summary

`Treasury.withdrawEth(to, amountWei, feeReceiver, feeWei)` pays `amountWei - feeWei` to `to` and `feeWei` to `feeReceiver`. The fee is a portion of `amountWei`, not an additional charge.

The balance check requires `address(this).balance >= amountWei + feeWei`. A treasury that holds exactly `amountWei` cannot pay a nonzero fee, even though the two transfers add up to `amountWei`.

## Expected behavior

The withdrawal succeeds when the treasury balance is at least `amountWei` and `feeWei <= amountWei`. The recipient receives `amountWei - feeWei` and the fee receiver receives `feeWei`. A balance below `amountWei` still reverts.
