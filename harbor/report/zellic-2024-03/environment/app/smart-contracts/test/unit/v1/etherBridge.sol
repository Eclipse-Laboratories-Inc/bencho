pragma solidity 0.8.21;

import {IEtherBridge} from "../../../src/v1/interfaces/IEtherBridge.sol";
import {Treasury} from "../../../src/v1/Treasury.sol";
import {EtherBridge} from "../../../src/v1/EtherBridge.sol";
import {IRegistry} from "../../../src/v1/interfaces/IRegistry.sol";
import {MockRegistry} from "./MockRegistry.sol";
import {MockRouter} from "./MockRouter.sol";
import {Test, console2} from "forge-std/Test.sol";

interface IExtendedEtherBridge is IEtherBridge {
    function initialize(address registryAddress) external;
}

contract EtherBridge_Test is Test {
    uint256 constant DEFAULT_GAS_PRICE = 1 wei;
    EtherBridge internal etherBridge;
    IRegistry internal registry;
    address internal routerAddress;
    address payable internal treasuryAddress;

    event Deposited(address indexed sender, bytes32 indexed recipient, uint256 amount, uint256 fee);

    function setUp() public virtual {
        // Deploy and set up the registry mock
        // Assuming Registry is a contract that implements IRegistry
        MockRegistry registryMock = new MockRegistry();
        registry = IRegistry(address(registryMock));

        // Deploy and set up the router mock or actual router contract
        // Assuming Router is a contract you wish to use
        MockRouter routerMock = new MockRouter();
        routerAddress = address(routerMock);

        // Deploy treasury
        Treasury treasury = new Treasury();
        treasuryAddress = payable(address(treasury));

        // Register the router address in the registry mock
        registryMock.registerContract("Router", routerAddress, IRegistry.ContractType.ROUTER);
        registryMock.registerContract("Treasury", treasuryAddress, IRegistry.ContractType.MODULE);

        // Deploy the EtherBridge contract
        etherBridge = new EtherBridge();

        // Initialize the EtherBridge contract
        etherBridge.initialize(address(registry));
    }

    function test_EtherBridge_Success() external {
        vm.txGasPrice(DEFAULT_GAS_PRICE);

        uint256 depositAmount = etherBridge.minDepositAmount();
        uint256 fee = etherBridge.estimateFee();
        uint256 total = fee + depositAmount;
        bytes32 recipient = bytes32(uint256(uint160(address(this))));

        vm.expectEmit(true, true, false, false);
        emit Deposited(address(this), recipient, depositAmount, fee);

        etherBridge.deposit{value: total}(recipient, depositAmount, fee);
    }

    function test_EtherBridge_Deposit_InvalidDepositAmount() external {
        vm.txGasPrice(DEFAULT_GAS_PRICE);

        uint256 invalidDepositAmount = etherBridge.minDepositAmount() - 1;
        uint256 fee = etherBridge.estimateFee();
        uint256 total = fee + invalidDepositAmount;
        bytes32 recipient = bytes32(uint256(uint160(address(this))));

        // Expect the transaction to revert with the specific error message
        vm.expectRevert("Deposit amount must be greater than equal to the minimum wei amount");

        // Call the deposit function with the invalid amount
        etherBridge.deposit{value: total}(recipient, invalidDepositAmount, 0);
    }

    function test_EtherBridge_Deposit_InsufficientFee() external {
        vm.txGasPrice(DEFAULT_GAS_PRICE);

        uint256 depositAmount = etherBridge.minDepositAmount();
        uint256 insufficientFee = etherBridge.estimateFee() - 1;
        uint256 total = insufficientFee + depositAmount;
        bytes32 recipient = bytes32(uint256(uint160(address(this))));

        // Expect the transaction to revert due to insufficient fee
        vm.expectRevert("Deposit fee amount is not enough to execute call");

        // Call the deposit function
        etherBridge.deposit{value: total}(recipient, depositAmount, insufficientFee);
    }

    function test_EtherBridge_Deposit_IncorrectDepositValue() external {
        vm.txGasPrice(DEFAULT_GAS_PRICE);

        uint256 depositAmount = etherBridge.minDepositAmount();
        uint256 fee = etherBridge.estimateFee();
        uint256 total = fee + depositAmount;
        bytes32 recipient = bytes32(uint256(uint160(address(this))));

        // Expect the transaction to revert due to incorrect total value sent
        vm.expectRevert("Deposit amount and fee must match sent value");

        // Call the deposit function with incorrect total value
        etherBridge.deposit{value: total - 1}(recipient, depositAmount, fee);
    }

    function test_EtherBridge_Deposit_CallAmountInsufficient() external {
        vm.txGasPrice(DEFAULT_GAS_PRICE);

        uint256 depositAmount = etherBridge.minDepositAmount();
        uint256 fee = etherBridge.estimateFee();
        uint256 total = depositAmount + fee - 1;
        bytes32 recipient = bytes32(uint256(uint160(address(this))));

        // Expect the transaction to revert due to insufficient amount
        vm.expectRevert("Deposit amount and fee must match sent value");
        etherBridge.deposit{value: total}(recipient, depositAmount, fee);
    }

    function test_EtherBridge_Deposit_RecipientNotSet() external {
        vm.txGasPrice(DEFAULT_GAS_PRICE);

        uint256 depositAmount = etherBridge.minDepositAmount();
        uint256 fee = etherBridge.estimateFee();
        uint256 total = fee + depositAmount;
        bytes32 recipient = bytes32(0);

        // Expect the transaction to revert due to recipient not set
        vm.expectRevert("Recipient address is not set");

        // Call the deposit function
        etherBridge.deposit{value: total}(recipient, depositAmount, fee);
    }

    function test_EtherBridge_Deposit_RouterRevertOrFail() external {
        vm.txGasPrice(DEFAULT_GAS_PRICE);
        MockRouter(routerAddress).setShouldRevert(true);

        uint256 margin = 20;
        uint256 depositAmount = 1 ether;
        uint256 fee = etherBridge.estimateFee();
        uint256 total = fee + depositAmount;
        bytes32 recipient = bytes32(uint256(uint160(address(this))));

        uint256 gasBefore = gasleft();
        vm.expectRevert("MockRouter: Forced revert");
        etherBridge.deposit{value: total}(recipient, depositAmount, fee);
        uint256 gasAfter = gasleft();
        uint256 gasUsed = gasBefore - gasAfter;

        assert(gasUsed > 0);
        assertTrue(gasUsed < fee / margin, "Gas used should be less than the fee over the margin");
    }

    function test_EtherBridge_Deposit_RouterUsesAllGas() external {
        vm.txGasPrice(DEFAULT_GAS_PRICE);
        MockRouter(routerAddress).setShouldConsumeAllGas(true);

        uint256 margin = 20;
        uint256 depositAmount = 1 ether;
        uint256 fee = etherBridge.estimateFee();
        uint256 total = fee + depositAmount;
        bytes32 recipient = bytes32(uint256(uint160(address(this))));

        uint256 gasBefore = gasleft();

        vm.expectRevert(bytes("")); // Expect any revert
        etherBridge.deposit{value: total}(recipient, depositAmount, fee);
        uint256 gasAfter = gasleft();
        uint256 gasUsed = gasBefore - gasAfter;

        assert(gasUsed > 0);
        console2.log("gasUsed", gasUsed);
        console2.log("fee / margin", fee / margin);
        assertTrue(gasUsed < fee / margin, "Gas used should be less than the fee over the margin");
    }

    //    function test_EtherBridge_Deposit_CallFallbackUsesTooMuchGas() external {
    //        // Test for 'call' where fallback function uses too much gas in treasury.
    //        // This probably requires the treasury address to be passed in so need to refactor ether bridge constructor
    //    }
    //
    //    function test_EtherBridge_Deposit_CallFailsDueToSelfDestructedTreasury() external {
    //        // Test for 'call' failing because treasury address is self-destructed
    //    }

    // TODO: test max deposit and withdraw
}
