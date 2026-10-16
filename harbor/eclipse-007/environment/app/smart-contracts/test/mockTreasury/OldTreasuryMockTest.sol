// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import { Test } from "../../lib/forge-std/src/Test.sol";
import { ERC1967Proxy } from "../../lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { OldTreasuryMock } from "../mocks/OldTreasuryMock.sol";

contract OldTreasuryMockTest is Test {
    address private constant NULL_ADDRESS = address(0);
    OldTreasuryMock oldTreasuryImpl;
    OldTreasuryMock oldTreasury;
    ERC1967Proxy proxy;
    address deployer;
    address nonOwner;
    address newOwner;

    error OwnableUnauthorizedAccount(address account);
    error OwnableInvalidOwner(address owner);

    modifier whenOwnershipIsTransferredByTheOwner() {
        oldTreasury.transferOwnership(newOwner);
        _;
    }

    function setUp() public {
        deployer = address(this);
        nonOwner = address(0x123);
        newOwner = address(0x456);

        // Deploy and initialize the mock contract
        oldTreasuryImpl = new OldTreasuryMock();
        proxy = new ERC1967Proxy(
            address(oldTreasuryImpl),  // Address of the implementation
            abi.encodeWithSelector(oldTreasuryImpl.initialize.selector, address(this))
        );
        oldTreasury = OldTreasuryMock(payable(address(proxy)));

        vm.deal(deployer, 100 ether);
        payable(address(oldTreasury)).transfer(100 ether);

        // Check if 100 Ether was successfully transferred
        assertEq(address(oldTreasury).balance, 100 ether, "Treasury should have 100 Ether in setup");
    }

    function test_WhenOwnerIsQueried() external view {
        // it should return the deployer address
        assertEq(oldTreasury.owner(), deployer, "Owner should be the deployer");
    }

    function test_WhenANonOwnerCallsAnOnlyOwnerFunction() external {
        // it should revert with an ownership error
        vm.prank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, nonOwner));
        oldTreasury.withdraw(1 ether);
    }

    function test_WhenOwnershipIsTransferredByANon_owner() external {
        // it should revert with an ownership error
        vm.prank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, nonOwner));
        oldTreasury.transferOwnership(nonOwner);
    }

    function test_WhenToANonZeroAddress() external whenOwnershipIsTransferredByTheOwner {
        assertEq(oldTreasury.owner(), newOwner, "Owner should be the new owner");
    }

    function test_WhenOwnershipIsTransferredToTheZeroAddress() external {
        // it should revert with an invalid address error
        vm.expectRevert(abi.encodeWithSelector(OwnableInvalidOwner.selector, NULL_ADDRESS));
        oldTreasury.transferOwnership(NULL_ADDRESS);
    }

    function test_WhenTheNewOwnerCallsAnOnlyOwnerFunction() external whenOwnershipIsTransferredByTheOwner {
        // it should succeed
        vm.prank(newOwner);
        oldTreasury.withdraw(1 ether);  // New owner can withdraw
    }

    function test_WhenTheOldOwnerCallsAnOnlyOwnerFunction() external whenOwnershipIsTransferredByTheOwner {
        // it should revert with an ownership error
        vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, deployer));
        oldTreasury.withdraw(1 ether);  // Old owner cannot withdraw
    }
}
