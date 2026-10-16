pragma solidity 0.8.21;

import {SimulatedMailbox} from "../../../src/v1/SimulatedMailbox.sol";
import {Test, console2} from "forge-std/Test.sol";

contract SimulatedMailbox_Test is Test {
    uint256 constant DEFAULT_GAS_PRICE = 1 wei;
    SimulatedMailbox internal mailbox;

    function setUp() public virtual {
        // Deploy the EtherBridge contract
        mailbox = new SimulatedMailbox();
    }

    function test_EtherBridge_Success() external {
        vm.txGasPrice(DEFAULT_GAS_PRICE);

        uint256 depositAmount = 1 ether;
        uint256 fee = 200_000 gwei;
        uint256 total = fee + depositAmount;
        mailbox.simpleSimulateDeposit{value: total}();

        // TODO: add listener to event and ensure its expected deposit message
    }
}
