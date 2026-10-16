pragma solidity 0.8.21;

import {Mailbox} from "../../../src/v1/Mailbox.sol";
import "forge-std/Test.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {MockRegistry} from "./MockRegistry.sol";
import {MockRouter} from "./MockRouter.sol";
import {MockContract} from "./MockContract.sol";
import {IRegistry} from "../../../src/v1/interfaces/IRegistry.sol";
import {IRoutableMailbox as IMailbox} from "../../../src/v1/interfaces/IRoutableMailbox.sol";
import {ECDSA} from "openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "openzeppelin-contracts/contracts/utils/cryptography/MessageHashUtils.sol";

contract Mailbox_Test is Test {
    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;

    IMailbox internal mailbox;
    MockRegistry internal mockRegistry;
    MockRouter internal mockRouter;
    MockContract internal mockContract;
    bytes ethereumChainId;
    bytes eclipseChainId;
    uint256 relayerPrivateKey = 0xdeadbeef;
    address relayer;

    function setUp() public virtual {
        mockRegistry = new MockRegistry();
        mockRouter = new MockRouter();
        mockContract = new MockContract();
        Mailbox mailboxImpl = new Mailbox();

        // Set up the registry with necessary contracts
        mockRegistry.registerContract("Registry", address(mockRegistry), IRegistry.ContractType.REGISTRY);
        mockRegistry.registerContract("Router", address(mockRouter), IRegistry.ContractType.ROUTER);
        mockRegistry.registerContract("Mailbox", address(mailboxImpl), IRegistry.ContractType.MAILBOX);
        mockRegistry.registerContract("Mock", address(mockContract), IRegistry.ContractType.MODULE);

        // Initialize the mailbox
        ethereumChainId = bytes("ETH");
        eclipseChainId = bytes("ECLIPSE");
        relayer = vm.addr(relayerPrivateKey);
        mailboxImpl.initialize(ethereumChainId, eclipseChainId, relayer, address(mockRegistry));
        mailbox = mailboxImpl;
    }

    function test_Mailbox_ReceiveMessage_Success() external {
        bytes memory sender = abi.encodePacked("Mock");
        bytes memory message = "Received message";
        uint64 nonce = 0;

        // Create the security param with relayer private key
        bytes32 hash = keccak256(abi.encodePacked(eclipseChainId, sender, message, nonce));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(relayerPrivateKey, hash);
        bytes memory signature = abi.encodePacked(r, s, v);
        bytes memory data = abi.encode(Mailbox.EclipseSecurityParam(nonce, signature));

        vm.prank(relayer);
        bool success = mailbox.receiveMessage(eclipseChainId, sender, message, data);
        assertTrue(success);
    }

    function test_Mailbox_ReceiveMessage_OnlyRelayer() external {
        bytes memory sender = abi.encodePacked("EtherBridge");
        bytes memory message = "Received message";
        bytes memory data = abi.encode(1);

        address nonRelayer = address(1);
        vm.prank(nonRelayer);
        vm.expectRevert("Only the relayer can call this method.");
        mailbox.receiveMessage(eclipseChainId, sender, message, data);
    }

    function test_Mailbox_MailOutgoingMessage_Success() external {
        bytes memory to = abi.encodePacked("EtherBridge");
        bytes memory message = "Outgoing message";

        vm.prank(address(mockRouter)); // Simulate call from Router
        mailbox.mailOutgoingMessage(to, message);
    }

    function test_Mailbox_MailOutgoingMessage_OnlyRouter() external {
        bytes memory to = abi.encodePacked("EtherBridge");
        bytes memory message = "Outgoing message";

        address nonRouter = address(1);
        vm.prank(nonRouter);
        vm.expectRevert("Only the router can call this method.");
        mailbox.mailOutgoingMessage(to, message);
    }

    function test_Mailbox_OutgoingMessageWithInvalidByteLength() external {
        bytes memory to = new bytes(33); // Invalid byte length
        bytes memory message = "Test message";

        vm.prank(address(mockRouter)); // Simulate call from Router
        vm.expectRevert("The encoded identifier must be less than equal to 32 bytes");
        mailbox.mailOutgoingMessage(to, message);
    }

    function test_Mailbox_OutgoingMessageWithEmptyMessage() external {
        bytes memory to = abi.encodePacked("EtherBridge");
        bytes memory message = ""; // Empty message

        vm.prank(address(mockRouter)); // Simulate call from Router
        vm.expectRevert("Message must be provided");
        mailbox.mailOutgoingMessage(to, message);
    }

    function test_Mailbox_ReceiveMessageWithInvalidChainIdLength() external {
        bytes memory invalidTargetChainId = new bytes(33); // Invalid byte length
        bytes memory sender = abi.encodePacked("Mock");
        bytes memory message = "Received message";
        uint64 nonce = 0;

        // Create the security param with relayer private key
        bytes32 hash = keccak256(abi.encodePacked(invalidTargetChainId, sender, message, nonce));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(relayerPrivateKey, hash);
        bytes memory signature = abi.encodePacked(r, s, v);
        bytes memory data = abi.encode(Mailbox.EclipseSecurityParam(nonce, signature));

        vm.prank(relayer);
        vm.expectRevert("Unsupported Eclipse chain id.");
        mailbox.receiveMessage(invalidTargetChainId, sender, message, data);
    }

    function test_Mailbox_ReceiveMessageWithUnsupportedChainId() external {
        bytes memory invalidTargetChainId = bytes("UNSUPPORTED");
        bytes memory sender = abi.encodePacked("Mock");
        bytes memory message = "Received message";
        uint64 nonce = 0;

        // Create the security param with relayer private key
        bytes32 hash = keccak256(abi.encodePacked(invalidTargetChainId, sender, message, nonce));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(relayerPrivateKey, hash);
        bytes memory signature = abi.encodePacked(r, s, v);
        bytes memory data = abi.encode(Mailbox.EclipseSecurityParam(nonce, signature));

        vm.prank(relayer);
        vm.expectRevert("Unsupported Eclipse chain id.");
        mailbox.receiveMessage(invalidTargetChainId, sender, message, data);
    }

    function test_Mailbox_SendMessageWithUnsupportedEclipseChainId() external {
        bytes memory eclipseChainId = bytes("UNSUPPORTED");
        bytes memory receiver = abi.encodePacked(address(mockContract));
        bytes memory message = "Test message";
        bytes memory data = abi.encode(1); // Dummy data

        vm.prank(address(mockRouter)); // Simulate call from Router
        vm.expectRevert("Unsupported Ethereum chain id.");
        mailbox.sendMessage(eclipseChainId, receiver, message, data);
    }

}
