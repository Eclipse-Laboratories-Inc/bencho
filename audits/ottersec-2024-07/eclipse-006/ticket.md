# MessageSent emits the Ethereum chain id as the destination

## Summary

`Mailbox.sendMessage` is how modules send a message out to Eclipse. The `MessageSent` event is what off-chain relayers read to learn the destination chain.

The event's `toChainId` is currently `encodeChainId` of the mailbox's Ethereum chain id. Relayers that trust the event will treat the message as destined for Ethereum rather than Eclipse.

## Expected behavior

`MessageSent.toChainId` decodes to the mailbox's Eclipse chain id (`keccak256` of the configured Eclipse chain id string), not the Ethereum chain id. Only authorized modules can send, and that access check must keep working.
