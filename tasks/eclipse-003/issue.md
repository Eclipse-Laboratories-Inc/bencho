# Missing zero-value checks on withdraw and outgoing mail

## Summary

Two bridge entry points accept empty destinations:

- `EtherBridge.withdraw` does not reject a zero `message.recipient`. The treasury will transfer ether to `address(0)`.
- `Mailbox.mailOutgoingMessage` does not reject an empty `to_` payload, so the mailbox will emit an outgoing message with no destination.

## Expected behavior

- `withdraw` reverts when `message.recipient` is the zero address.
- `mailOutgoingMessage` reverts when `to_` is empty.

Initialized, non-zero destinations must keep working. Do not change deposit accounting or the lamport conversion in this fix.
