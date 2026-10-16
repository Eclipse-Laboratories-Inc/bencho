pragma solidity 0.8.21;

import {IRoutableMailbox as IMailbox} from "./interfaces/IRoutableMailbox.sol";
import {IEtherBridge} from "./interfaces/IEtherBridge.sol";
import {console2} from "forge-std/Test.sol";

/// @title Simulated Mailbox
/// @dev This contract acts as a 'simulated' mailbox for testing relayers.
contract SimulatedMailbox is IMailbox {
    mapping(bytes32 => uint256) private sendNonces;
    bytes private targetChainId;

    /// @dev Initializes the mailbox contract
    constructor() {
        targetChainId = new bytes(2);
    }

    /// @dev Receives messages from 'other' chains
    function receiveMessage(bytes memory chainId_, bytes memory sender_, bytes memory message_, bytes memory data_)
        external
        payable
        override
        returns (bool)
    {
        // Emit the message received event
        emit MessageReceived(sender_, chainId_, message_);

        return true;
    }

    /// @dev Simulates a deposit using the msg.value and a message
    function simulatedDeposit(bytes memory to, IEtherBridge.DepositMessage memory message) public payable {
        bytes memory encodedMessage = abi.encode(message);
        mailOutgoingMessage(to, encodedMessage);
    }

    /// @dev Simulates a simple deposit using the msg.value and fixed message
    /// using the following sender, recipient and fee:
    /// sender: 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
    /// recipient: 0xd91e8d84ab2f3cfece4351c15d2eeca72f02309f513e331ac31d92677d1e9e6d
    /// fee: 200 gwei
    function simpleSimulateDeposit() external payable {
        // Initialize  message
        console2.log("1");
        address testSender = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
        bytes32 testRecipient = 0xd91e8d84ab2f3cfece4351c15d2eeca72f02309f513e331ac31d92677d1e9e6d;
        uint256 testFee = 200 gwei;
        uint256 testAmount = msg.value - testFee;
        uint256 wei_per_gwei = 1_000_000;

        console2.log("2");
        IEtherBridge.DepositMessage memory depositMsg = IEtherBridge.DepositMessage({
            sender: testSender, // Alice on this chain
            recipient: testRecipient, // Alice on target chain
            amount: testAmount / wei_per_gwei,
            fee: testFee / wei_per_gwei
        });

        console2.log("3");

        // Simulate deposit with message
        bytes memory to = "Deposit";
        simulatedDeposit(to, depositMsg);

        console2.log("4");
    }

    /// @dev Handles messages from the router, updates nonce, encodes and calls sendMessage
    function mailOutgoingMessage(bytes memory to_, bytes memory message_) public override {
        // Retrieve and increment the outbound nonce for the recipient
        uint256 outboundNonce = sendNonces[bytes32(to_)] + 1;

        // Update the nonce in storage
        sendNonces[bytes32(to_)] = outboundNonce;

        // Encode the updated nonce
        bytes memory nonceBytes = abi.encodePacked(outboundNonce);

        // Send the message
        sendMessage(targetChainId, to_, message_, nonceBytes);
    }

    /// @dev Facilitates the sending of messages ensuring only the router can initiate this and the source chain is the settlement chain.
    function sendMessage(bytes memory rollupChainId_, bytes memory receiver_, bytes memory message_, bytes memory data_)
        public
        payable
        override
        returns (bool)
    {
        // Emit the message sent event
        emit MessageSent(receiver_, rollupChainId_, message_, data_);

        return true;
    }
}
