pragma solidity 0.8.21;

import {IEIP6170 as IRelayerMailbox} from "./IEIP6170.sol";

/// @title IRoutableMailbox
/// @dev This interface ensures the mailbox can receives messages from a router.
interface IRoutableMailbox is IRelayerMailbox {
    /// @notice Sends an outgoing message from a router to a mailbox.
    /// @param to_ The intended receiver of the message.
    /// @param message_ The arbitrary message to be mailed out.
    function mailOutgoingMessage(bytes memory to_, bytes memory message_) external;
}
