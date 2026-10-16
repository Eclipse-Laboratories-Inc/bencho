// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import { Test, console } from "../../lib/forge-std/src/Test.sol";
import { MailboxV0 } from "../../src/v0/MailboxV0.sol";
import { TreasuryV0 } from "../../src/v0/TreasuryV0.sol";
import { EtherBridgeV0 } from "../../src/v0/EtherBridgeV0.sol";

import { Treasury } from "../../src/v1/Treasury.sol";
import { CanonicalBridge } from "../../src/v1/CanonicalBridge.sol";
import { Upgrader0to1 } from "../../src/v1/upgrader/Upgrader0to1.sol";

import { Upgrades } from "../../lib/openzeppelin-foundry-upgrades/src/Upgrades.sol";
import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";
import { Ownable2StepUpgradeable } from "openzeppelin-contracts-upgradeable/contracts/access/Ownable2StepUpgradeable.sol";


contract UpgraderTest is Test {

    address public constant NULL_ADDRESS = address(0);
    bytes32 public constant DEFAULT_ADMIN_ROLE = bytes32(0);
    bytes32 public constant DEPOSITOR_ROLE = keccak256("Depositor");
    bytes32 public constant WITHDRAW_AUTHORITY_ROLE = keccak256("WithdrawalAuthority");
    bytes32 public constant WITHDRAW_CANCELLER_ROLE = keccak256("WithdrawalCanceller");
    bytes32 public constant FRAUD_WINDOW_SETTER_ROLE = keccak256("FraudWindowSetter");
    bytes32 public constant PAUSER_ROLE = keccak256("Pauser");
    bytes32 public constant STARTER_ROLE = keccak256("Starter");
    bytes32 public constant UPGRADER_ROLE = keccak256("Upgrader");
    bytes32 public constant EMERGENCY_ROLE = keccak256("Emergency");
    bytes32 public constant TRUSTED_RELAYER_ROLE = keccak256("TRUSTED_RELAYER_ROLE");
    bytes32 public constant MODULE_ROLE = keccak256("MODULE_ROLE");
    bytes32 public constant ADMIN_AUTHORITY_ROLE = keccak256("ADMIN_AUTHORITY_ROLE");
    bytes32 public constant ETHER_BRIDGE_ID = keccak256("EtherBridge");

    Treasury public treasuryV1;
    CanonicalBridge public canonicalBridgeV1;

    string private ethereumChainId = "EtherBridge";
    string private eclipseChainId = "Eclipse";

    address private deployer = makeAddr("deployer");
    address private owner = makeAddr("owner");
    address private trustedRelayerAddress = makeAddr("relayer");
    address private bridgeTrollAddress = makeAddr("troll");

    TreasuryV0 treasuryV0Impl;
    MailboxV0 mailboxV0Impl;
    EtherBridgeV0 etherBridgeV0Impl;
    Upgrader0to1 upgrader0To1;

    TreasuryV0 treasuryV0;
    MailboxV0 mailboxV0;
    EtherBridgeV0 etherBridgeV0;

    address treasuryProxyAddress;
    address mailboxProxyAddress;
    address etherBridgeProxyAddress;

    address treasuryV1ImplAddress;
    address canonicalBridgeV1Address;

    address treasuryOwner;
    uint256 treasuryBalance;

    error ExpectedRoleNotAssigned(address contract_, bytes32 role, address user);

    function setUp() external {

        treasuryV0Impl = new TreasuryV0();
        mailboxV0Impl = new MailboxV0();
        etherBridgeV0Impl = new EtherBridgeV0();

        // Deploy proxies / contracts and get deployed instances
        bytes memory emptyInitData = "";
        etherBridgeProxyAddress = Upgrades.deployUUPSProxy("EtherBridgeV0.sol:EtherBridgeV0", emptyInitData);
        treasuryProxyAddress = Upgrades.deployUUPSProxy("TreasuryV0.sol:TreasuryV0", emptyInitData);
        mailboxProxyAddress = Upgrades.deployUUPSProxy("MailboxV0.sol:MailboxV0", emptyInitData);

        etherBridgeV0 = EtherBridgeV0(etherBridgeProxyAddress);
        treasuryV0 = TreasuryV0(payable(treasuryProxyAddress));
        mailboxV0 = MailboxV0(mailboxProxyAddress);

        // Call initialization functions
        bytes32[] memory ids = new bytes32[](1);
        ids[0] = etherBridgeV0.ETHER_BRIDGE_ID();
        address[] memory modules = new address[](1);
        modules[0] = etherBridgeProxyAddress;

        MailboxV0.InitParams memory initParams = MailboxV0.InitParams({
            initialOwner: owner,
            trustedRelayer: trustedRelayerAddress,
            ids: ids,
            modules: modules,
            ethereumChainId: ethereumChainId,
            eclipseChainId: eclipseChainId
        });

        etherBridgeV0.initialize(owner, address(mailboxProxyAddress), address(treasuryProxyAddress));
        treasuryV0.initialize(owner, address(etherBridgeProxyAddress));
        mailboxV0.initialize(initParams);

        treasuryV1ImplAddress = address(new Treasury());

        canonicalBridgeV1Address = address(new CanonicalBridge(
            owner,
            treasuryProxyAddress
        ));

        // Collect information from v0
        treasuryOwner = Ownable2StepUpgradeable(treasuryProxyAddress).owner();
        treasuryBalance = treasuryProxyAddress.balance;

        // Deploy the upgrader
        upgrader0To1 = new Upgrader0to1();

        // Log configuration
        console.log("");
        console.log("------ deployer ------");
        console.log("deployer(wallet): %s", address(this));
        console.log("deployer(msg.sender): %s", msg.sender);

        console.log("");
        console.log("------ contracts ------");
        console.log("EtherBridge(address): %s", address(etherBridgeV0));
        console.log("EtherBridge(proxy): %s", address(etherBridgeProxyAddress));
        console.log("Treasury(address): %s", address(treasuryV0));
        console.log("Treasury(proxy): %s", address(treasuryProxyAddress));
        console.log("Mailbox(address): %s", address(mailboxV0));
        console.log("Mailbox(proxy): %s", address(mailboxProxyAddress));
        console.log("upgrader0To1: %s", address(upgrader0To1));

        console.log("");
        console.log("------ configs ------");
        console.log("trustedRelayerAddress: %s", trustedRelayerAddress);
        console.log("Treasury(balance): %s", treasuryProxyAddress.balance);
        console.log("owner(config): %s", owner);

        console.log("------- roles -------");
        console.log("DEFAULT_ADMIN_ROLE:");
        console.logBytes32(DEFAULT_ADMIN_ROLE);
        console.log("UPGRADER_ROLE:");
        console.logBytes32(UPGRADER_ROLE);
    }

    function test_upgrader0To1() external {

        vm.startPrank(owner);
        // The owner grants permissions to the upgrader.
        Ownable2StepUpgradeable(treasuryProxyAddress).transferOwnership(address(upgrader0To1));

        // The owner pauses the old treasury and bridge contracts.
        TreasuryV0(payable(treasuryProxyAddress)).pause();
        EtherBridgeV0(etherBridgeProxyAddress).pause();
        vm.stopPrank();

        // The upgrader deployer grants upgrader role to the multisig that will execute the upgrade.
        IAccessControl(address(upgrader0To1)).grantRole(UPGRADER_ROLE, address(this));

        // The owner asks the Upgrader0to1 to perform the upgrade. Implementations should pre-deployed. 
        Upgrader0to1.UpgradeParams memory params = Upgrader0to1.UpgradeParams({
            treasuryProxy: treasuryProxyAddress,
            newTreasuryImplementation: treasuryV1ImplAddress,
            treasuryAdmin: treasuryOwner,
            bridgeAdmin: treasuryOwner,
            trustedRelayer: trustedRelayerAddress,
            bridgeTroll: bridgeTrollAddress,
            oldEtherbridgeAddress: etherBridgeProxyAddress
        });

        canonicalBridgeV1Address = upgrader0To1.executeUpgrade(params);

        // The remainder of this test confirms successful upgrade without loss of funds or control.
        uint256 newTreasuryBalance = treasuryProxyAddress.balance;
        assertEq(
            newTreasuryBalance,
            treasuryBalance,
            "Treasury balance has changed"
        );

        address canonicalBridgeTreasuryAddress = CanonicalBridge(canonicalBridgeV1Address).TREASURY();
        assertEq(canonicalBridgeTreasuryAddress, treasuryProxyAddress, "CanonicalBridge treasury misconfigured");

        // Check that this contract received the ACL role in all three contracts.
        console.log("Check upgrade caller has default admin role");
        confirmRole(treasuryProxyAddress, DEFAULT_ADMIN_ROLE, address(this));
        confirmRole(address(canonicalBridgeV1Address), DEFAULT_ADMIN_ROLE, address(this));

        // Check that internal trusts are established.
        console.log("check internal trust roles");
        confirmRole(treasuryProxyAddress, DEPOSITOR_ROLE, address(canonicalBridgeV1Address));
        confirmRole(treasuryProxyAddress, WITHDRAW_AUTHORITY_ROLE, address(canonicalBridgeV1Address));

        // Check that the bridge admin received Bridge ACL and admin roles.
        console.log("check bridge admin received bridge ACL and admin roles");
        confirmRole(address(canonicalBridgeV1Address), DEFAULT_ADMIN_ROLE, owner);
        confirmRole(address(canonicalBridgeV1Address), PAUSER_ROLE, owner);
        confirmRole(address(canonicalBridgeV1Address), STARTER_ROLE, owner);
        confirmRole(address(canonicalBridgeV1Address), WITHDRAW_AUTHORITY_ROLE, owner);
        confirmRole(address(canonicalBridgeV1Address), WITHDRAW_CANCELLER_ROLE, owner);
        confirmRole(address(canonicalBridgeV1Address), FRAUD_WINDOW_SETTER_ROLE, owner);

        // Check that the old treasury owner received ACL and admin roles.
        console.log("check treasury owner receive treasury ACL and admin roles.");
        confirmRole(treasuryProxyAddress, DEFAULT_ADMIN_ROLE, treasuryOwner);
        confirmRole(treasuryProxyAddress, PAUSER_ROLE, treasuryOwner);
        confirmRole(treasuryProxyAddress, STARTER_ROLE, treasuryOwner);
        confirmRole(treasuryProxyAddress, UPGRADER_ROLE, treasuryOwner);
        confirmRole(treasuryProxyAddress, EMERGENCY_ROLE, treasuryOwner);

        // Check that the BridgeTroll received halting roles
        console.log("check bridge troll received halting roles.");
        confirmRole(address(canonicalBridgeV1Address), WITHDRAW_CANCELLER_ROLE, bridgeTrollAddress);
        confirmRole(address(canonicalBridgeV1Address), PAUSER_ROLE, bridgeTrollAddress);

        // Check that the relayer received withdraw authority role.
        confirmRole(address(canonicalBridgeV1Address), WITHDRAW_AUTHORITY_ROLE, trustedRelayerAddress);
    }

    function confirmRole(address c, bytes32 role, address user) internal view {
        if (!IAccessControl(c).hasRole(role, user)) {
            revert ExpectedRoleNotAssigned(c, role, user);
        }
    }


}
