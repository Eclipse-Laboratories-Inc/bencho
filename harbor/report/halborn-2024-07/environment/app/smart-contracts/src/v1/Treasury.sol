pragma solidity 0.8.21;

import "openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import "openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/contracts/access/Ownable2StepUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/contracts/utils/ReentrancyGuardUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/contracts/utils/PausableUpgradeable.sol";

import "./interfaces/ITreasury.sol";
import "./CommonContainer.sol";

/// @title Treasury
/// @dev Stores ether from the ether bridge or the owner and allows for emergency withdrawals by the owner.
contract Treasury is
    ITreasury,
    CommonContainer,
    Initializable,
    Ownable2StepUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable,
    UUPSUpgradeable
{
    /// @custom:storage-location erc7201:eclipse.treasury.v1
    struct StorageV1 {
        address etherBridgeAddress;
    }

    // keccak256(abi.encode(uint256(keccak256("eclipse.treasury.v1")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant STORAGE_V1_LOCATION = 0x81159cb40e73093d0d223f2fb64aaf85cf8f1e0b1fd69939c1101cbd5855c900;

    function _getStorageV1() internal pure returns (StorageV1 storage $) {
        assembly {
            $.slot := STORAGE_V1_LOCATION
        }
    }

    /// @dev Constructor that disables initializers
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @dev Initializes the treasury contract, entry point for initialization
    /// @param etherBridgeAddress_ The address of the ether bridge contract.
    function initialize(address owner_, address etherBridgeAddress_)
        public
        addressInitialized(owner_)
        addressInitialized(etherBridgeAddress_)
        initializer
    {
        __Ownable_init(owner_);
        __Ownable2Step_init();
        __Pausable_init();
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();

        StorageV1 storage $ = _getStorageV1();
        $.etherBridgeAddress = etherBridgeAddress_;
    }

    /// @dev Allows for emergency withdraws to owner.
    /// @param amount The amount of Ether (in wei) to withdraw.
    function emergencyWithdraw(uint256 amount) external virtual override onlyOwner nonReentrant {
        require(address(this).balance >= amount, "Insufficient funds");
        (bool success,) = msg.sender.call{value: amount}("");
        require(success, "Failed to send Ether");

        emit EmergencyTreasuryWithdraw(msg.sender, amount);
    }

    function pause() external virtual onlyOwner {
        _pause();
    }

    function unpause() external virtual onlyOwner {
        _unpause();
    }

    /// @dev Required by the OZ UUPS module
    function _authorizeUpgrade(address) internal view override onlyOwner {}

    /// @dev Function to receive Ether, marked as virtual for future override
    receive() external payable virtual whenNotPaused {
        StorageV1 storage $ = _getStorageV1();
        require(msg.sender == $.etherBridgeAddress || msg.sender == owner(), "Unauthorized source");
        emit TreasuryDeposit(msg.sender, msg.value);
    }
}
