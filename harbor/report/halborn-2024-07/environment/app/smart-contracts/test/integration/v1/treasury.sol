pragma solidity 0.8.21;

import {Treasury} from "../../../src/v1/Treasury.sol";
import {ITreasury} from "../../../src/v1/interfaces/ITreasury.sol";
import "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import "openzeppelin-contracts-upgradeable/contracts/utils/PausableUpgradeable.sol";
import "openzeppelin-foundry-upgrades/Upgrades.sol";
import {MockTreasury} from "./mockTreasury.sol";
import "forge-std/Test.sol";

contract TreasuryIntegrationTest is Test {
    using Upgrades for address;

    // Proxy to treasury
    Treasury private treasuryProxy;

    uint256 private initialBalance = 10 ether;
    address payable private constant etherBridgeAddress = payable(address(0xB));

    function upgradeProxyPublic(address proxy, string memory contractName, bytes memory data) public {
        return Upgrades.upgradeProxy(proxy, contractName, data);
    }

    function setUp() public {
        // Parameters for deployment
        string memory contractName = "Treasury.sol:Treasury";
        bytes memory initData = abi.encodeWithSelector(Treasury.initialize.selector, address(this), etherBridgeAddress);

        // Deploy the UUPS proxy using the OpenZeppelin foundry-upgrades library
        address proxyAddress = Upgrades.deployUUPSProxy(contractName, initData);

        // Cast the proxy address to the Treasury interface
        treasuryProxy = Treasury(payable(proxyAddress));

        // Provide some initial balance to the contract for testing
        vm.deal(address(treasuryProxy), initialBalance);
    }

    // Upgrade Tests
    function test_Treasury_DeploymentOfMockTreasury() public {
        // Attempt to deploy using the internal function directly to check for errors
        address deployedAddress = Upgrades.deployUUPSProxy("mockTreasury.sol:MockTreasury", "");
        assert(deployedAddress != address(0));
    }

    function test_Treasury_UpgradeToMockTreasury() public {
        address oldImplAddress = Upgrades.getImplementationAddress(address(treasuryProxy));

        // Perform the upgrade
        upgradeProxyPublic(address(treasuryProxy), "mockTreasury.sol:MockTreasury", "");

        // Ensure the proxy is pointing to a MockTreasury contract
        MockTreasury v2 = MockTreasury(payable(address(treasuryProxy)));
        assertEq(v2.V2_CONSTANT(), 1337);
        assertEq(v2.someFunction(), 5);

        // Check that impl address is changed
        address newImplAddress = Upgrades.getImplementationAddress(address(treasuryProxy));
        assertNotEq(oldImplAddress, newImplAddress);
    }
}
