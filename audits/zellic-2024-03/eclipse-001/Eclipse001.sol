// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {IEtherBridge} from "../../src/v1/interfaces/IEtherBridge.sol";
import {IRegistry} from "../../src/v1/interfaces/IRegistry.sol";
import {Treasury} from "../../src/v1/Treasury.sol";
import {EtherBridge} from "../../src/v1/EtherBridge.sol";
import {MockRegistry} from "../unit/v1/MockRegistry.sol";
import {MockRouter} from "../unit/v1/MockRouter.sol";
import {Test} from "forge-std/Test.sol";

contract Eclipse001_Test is Test {
    EtherBridge internal etherBridge;
    address internal routerAddress;
    address payable internal treasuryAddress;

    function setUp() public {
        MockRegistry registryMock = new MockRegistry();
        MockRouter routerMock = new MockRouter();
        routerAddress = address(routerMock);

        Treasury treasury = new Treasury();
        treasuryAddress = payable(address(treasury));

        registryMock.registerContract("Router", routerAddress, IRegistry.ContractType.ROUTER);
        registryMock.registerContract("Treasury", treasuryAddress, IRegistry.ContractType.MODULE);

        etherBridge = new EtherBridge();
        etherBridge.initialize(address(registryMock));
    }

    function test_audit_depositLocksFullWeiInTreasury() external {
        vm.txGasPrice(1);
        vm.deal(address(this), 10 ether);

        uint256 depositAmount = etherBridge.minDepositAmount();
        uint256 fee = etherBridge.estimateFee();
        bytes32 recipient = bytes32(uint256(uint160(address(this))));
        uint256 treasuryBefore = treasuryAddress.balance;

        etherBridge.deposit{value: depositAmount + fee}(recipient, depositAmount, fee);

        assertEq(treasuryAddress.balance - treasuryBefore, depositAmount);
    }
}
