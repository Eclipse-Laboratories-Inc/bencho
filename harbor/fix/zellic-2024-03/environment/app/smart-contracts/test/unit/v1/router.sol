pragma solidity 0.8.21;

import {IRouter} from "../../../src/v1/interfaces/IRouter.sol";
import {IRoutableMailbox} from "../../../src/v1/interfaces/IRoutableMailbox.sol";
import {IRegistry} from "../../../src/v1/interfaces/IRegistry.sol";
import {Router} from "../../../src/v1/Router.sol";
import {MockRoutableMailbox as Mailbox} from "./MockRoutableMailbox.sol";
import {Test, console2} from "forge-std/Test.sol";
import {MockRegistry} from "./MockRegistry.sol";
import {MockContract} from "./MockContract.sol";

contract Router_Test is Test {
    IRouter internal router;
    MockRegistry internal mockRegistry;
    IRoutableMailbox internal mockMailbox;
    MockContract internal mockContract;

    function setUp() public virtual {
        mockRegistry = new MockRegistry();
        mockContract = new MockContract();
        mockMailbox = new Mailbox();
        Router routerImpl = new Router();

        mockRegistry.registerContract("Registry", address(mockRegistry), IRegistry.ContractType.REGISTRY);
        mockRegistry.registerContract("Mock", address(mockContract), IRegistry.ContractType.MODULE);
        mockRegistry.registerContract("Mailbox", address(mockMailbox), IRegistry.ContractType.MAILBOX);
        mockRegistry.registerContract("Router", address(routerImpl), IRegistry.ContractType.ROUTER);

        routerImpl.initialize(address(mockRegistry));

        router = routerImpl;
    }

    function test_Router_RouteIncomingMessage_Success() external {
        bytes memory encodedIdentifier = abi.encode("Mock");
        bytes memory message = "Test message";

        address mailboxAddress = address(mockMailbox);
        vm.prank(mailboxAddress);
        vm.expectCall(address(mockContract), message);
        router.routeIncomingMessage(encodedIdentifier, message);
    }

    function test_Router_RouteIncomingMessage_Fail_InvalidIdentifier() external {
        bytes memory encodedIdentifier = abi.encode("Invalid");
        bytes memory message = "Test message";

        address mailboxAddress = address(mockMailbox);
        vm.prank(mailboxAddress);

        vm.expectRevert("This identifier does not have a registered address");
        router.routeIncomingMessage(encodedIdentifier, message);
    }

    function test_Router_RouteIncomingMessage_OnlyOwner() external {
        address nonOwner = address(1);
        bytes memory encodedIdentifier = abi.encode("Mock");
        bytes memory message = "Test message";

        vm.prank(nonOwner);
        vm.expectRevert();
        router.routeIncomingMessage(encodedIdentifier, message);
    }

    function test_Router_RouteOutgoingMessage_Success() external {
        bytes memory message = "Outgoing message";
        address moduleContractAddress = address(mockContract);

        address mailboxAddress = address(mockMailbox);
        vm.prank(moduleContractAddress);
        vm.expectCall(
            mailboxAddress, abi.encodeWithSignature("mailOutgoingMessage(bytes,bytes)", bytes("Mock"), message)
        );
        router.routeOutgoingMessage(message);
    }

    function test_Router_RouteOutgoingMessage_OnlyModuleContract() external {
        address nonModuleContract = address(new MockContract());
        bytes memory message = "Outgoing message";

        vm.prank(nonModuleContract);
        vm.expectRevert("Caller is not a module contract");
        router.routeOutgoingMessage(message);
    }
}
