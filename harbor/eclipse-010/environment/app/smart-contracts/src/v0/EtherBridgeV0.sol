// All Rights Reserved
pragma solidity 0.8.21;

import "openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import "openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/contracts/utils/ReentrancyGuardUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/contracts/utils/PausableUpgradeable.sol";

import "./interfaces/IEtherBridgeV0.sol";
import "./interfaces/ITreasuryV0.sol";
import "./interfaces/IMailboxV0.sol";
import "./interfaces/ISemVerV0.sol";
import "./CommonContainerV0.sol";

/// @title EtherBridge
/// @dev A bridge contract for depositing and withdrawing ether to and from the Eclipse rollup.
contract EtherBridgeV0 is
    IEtherBridgeV0,
    ISemVerV0,
    CommonContainerV0,
    Initializable,
    AccessControlUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable,
    UUPSUpgradeable
{
    bytes32 public constant ETHER_BRIDGE_ID = keccak256("EtherBridge");

    uint256 public constant MIN_DEPOSIT = MIN_DEPOSIT_LAMPORTS * WEI_PER_LAMPORT;
    uint256 private constant MIN_DEPOSIT_LAMPORTS = 2_000_000;
    uint256 private constant WEI_PER_LAMPORT = 1_000_000_000;

    uint8 private constant MAJOR_VERSION = 1;
    uint8 private constant MINOR_VERSION = 0;
    uint8 private constant PATCH_VERSION = 0;

    /// @custom:storage-location erc7201:eclipse.ether_bridge.v1
    struct StorageV1 {
        bytes etherBridgeId;
        IMailboxV0 mailboxProxy;
        ITreasuryV0 treasuryProxy;
    }

    // keccak256(abi.encode(uint256(keccak256("eclipse.ether_bridge.v1")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant STORAGE_V1_LOCATION = 0x47de546cf6a4c0310e912c3941a75f4e016a86b1301d78e45822946d7c351e00;

    function _getStorageV1() internal pure returns (StorageV1 storage $) {
        assembly {
            $.slot := STORAGE_V1_LOCATION
        }
    }

    /// @dev Ensures the deposit amount and msg.value valid & equal and they are greater then eq to min deposit amount
    /// @param amountWei The amount to be deposited.
    modifier validDepositAmount(uint256 amountWei) {
        require(msg.value == amountWei, "Deposit amount and msg.value must be equal");
        require(msg.value % WEI_PER_LAMPORT == 0, "Deposit msg.value must not have a fractional gwei value");
        require(msg.value >= MIN_DEPOSIT, "Deposit amount must be greater than equal to the minimum wei amount");
        _;
    }

    /// @dev Restricts the function call to only admins.
    modifier onlyAuthority() {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Only an admin can call this method.");
        _;
    }

    /// @dev Constructor that disables initializers
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @dev Initializes the contract variables and deploys the treasury.
    /// @param mailboxAddress_ Address of the mailbox contract.
    /// @param treasuryAddress_ Address of the treasury contract.
    function initialize(address owner_, address mailboxAddress_, address treasuryAddress_)
        public
        addressInitialized(owner_)
        addressInitialized(mailboxAddress_)
        addressInitialized(treasuryAddress_)
        initializer
    {
        __AccessControl_init();
        __Pausable_init();
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, owner_);

        StorageV1 storage $ = _getStorageV1();
        $.mailboxProxy = IMailboxV0(mailboxAddress_);
        $.treasuryProxy = ITreasuryV0(treasuryAddress_);
        $.etherBridgeId = abi.encode(ETHER_BRIDGE_ID);
    }

    /// @dev Retrieves the constant version details of the smart contract.
    function getVersionComponents() public pure override returns (Version memory) {
        return Version(MAJOR_VERSION, MINOR_VERSION, PATCH_VERSION);
    }

    /// @notice Deposit amount and a fee after deductions into treasury
    function deposit(bytes32 recipient, uint256 amountWei)
        external
        payable
        virtual
        override
        whenNotPaused
        bytes32Initialized(recipient)
        validDepositAmount(amountWei)
        nonReentrant
    {
        StorageV1 storage $ = _getStorageV1();

        // Create deposit message with amount in gwei
        uint256 amountGwei = amountWei / WEI_PER_LAMPORT;
        IEtherBridgeV0.DepositMessage memory message =
            IEtherBridgeV0.DepositMessage({sender: msg.sender, recipient: recipient, amountGwei: amountGwei});

        // Encode message and forward to mailbox
        bytes memory encodedMessage = abi.encode(message);
        bool success = $.mailboxProxy.sendMessage("", $.etherBridgeId, encodedMessage, "");
        require(success, "Unable to forward deposit message to Mailbox");

        // Lock funds in the treasury
        (success,) = payable(address($.treasuryProxy)).call{value: amountWei}("");
        require(success, "Transfer failed");
        emit Deposited(msg.sender, recipient, amountWei);
    }

    /// @dev Pause deposits
    function pause() external virtual onlyAuthority {
        _pause();
    }

    /// @dev Unpause deposits
    function unpause() external virtual onlyAuthority {
        _unpause();
    }

    /// @dev required by the OZ UUPS module
    function _authorizeUpgrade(address) internal virtual override onlyAuthority {}
}
