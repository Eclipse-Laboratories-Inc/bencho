// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {IEtherBridge} from "../../src/v1/interfaces/IEtherBridge.sol";
import {IRegistry} from "../../src/v1/interfaces/IRegistry.sol";
import {Treasury} from "../../src/v1/Treasury.sol";
import {EtherBridge} from "../../src/v1/EtherBridge.sol";
import {MockRegistry} from "../unit/v1/MockRegistry.sol";
import {MockRouter} from "../unit/v1/MockRouter.sol";
import {Test} from "forge-std/Test.sol";

contract Eclipse002_Test is Test {
    uint256 internal constant WEI_PER_LAMPORT = 1_000_000_000;

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
        vm.deal(treasuryAddress, 1 ether);
    }

    function test_audit_withdrawConvertsLamportsToWei() external {
        address recipient = makeAddr("recipient");
        uint256 lamports = 5;
        IEtherBridge.WithdrawMessage memory message = IEtherBridge.WithdrawMessage({
            sender: bytes32(uint256(1)),
            recipient: recipient,
            amount: lamports
        });

        uint256 beforeBalance = recipient.balance;
        vm.prank(routerAddress);
        etherBridge.withdraw(message);

        assertEq(recipient.balance - beforeBalance, lamports * WEI_PER_LAMPORT);
    }
}
