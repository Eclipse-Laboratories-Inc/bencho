// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {Mailbox} from "../../src/v1/Mailbox.sol";
import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";

contract Eclipse006_Test is Test {
    function test_audit_messageSentUsesEclipseChainId() external {
        Mailbox mailbox = new Mailbox();
        string memory ethereumChainId = "eth-mainnet";
        string memory eclipseChainId = "eclipse-chain";

        bytes32[] memory ids = new bytes32[](1);
        ids[0] = keccak256("module");
        address[] memory modules = new address[](1);
        modules[0] = address(this);

        mailbox.initialize(
            Mailbox.InitParams({
                trustedRelayer: address(0xBEEF),
                ids: ids,
                modules: modules,
                ethereumChainId: ethereumChainId,
                eclipseChainId: eclipseChainId
            })
        );

        vm.recordLogs();
        mailbox.sendMessage("", abi.encodePacked("receiver"), abi.encodePacked("payload"), "");

        bytes32 want = keccak256(abi.encodePacked(eclipseChainId));
        bytes32 topic = keccak256("MessageSent(bytes,bytes,bytes,bytes)");
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool found;
        bytes32 got;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics.length > 0 && logs[i].topics[0] == topic) {
                (, bytes memory toChainId,,) = abi.decode(logs[i].data, (bytes, bytes, bytes, bytes));
                got = abi.decode(toChainId, (bytes32));
                found = true;
            }
        }
        assertTrue(found, "MessageSent was not emitted");
        assertEq(got, want);
    }
}
