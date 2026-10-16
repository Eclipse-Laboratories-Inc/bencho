// SPDX-License-Identifier: UNLICENSED 
pragma solidity 0.8.21;

import { Initializable } from "openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import { UUPSUpgradeable } from "openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import { AccessControlUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from 
    "openzeppelin-contracts-upgradeable/contracts/utils/ReentrancyGuardUpgradeable.sol";
import { PausableUpgradeable } from "openzeppelin-contracts-upgradeable/contracts/utils/PausableUpgradeable.sol";
import { ITreasury } from "./interfaces/ITreasury.sol";
import { ISemVer } from "./interfaces/ISemVer.sol";

/// @title Treasury
/// @dev Stores ether from the ether bridge or the owner and allows for emergency withdrawals by the owner.
contract Treasury is
    ITreasury,
    ISemVer,
    Initializable,
    AccessControlUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable,
    UUPSUpgradeable
{
    struct OwnableStorage {
        address _owner;
    }

    address private constant NULL_ADDRESS = address(0);
    uint8 private constant MAJOR_VERSION = 2;
    uint8 private constant MINOR_VERSION = 0;
    uint8 private constant PATCH_VERSION = 0;

    bytes32 public constant override DEPOSITOR_ROLE = keccak256("Depositor");
    bytes32 public constant override WITHDRAW_AUTHORITY_ROLE = keccak256("WithdrawalAuthority");
    bytes32 public constant override PAUSER_ROLE = keccak256("Pauser");
    bytes32 public constant override STARTER_ROLE = keccak256("Starter");
    bytes32 public constant override UPGRADER_ROLE = keccak256("Upgrader");
    bytes32 public constant override EMERGENCY_ROLE = keccak256("Emergency");

    /// @custom:storage-location erc7201:eclipse.treasury.v1
    struct StorageV1 {
        address etherBridgeAddress;
    }

    // keccak256(abi.encode(uint256(keccak256("openzeppelin.storage.Ownable")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant OWNABLE_STORAGE_LOCATION = 0x9016d09d72d40fdae2fd8ceac6b6234c7706214fd39c1cd1e609a0528c199300;

    /// @dev Ensures that address is non-zero.
    modifier addressInitialized(address _address) {
        if (_address == NULL_ADDRESS) revert ZeroAddress();
        _;
    }

    /// @dev ERC7201 storage with access to previous owner.
    function _getOwnableStorage() private pure returns (OwnableStorage storage $) {
        assembly {
            $.slot := OWNABLE_STORAGE_LOCATION
        }
    }

    /// @dev Constructor that disables initializers
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Converts the Ownable.owner to a privileged user in AccessControl.
    /// @dev The EtherBridge address must be granted the DEPOSITOR_ROLE and WITHDRAW_AUTHORITY_ROLE
    /// post-initialization to be trusted by this contract. By default, no one can deposit or withdraw.
    /// @inheritdoc ITreasury
    function reinitialize()
        external
        virtual
        override
        reinitializer(2)
    {
        address oldOwner = _getOwnableStorage()._owner;
        if (oldOwner == NULL_ADDRESS) {
            revert InvalidInitialization();
        }
        emit TreasuryReinitialized(msg.sender, oldOwner);
        // oldOwner receives user admin role for the operational roles.
        _grantRole(DEFAULT_ADMIN_ROLE, oldOwner);
        // oldOwner receives operational roles.
        _grantRole(PAUSER_ROLE, oldOwner);
        _grantRole(STARTER_ROLE, oldOwner);
        _grantRole(UPGRADER_ROLE, oldOwner);
        _grantRole(EMERGENCY_ROLE, oldOwner);
        // deployer receives user admin role.
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    /// @inheritdoc ISemVer
    function getVersionComponents() public pure virtual override returns (Version memory) {
        return Version(MAJOR_VERSION, MINOR_VERSION, PATCH_VERSION);
    }

    /// @inheritdoc ITreasury
    /// @dev Access controlled, pausible
    function depositEth() external payable virtual override whenNotPaused onlyRole(DEPOSITOR_ROLE) {
        emit TreasuryDeposit(msg.sender, msg.value);
    }

    /// @inheritdoc ITreasury
    /// @dev Access controlled, pausible
    function withdrawEth(
        address to, 
        uint256 amountWei,
        address feeReceiver,
        uint256 feeWei
    ) 
        external
        nonReentrant
        whenNotPaused
        addressInitialized(to)
        addressInitialized(feeReceiver)
        onlyRole(WITHDRAW_AUTHORITY_ROLE)
        returns (bool success) 
    {
        uint256 totalAmount = amountWei + feeWei;
        if (address(this).balance < totalAmount) {
            revert InsufficientFunds();
        }
        (success,) = payable(to).call{value: amountWei - feeWei}("");
        if (!success) revert TreasuryTransferFailed();
        (success,) = payable(feeReceiver).call{value: feeWei}("");
        if (!success) revert TreasuryTransferFailed();
        emit TreasuryWithdrawal(msg.sender, to, amountWei, feeReceiver, feeWei);
    }

    /// @inheritdoc ITreasury
    /// @dev Access controlled.
    function emergencyWithdraw(
        uint256 amount
    ) 
        external
        virtual 
        override 
        onlyRole(EMERGENCY_ROLE)
    {
        if (address(this).balance < amount) revert InsufficientFunds(); 
        (bool success,) = payable(msg.sender).call{value: amount}("");
        if (!success) revert TreasuryTransferFailed(); 
        emit EmergencyTreasuryWithdraw(msg.sender, amount);
    }

    /// @notice Pauses deposits and withdrawals.
    /// @dev Access controlled.
    function pause() external virtual override onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /// @notice Resumes deposits and withdrawals.
    /// @dev Access controlled.
    function unpause() external virtual override onlyRole(STARTER_ROLE) {
        _unpause();
    }

    /// @dev Required by the OZ UUPS module
    /// @dev Access controlled.
    function _authorizeUpgrade(address) internal view virtual override onlyRole(UPGRADER_ROLE) {}
}
