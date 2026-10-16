pragma solidity 0.8.21;

import {Mailbox} from "../../../src/v1/Mailbox.sol";
import "openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import "openzeppelin-contracts-upgradeable/contracts/utils/ReentrancyGuardUpgradeable.sol";
import "forge-std/Test.sol";

contract MockModule {
    function callExternal(address target, bytes memory data) external returns (bool, bytes memory) {
        return target.call(data);
    }

    function receiveCall() public {}

    function failingCall() public {
        revert();
    }
}

contract MailboxTest is Test {
    Mailbox private mailbox;
    address private constant trustedRelayer = address(0xA);
    bytes32[] private moduleIds;
    address[] private modules;
    string private constant ethereumChainId = "ETH";
    string private constant eclipseChainId = "ECL";

    event MessageReceived(bytes sender, bytes chainId, bytes message, bytes data);
    event MessageSent(bytes receiver, bytes chainId, bytes message, bytes data);

    function setUp() public {
        moduleIds = [keccak256(abi.encodePacked("MockModule1")), keccak256(abi.encodePacked("MockModule2"))];
        modules = [address(new MockModule()), address(new MockModule())];

        Mailbox.InitParams memory params = Mailbox.InitParams({
            trustedRelayer: trustedRelayer,
            ids: moduleIds,
            modules: modules,
            ethereumChainId: ethereumChainId,
            eclipseChainId: eclipseChainId
        });
        mailbox = new Mailbox();
        mailbox.initialize(params);
    }

    //    // Test initial setup
    function test_Mailbox_CannotInitAgain() public {
        // Expect a revert on calling initialize again
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        mailbox.initialize(
            Mailbox.InitParams({
                trustedRelayer: trustedRelayer,
                ids: moduleIds,
                modules: modules,
                ethereumChainId: ethereumChainId,
                eclipseChainId: eclipseChainId
            })
        );
    }

    // Access control tests
    function test_Mailbox_OnlyTrustedRelayerCanReceiveMessages() public {
        bytes memory message = "Hello";
        bytes memory data = abi.encode(Mailbox.EclipseSecurityParam({nonce: 1}));

        // Emulate a call from a non-trusted relayer
        vm.prank(address(0xABC));
        vm.expectRevert("Only the trusted relayer can call this method.");
        mailbox.receiveMessage(abi.encode(eclipseChainId), abi.encode(moduleIds[0]), message, data);
    }

    function test_Mailbox_OnlyModuleCanSendMessage() public {
        bytes memory message = "Hello";
        // Emulate a call from a non-authorized module
        vm.prank(address(0xABC));
        vm.expectRevert("Only an authorized module can call this method.");
        mailbox.sendMessage(abi.encode(ethereumChainId), abi.encode(moduleIds[0]), message, "");
    }

    // Functionality tests for `receiveMessage`
    function test_Mailbox_ReceiveMessageWithValidNonce() public {
        bytes memory message = abi.encodeWithSelector(MockModule.receiveCall.selector);
        bytes memory data = abi.encode(Mailbox.EclipseSecurityParam({nonce: 1}));
        bytes memory chainId = abi.encode(keccak256(abi.encodePacked(eclipseChainId)));
        vm.prank(trustedRelayer);
        bool result = mailbox.receiveMessage(chainId, abi.encode(moduleIds[0]), message, data);
        assertTrue(result);
    }

    function test_Mailbox_RejectsMessageWithDuplicateNonce() public {
        bytes memory message = abi.encodeWithSelector(MockModule.receiveCall.selector);
        bytes memory data = abi.encode(Mailbox.EclipseSecurityParam({nonce: 1}));
        bytes memory chainId = abi.encode(keccak256(abi.encodePacked(eclipseChainId)));
        vm.prank(trustedRelayer);
        bool result = mailbox.receiveMessage(chainId, abi.encode(moduleIds[0]), message, data);
        assertTrue(result);
        vm.stopPrank();

        vm.prank(trustedRelayer);
        vm.expectRevert("Message with this nonce already received.");
        mailbox.receiveMessage(chainId, abi.encode(moduleIds[0]), message, data);
    }

    function test_Mailbox_RejectsMessageFromUnrecognizedModule() public {
        bytes memory message = "Hello";
        bytes memory data = abi.encode(Mailbox.EclipseSecurityParam({nonce: 1}));
        bytes memory chainId = abi.encode(keccak256(abi.encodePacked(eclipseChainId)));
        vm.prank(trustedRelayer);
        vm.expectRevert("Module does not exist.");
        mailbox.receiveMessage(chainId, abi.encode(keccak256("UnknownModule")), message, data);
    }

    function test_Mailbox_FailsOnExternalCallFailure() public {
        bytes memory message = abi.encodeWithSelector(MockModule.failingCall.selector);
        bytes memory data = abi.encode(Mailbox.EclipseSecurityParam({nonce: 1}));
        bytes memory chainId = abi.encode(keccak256(abi.encodePacked(eclipseChainId)));
        vm.prank(trustedRelayer);
        vm.expectRevert("External call to module failed.");
        mailbox.receiveMessage(chainId, abi.encode(moduleIds[0]), message, data);
    }

    function test_Mailbox_EmitsEventOnMessageReceived() public {
        bytes memory message = abi.encodeWithSelector(MockModule.receiveCall.selector);
        bytes memory data = abi.encode(Mailbox.EclipseSecurityParam({nonce: 1}));
        bytes memory chainId = abi.encode(keccak256(abi.encodePacked(eclipseChainId)));
        vm.prank(trustedRelayer);
        vm.expectEmit(true, true, true, true);
        emit MessageReceived(abi.encode(moduleIds[0]), chainId, message, data);
        mailbox.receiveMessage(chainId, abi.encode(moduleIds[0]), message, data);
    }

    // Functionality tests for `sendMessage`
    function test_Mailbox_SendMessageGeneratesNonce() public {
        bytes memory message = "Hello";
        vm.prank(modules[0]);
        bool result = mailbox.sendMessage(abi.encode(ethereumChainId), abi.encode(moduleIds[0]), message, "");
        assertTrue(result);
    }

    function test_Mailbox_EmitsEventOnMessageSent() public {
        bytes memory message = "Hello";
        bytes memory data = abi.encode(Mailbox.EclipseSecurityParam({nonce: 1}));
        bytes memory chainId = abi.encode(keccak256(abi.encodePacked(ethereumChainId)));
        vm.prank(modules[0]);
        vm.expectEmit(true, true, true, false); // TODO: need a way to expect a deterministic first nonce
        emit MessageSent(abi.encode(moduleIds[0]), chainId, message, data);
        mailbox.sendMessage(chainId, abi.encode(moduleIds[0]), message, data);
    }

    // Edge case tests (TODO: do all the tests for the 'require' checks in initialize
    function test_Mailbox_HandleZeroAddressesInInitialization() public {
        Mailbox m = new Mailbox();
        Mailbox.InitParams memory params = Mailbox.InitParams({
            trustedRelayer: address(0),
            ids: moduleIds,
            modules: modules,
            ethereumChainId: ethereumChainId,
            eclipseChainId: eclipseChainId
        });
        vm.expectRevert("CommonUtility: zero address");
        m.initialize(params);
    }
}
