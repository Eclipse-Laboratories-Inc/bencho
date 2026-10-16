// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {IEtherBridge} from "../../src/v1/interfaces/IEtherBridge.sol";
import {IRegistry} from "../../src/v1/interfaces/IRegistry.sol";
import {Treasury} from "../../src/v1/Treasury.sol";
import {EtherBridge} from "../../src/v1/EtherBridge.sol";
import {Mailbox} from "../../src/v1/Mailbox.sol";
import {MockRegistry} from "../unit/v1/MockRegistry.sol";
import {MockRouter} from "../unit/v1/MockRouter.sol";
import {MockContract} from "../unit/v1/MockContract.sol";
import {Test} from "forge-std/Test.sol";

contract Eclipse003_Test is Test {
    EtherBridge internal etherBridge;
    Mailbox internal mailbox;
    MockRouter internal router;

    function setUp() public {
        MockRegistry registryMock = new MockRegistry();
        router = new MockRouter();
        MockContract module = new MockContract();

        Treasury treasury = new Treasury();
        registryMock.registerContract("Router", address(router), IRegistry.ContractType.ROUTER);
        registryMock.registerContract("Treasury", address(treasury), IRegistry.ContractType.MODULE);
        registryMock.registerContract("Registry", address(registryMock), IRegistry.ContractType.REGISTRY);
        registryMock.registerContract("Mock", address(module), IRegistry.ContractType.MODULE);

        etherBridge = new EtherBridge();
        etherBridge.initialize(address(registryMock));
        vm.deal(address(treasury), 1 ether);

        mailbox = new Mailbox();
        mailbox.initialize(bytes("ETH"), bytes("ECLIPSE"), makeAddr("relayer"), address(registryMock));
    }

    function test_audit_withdrawRejectsZeroRecipient() external {
        IEtherBridge.WithdrawMessage memory message = IEtherBridge.WithdrawMessage({
            sender: bytes32(uint256(1)),
            recipient: address(0),
            amount: 1
        });
        vm.prank(address(router));
        vm.expectRevert();
        etherBridge.withdraw(message);
    }

    function test_audit_mailOutgoingRejectsEmptyDestination() external {
        vm.prank(address(router));
        vm.expectRevert();
        mailbox.mailOutgoingMessage("", "hello");
    }
}
