/// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import { CanonicalBridge } from "../CanonicalBridge.sol";
import { ITreasury } from "../interfaces/ITreasury.sol";
import { UUPSUpgradeable } from "openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { Ownable2StepUpgradeable } from "openzeppelin-contracts-upgradeable/contracts/access/Ownable2StepUpgradeable.sol";
import { PausableUpgradeable } from "openzeppelin-contracts-upgradeable/contracts/utils/PausableUpgradeable.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";

contract Upgrader0to1 is AccessControl {
    using Address for address;
    address public constant NULL_ADDRESS = address(0);
    bytes32 public constant DEPOSITOR_ROLE = keccak256("Depositor");
    bytes32 public constant WITHDRAW_AUTHORITY_ROLE = keccak256("WithdrawalAuthority");
    bytes32 public constant WITHDRAW_CANCELLER_ROLE = keccak256("WithdrawalCanceller");
    bytes32 public constant FRAUD_WINDOW_SETTER_ROLE = keccak256("FraudWindowSetter");
    bytes32 public constant PAUSER_ROLE = keccak256("Pauser");
    bytes32 public constant STARTER_ROLE = keccak256("Starter");
    bytes32 public constant UPGRADER_ROLE = keccak256("Upgrader");
    bytes32 public constant EMERGENCY_ROLE = keccak256("Emergency");

    address treasuryOldOwner;

    struct UpgradeParams {
        address treasuryProxy;
        address newTreasuryImplementation;
        address treasuryAdmin;
        address bridgeAdmin;
        address trustedRelayer;
        address bridgeTroll;
        address oldEtherbridgeAddress;
    }

    event UpgradeComplete (
        address treasuryProxy,
        address newTreasuryImplementation,
        address treasuryAdmin,
        address bridgeAdmin,
        address trustedRelayer,
        address bridgeTroll,
        address oldEtherBridgeProxyAddress,
        address newCanonicalBridge
    );

    error NullAddress();
    error NotContract(address a);
    error UpgraderDoesNotOwnTreasury();
    error Unpaused(address proxy);
    error ExpectedRoleNotAssigned(address contract_, bytes32 role, address user);
    error BridgeTreasuryConfigError(address actual, address expected);

    modifier validAddress (address a) {
        _checkAddress(a);
        _;
    }

    modifier isContract (address c) {
        _checkAddress(c);
        _checkContract(c);
        _;
    }

    modifier onlyUpgrader {
        _checkRole(UPGRADER_ROLE, msg.sender);
        _;
    }

    constructor () {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(UPGRADER_ROLE, msg.sender);
    }

    // This contract must obtain ownership of the Treasury before this function is called.
    // This is because an anon user is not allowed to upgrade the treasury. The old Treasury uses 2StepOwnable, so this
    // will "accept" ownership.
    // The Treasury must be paused before commencing the upgrade.
    // 
    // Multisig wallets:
    //
    // 1. Pause the Treasury and the bridge.
    // 2. Treasury.transferOwnership(this)
    // 3. this.executeUpgrade(params)

    function executeUpgrade(
        UpgradeParams calldata p
    )
        external
        isContract(p.treasuryProxy)
        isContract(p.newTreasuryImplementation)
        isContract(p.oldEtherbridgeAddress)
        validAddress(p.treasuryAdmin)
        validAddress(p.trustedRelayer)
        validAddress(p.bridgeTroll)
        onlyUpgrader
        returns (address newCanonicalBridge)
    {
        // Check permission before we start.
        checkTreasuryOwnership(p.treasuryProxy);

        // Ensure Treasury and Etherbridge are paused before we start.
        checkPaused(p.treasuryProxy);
        checkPaused(p.oldEtherbridgeAddress);

        // Accept Treasury ownership
        treasuryOldOwner = Ownable2StepUpgradeable(p.treasuryProxy).owner();
        Ownable2StepUpgradeable(p.treasuryProxy).acceptOwnership();

        // Execute treasury upgrade. This contract gets admin roles because it is the present owner.
        UUPSUpgradeable(p.treasuryProxy).upgradeToAndCall(
            address(p.newTreasuryImplementation),
            abi.encodeWithSelector(ITreasury.reinitialize.selector)
        );

        // Deploy CanonicalBridge. This contract gets admin roles.
        newCanonicalBridge = address(
            new CanonicalBridge(
                address(this), 
                p.treasuryProxy
            )
        );

        // Give msg.sender DEFAULT_ADMIN_ROLE for safety. REVOKE manually if caller is not an authoritative multisig.
        AccessControl(p.treasuryProxy).grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        AccessControl(newCanonicalBridge).grantRole(DEFAULT_ADMIN_ROLE, msg.sender);

        // Establish internal trust between the contracts.
        AccessControl(p.treasuryProxy).grantRole(DEPOSITOR_ROLE, newCanonicalBridge);
        AccessControl(p.treasuryProxy).grantRole(WITHDRAW_AUTHORITY_ROLE, newCanonicalBridge);

        // Assign Bridge admin roles as requested.
        AccessControl(newCanonicalBridge).grantRole(DEFAULT_ADMIN_ROLE, p.bridgeAdmin);
        AccessControl(newCanonicalBridge).grantRole(PAUSER_ROLE, p.bridgeAdmin);
        AccessControl(newCanonicalBridge).grantRole(STARTER_ROLE, p.bridgeAdmin);
        AccessControl(newCanonicalBridge).grantRole(WITHDRAW_AUTHORITY_ROLE, p.bridgeAdmin);
        AccessControl(newCanonicalBridge).grantRole(WITHDRAW_CANCELLER_ROLE, p.bridgeAdmin);
        AccessControl(newCanonicalBridge).grantRole(FRAUD_WINDOW_SETTER_ROLE, p.bridgeAdmin);

        // Assign Treasury admin roles as requested.
        AccessControl(p.treasuryProxy).grantRole(DEFAULT_ADMIN_ROLE, p.treasuryAdmin);
        AccessControl(p.treasuryProxy).grantRole(PAUSER_ROLE, p.treasuryAdmin);
        AccessControl(p.treasuryProxy).grantRole(STARTER_ROLE, p.treasuryAdmin);
        AccessControl(p.treasuryProxy).grantRole(UPGRADER_ROLE, p.treasuryAdmin);
        AccessControl(p.treasuryProxy).grantRole(EMERGENCY_ROLE, p.treasuryAdmin);

        // Assign BridgeTroll roles as requested.
        AccessControl(newCanonicalBridge).grantRole(WITHDRAW_CANCELLER_ROLE, p.bridgeTroll);
        AccessControl(newCanonicalBridge).grantRole(PAUSER_ROLE, p.bridgeTroll);

        // Assign Relayer roles as requested.
        AccessControl(newCanonicalBridge).grantRole(WITHDRAW_AUTHORITY_ROLE, p.trustedRelayer);

        // During reinitialization, this contract received roles. Revoke this contract's authority.
        AccessControl(p.treasuryProxy).revokeRole(DEFAULT_ADMIN_ROLE, address(this));
        AccessControl(newCanonicalBridge).revokeRole(PAUSER_ROLE, address(this));
        AccessControl(newCanonicalBridge).revokeRole(STARTER_ROLE, address(this));
        AccessControl(newCanonicalBridge).revokeRole(WITHDRAW_AUTHORITY_ROLE, address(this));
        AccessControl(newCanonicalBridge).revokeRole(WITHDRAW_CANCELLER_ROLE, address(this));
        AccessControl(newCanonicalBridge).revokeRole(FRAUD_WINDOW_SETTER_ROLE, address(this));
        AccessControl(newCanonicalBridge).revokeRole(DEFAULT_ADMIN_ROLE, address(this));
        
        // CanonicalBridge agress with the treasury proxy address.
        if (CanonicalBridge(newCanonicalBridge).TREASURY() != p.treasuryProxy) {
            revert BridgeTreasuryConfigError(CanonicalBridge(newCanonicalBridge).TREASURY(), p.treasuryProxy);
        }

        // Check that caller received ACL role in all three contracts.
        confirmRole(p.treasuryProxy, DEFAULT_ADMIN_ROLE, msg.sender);
        confirmRole(newCanonicalBridge, DEFAULT_ADMIN_ROLE, msg.sender);

        // Check that internal trusts are established.
        confirmRole(p.treasuryProxy, DEPOSITOR_ROLE, newCanonicalBridge);
        confirmRole(p.treasuryProxy, WITHDRAW_AUTHORITY_ROLE, newCanonicalBridge);

        // Check that the bridge admin received Bridge ACL and admin roles.
        confirmRole(newCanonicalBridge, DEFAULT_ADMIN_ROLE, p.bridgeAdmin);
        confirmRole(newCanonicalBridge, PAUSER_ROLE, p.bridgeAdmin);
        confirmRole(newCanonicalBridge, STARTER_ROLE, p.bridgeAdmin);
        confirmRole(newCanonicalBridge, WITHDRAW_AUTHORITY_ROLE, p.bridgeAdmin);
        confirmRole(newCanonicalBridge, WITHDRAW_CANCELLER_ROLE, p.bridgeAdmin);
        confirmRole(newCanonicalBridge, FRAUD_WINDOW_SETTER_ROLE, p.bridgeAdmin);

        // Check that the old treasury owner received ACL and admin roles.
        confirmRole(p.treasuryProxy, DEFAULT_ADMIN_ROLE, treasuryOldOwner);
        confirmRole(p.treasuryProxy, PAUSER_ROLE, treasuryOldOwner);
        confirmRole(p.treasuryProxy, STARTER_ROLE, treasuryOldOwner);
        confirmRole(p.treasuryProxy, UPGRADER_ROLE, treasuryOldOwner);
        confirmRole(p.treasuryProxy, EMERGENCY_ROLE, treasuryOldOwner);

        // Check that the BridgeTroll received halting roles
        confirmRole(newCanonicalBridge, WITHDRAW_CANCELLER_ROLE, p.bridgeTroll);
        confirmRole(newCanonicalBridge, PAUSER_ROLE, p.bridgeTroll);

        // Check that the relayer received withdraw authority role.
        confirmRole(newCanonicalBridge, WITHDRAW_AUTHORITY_ROLE, p.trustedRelayer);

        // Emit success.
        emitter(p, newCanonicalBridge);
    }

    function confirmRole(address c, bytes32 role, address user) internal view {
        if (!AccessControl(c).hasRole(role, user)) {
            revert ExpectedRoleNotAssigned(c, role, user);
        }
    }

    /// @dev This is separate from the upgrade function so coverage reporting doesn't run out of stack depth.
    function emitter(UpgradeParams calldata p, address newCanonicalBridge) internal {
        emit UpgradeComplete(
            p.treasuryProxy,
            p.newTreasuryImplementation,
            p.treasuryAdmin,
            p.bridgeAdmin,
            p.trustedRelayer,
            p.bridgeTroll,
            p.oldEtherbridgeAddress,
            newCanonicalBridge
        );
    }

    function checkTreasuryOwnership(address treasuryProxy) public view {
        if (Ownable2StepUpgradeable(treasuryProxy).pendingOwner() != address(this)) {
            revert UpgraderDoesNotOwnTreasury();
        }
    }

    function checkPaused(address c) public view {
        if (!PausableUpgradeable(c).paused()) {
            revert Unpaused(c);
        }
    }

    function _checkAddress(address a) internal pure {
        if (a == NULL_ADDRESS) {
            revert NullAddress();
        }
    }

    function _checkContract(address c) internal view {
        if (!_isContract(c)) {
            revert NotContract(c);
        }
    }
    
    function _isContract(address c) public view returns (bool) {
        uint256 size;
        // extcodesize returns 0 for externally owned accounts (EOA) and unconstructed contract addresses.
        assembly {
            size := extcodesize(c)
        }
        return size > 0;
    }
}
