# Deposits are not locked in the treasury

## Summary

`EtherBridge.deposit` is supposed to lock the deposited ether in the `Treasury` contract. The amount forwarded to the treasury is not the wei amount the user deposited.

The bridge documents a 1 gwei = 1 lamport conversion for the message sent to Eclipse. That conversion is being applied to the ether that should be locked on Ethereum. Most of a deposit therefore stays in `EtherBridge` instead of the treasury, and there is no withdrawal path for those residual funds.

## Expected behavior

After a successful `deposit(recipient, amount, fee)`:

- The treasury balance increases by `amount` wei.
- The deposit fee remains with the bridge.
- The outgoing message may still express the bridged value in lamports.

## Notes

A deposit that passes the existing amount and fee checks should be enough to reproduce this.
