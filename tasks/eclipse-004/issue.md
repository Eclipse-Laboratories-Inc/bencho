# receiveMessage updates the nonce after the external call

## Summary

`Mailbox.receiveMessage` validates the relayer signature, then calls `router.routeIncomingMessage`, and only afterwards marks `receiveNonces[nonce]` as used.

The function is protected by `nonReentrant`, so this is not an open reentrancy into `receiveMessage`. The project still requires the checks-effects-interactions order: the nonce must be recorded before the router call. A router invoked during delivery can currently observe the nonce as unused.

## Expected behavior

While `routeIncomingMessage` is executing, the nonce for that message is already marked received. A later `receiveMessage` with the same nonce still reverts. Successful delivery of a fresh, well-signed message still returns true.
