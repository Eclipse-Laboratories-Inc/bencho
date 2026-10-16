pragma solidity 0.8.21;

/// @title Cross-Chain Messaging interface
/// @dev Allows seamless interchain messaging.
/// @author Sujith Somraaj (extended by Eclipse Labs)
/// Note: Based on EIP-6170 with the minor modifications (See Mailbox.md)
interface IMailbox {
    /// @dev This emits when a cross-chain message is sent.
    /// Note: MessageSent MUST trigger when a message is sent, including zero bytes transfers.
    event MessageSent(bytes to, bytes toChainId, bytes message, bytes extraData);

    /// @dev This emits when a cross-chain message is received.
    /// MessageReceived MUST trigger on any successful call to receiveMessage
    event MessageReceived(bytes from, bytes fromChainId, bytes message, bytes extraData);

    /// @notice Sends a message to another blockchain through the trusted relayer
    /// @dev Sends an encoded message to a specified receiver on the target chain using a trusted relayer.
    /// @param chainId_ is the address of the receiver.
    /// @param receiver_ is the address of the receiver.
    /// @param message_ is the arbitrary message to be delivered.
    /// @param data_ is the address of the receiver.
    function sendMessage(bytes memory chainId_, bytes memory receiver_, bytes memory message_, bytes memory data_)
        external
        payable
        returns (bool);

    /// @notice Receives a message from a sender on a different blockchain
    /// @dev Validates the sender, chainId, and ensures the message has not been replayed (checks nonce).
    /// @param chainId_ is the unique identifier of the sending blockchain.
    /// @param sender_ is the address of the sender.
    /// @param message_ is the arbitrary message sent by the sender.
    /// @param data_ is an additional parameter to be used for security purposes. E.g, can send nonce in layerzero.
    /// @return the status of message processing/storage.
    /// Note: sender validation (or) message validation should happen before processing the message.
    function receiveMessage(bytes memory chainId_, bytes memory sender_, bytes memory message_, bytes memory data_)
        external
        payable
        returns (bool);
}
