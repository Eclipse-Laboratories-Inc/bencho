// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

interface IMailbox {
    function sendMessage(bytes memory chainid, bytes memory receiver, bytes memory message, bytes memory data) external payable returns (bool);
}

contract StubModule {
    function revertWithMessage(string memory message) external pure {
        revert(message);
    }

    function success() external pure {
        // do nothing
    }

    function sendMessage(address mailbox, bytes memory chainid, bytes memory receiver, bytes memory message, bytes memory data) external payable returns (bool) {
        return IMailbox(mailbox).sendMessage(chainid, receiver, message, data);
    }
}