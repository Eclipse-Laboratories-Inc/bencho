pragma solidity 0.8.21;

/// @title IRouter Interface
/// @dev Defines the interface for a router that can receive and send messages from and to a mailbox.
interface IRouter {
    /// @notice Routes a message to the appropriate contract.
    /// @param encodedIdentifier Encoded identifier of the sender of the message.
    /// @param message A message received from a mailbox.
    function routeIncomingMessage(bytes calldata encodedIdentifier, bytes calldata message) external payable;

    /// @notice Routes an message to the mailbox.
    /// @param message Allows sending messages to a mailbox.
    function routeOutgoingMessage(bytes calldata message) external payable;
}
