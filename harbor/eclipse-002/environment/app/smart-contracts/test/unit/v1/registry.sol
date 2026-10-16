pragma solidity 0.8.21;

import {IRegistry} from "../../../src/v1/interfaces/IRegistry.sol";
import {Registry} from "../../../src/v1/Registry.sol";
import {Test} from "forge-std/Test.sol";
import "./MockContract.sol";

contract Registry_Test is Test {
    Registry internal registry;
    MockContract internal mockContract;

    event ContractRegistered(string identifier, address contractAddress);
    event ContractUnregistered(string identifier, address contractAddress);

    function setUp() public virtual {
        registry = new Registry();
        registry.initialize();
        mockContract = new MockContract();
    }

    function test_Registry_RegisterContractWithValidDetails_Success() external {
        registry.registerContract("Mock", address(mockContract), IRegistry.ContractType.OTHER);
        assertEq(registry.getAddress("Mock"), address(mockContract));
    }

    function test_Registry_RegisterContractWithInvalidIdentifier_Failure() external {
        vm.expectRevert("Invalid contract identifier");
        registry.registerContract("", address(mockContract), IRegistry.ContractType.OTHER);
    }

    function test_Registry_RegisterContractWithInvalidAddress_Failure() external {
        vm.expectRevert("Invalid contract address");
        registry.registerContract("Mock", address(0), IRegistry.ContractType.OTHER);
    }

    function test_Registry_RegisterContractByNonOwner_Failure() external {
        address nonOwner = address(1);
        vm.prank(nonOwner);
        vm.expectRevert();
        registry.registerContract("Mock", address(mockContract), IRegistry.ContractType.OTHER);
    }

    function test_Registry_UnregisterRegisteredContract_Success() external {
        registry.registerContract("Mock", address(mockContract), IRegistry.ContractType.OTHER);
        registry.unregisterContract("Mock");
        vm.expectRevert("Identifier not registered");
        registry.getAddress("Mock");
    }

    function test_Registry_UnregisterNonExistentContract_Failure() external {
        vm.expectRevert("Contract not registered");
        registry.unregisterContract("NonExistent");
    }

    function test_Registry_UnregisterContractByNonOwner_Failure() external {
        address nonOwner = address(1);
        vm.prank(nonOwner);
        vm.expectRevert();
        registry.unregisterContract("Mock");
    }

    function test_Registry_GetAddressOfRegisteredContract_Success() external {
        registry.registerContract("Mock", address(mockContract), IRegistry.ContractType.OTHER);
        assertEq(registry.getAddress("Mock"), address(mockContract));
    }

    function test_Registry_GetAddressOfUnregisteredContract_Failure() external {
        vm.expectRevert("Identifier not registered");
        registry.getAddress("NonExistent");
    }

    function test_Registry_GetIdentifierOfRegisteredContract_Success() external {
        registry.registerContract("Mock", address(mockContract), IRegistry.ContractType.OTHER);
        assertEq(registry.getIdentifier(address(mockContract)), "Mock");
    }

    function test_Registry_GetIdentifierOfUnregisteredContract_Failure() external {
        vm.expectRevert("Address not registered");
        registry.getIdentifier(address(2));
    }

    function test_Registry_GetContractTypeOfRegisteredContract_Success() external {
        registry.registerContract("Mock", address(mockContract), IRegistry.ContractType.OTHER);
        assertEq(uint256(registry.getContractType(address(mockContract))), uint256(IRegistry.ContractType.OTHER));
    }

    function test_Registry_GetContractTypeOfUnregisteredContract_Failure() external {
        vm.expectRevert("Address not registered");
        registry.getContractType(address(2));
    }

    // Event tests
    function test_Registry_ContractRegisteredEvent_EmittedOnSuccessfulRegistration() external {
        vm.expectEmit(true, true, true, true);
        emit ContractRegistered("Mock", address(mockContract));
        registry.registerContract("Mock", address(mockContract), IRegistry.ContractType.OTHER);
    }

    function test_Registry_ContractUnregisteredEvent_EmittedOnSuccessfulUnregistration() external {
        registry.registerContract("Mock", address(mockContract), IRegistry.ContractType.OTHER);
        vm.expectEmit(true, true, true, true);
        emit ContractUnregistered("Mock", address(mockContract));
        registry.unregisterContract("Mock");
    }
}
