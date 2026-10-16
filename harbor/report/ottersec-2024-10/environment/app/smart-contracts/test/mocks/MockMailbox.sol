// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

contract MockMailBox {
    bool isSendMessageOk;
    bool sendMessageReturnValue;
    error SendMessageFailed();

    constructor() {
        isSendMessageOk = true;
        sendMessageReturnValue = true;
    }

    function sendMessage(bytes memory, bytes memory, bytes memory, bytes memory) external payable returns (bool) {
        if (!isSendMessageOk) revert SendMessageFailed();
        return sendMessageReturnValue;
    }

    function mockSendMessage(bool returnValue, bool success) external {
        sendMessageReturnValue = returnValue;
        isSendMessageOk = success;
    }
}