pragma solidity 0.8.21;

import "../../../src/v1/interfaces/IRoutableMailbox.sol";

contract MockRoutableMailbox is IRoutableMailbox {
    function mailOutgoingMessage(bytes memory to_, bytes memory message_) external override {
        bytes memory chainId = "somechainid";
        receiveMessage(chainId, to_, message_, message_);
    }

    // Simulate sending a message to a different blockchain
    function sendMessage(bytes memory chainId_, bytes memory receiver_, bytes memory message_, bytes memory data_)
        external
        payable
        override
        returns (bool)
    {
        emit MessageSent(receiver_, chainId_, message_, data_);
        return true;
    }

    // Simulate receiving a message from a different blockchain
    function receiveMessage(bytes memory chainId_, bytes memory sender_, bytes memory message_, bytes memory data_)
        public
        payable
        override
        returns (bool)
    {
        emit MessageReceived(sender_, chainId_, message_);
        return true;
    }
}
