// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {IRouter} from "../../src/v1/interfaces/IRouter.sol";
import {IRegistry} from "../../src/v1/interfaces/IRegistry.sol";
import {Mailbox} from "../../src/v1/Mailbox.sol";
import {MockRegistry} from "../unit/v1/MockRegistry.sol";
import {MockContract} from "../unit/v1/MockContract.sol";
import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";

contract NonceProbe is IRouter {
    uint64 public nonce;
    bool public nonceMarked;
    Vm internal constant CHEAT = Vm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    function setNonce(uint64 nonce_) external {
        nonce = nonce_;
    }

    function routeIncomingMessage(bytes calldata, bytes calldata) external payable override {
        for (uint256 slot = 0; slot < 12; slot++) {
            bytes32 key = keccak256(abi.encode(nonce, slot));
            if (CHEAT.load(msg.sender, key) == bytes32(uint256(1))) {
                nonceMarked = true;
            }
        }
    }

    function routeOutgoingMessage(bytes calldata) external payable override {}
}

contract Eclipse004_Test is Test {
    Mailbox internal mailbox;
    NonceProbe internal probe;
    bytes internal eclipseChainId;
    uint256 internal relayerPrivateKey = 0xdeadbeef;
    address internal relayer;

    function setUp() public {
        MockRegistry registryMock = new MockRegistry();
        probe = new NonceProbe();
        MockContract module = new MockContract();

        registryMock.registerContract("Registry", address(registryMock), IRegistry.ContractType.REGISTRY);
        registryMock.registerContract("Router", address(probe), IRegistry.ContractType.ROUTER);
        registryMock.registerContract("Mock", address(module), IRegistry.ContractType.MODULE);

        eclipseChainId = bytes("ECLIPSE");
        relayer = vm.addr(relayerPrivateKey);
        mailbox = new Mailbox();
        mailbox.initialize(bytes("ETH"), eclipseChainId, relayer, address(registryMock));
    }

    function test_audit_nonceMarkedBeforeRouterCall() external {
        bytes memory sender = abi.encodePacked("Mock");
        bytes memory message = "Received message";
        uint64 nonce = 42;
        probe.setNonce(nonce);

        bytes32 hash = keccak256(abi.encodePacked(eclipseChainId, sender, message, nonce));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(relayerPrivateKey, hash);
        bytes memory data = abi.encode(Mailbox.EclipseSecurityParam(nonce, abi.encodePacked(r, s, v)));

        vm.prank(relayer);
        bool ok = mailbox.receiveMessage(eclipseChainId, sender, message, data);
        assertTrue(ok);
        assertTrue(probe.nonceMarked(), "nonce was not marked before the router call");
    }

    function test_keep_receiveMessageRejectsReplayedNonce() external {
        bytes memory sender = abi.encodePacked("Mock");
        bytes memory message = "Received message";
        uint64 nonce = 43;
        probe.setNonce(nonce);
        bytes32 hash = keccak256(abi.encodePacked(eclipseChainId, sender, message, nonce));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(relayerPrivateKey, hash);
        bytes memory data = abi.encode(Mailbox.EclipseSecurityParam(nonce, abi.encodePacked(r, s, v)));
        vm.prank(relayer);
        assertTrue(mailbox.receiveMessage(eclipseChainId, sender, message, data));
        vm.prank(relayer);
        vm.expectRevert();
        mailbox.receiveMessage(eclipseChainId, sender, message, data);
    }
}
