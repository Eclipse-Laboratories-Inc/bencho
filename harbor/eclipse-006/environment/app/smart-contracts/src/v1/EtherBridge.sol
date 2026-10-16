pragma solidity 0.8.21;

import "openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import "openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/contracts/utils/ReentrancyGuardUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/contracts/utils/PausableUpgradeable.sol";

import "./interfaces/IEtherBridge.sol";
import "./interfaces/ITreasury.sol";
import "./interfaces/IMailbox.sol";
import "./CommonContainer.sol";

/// @title EtherBridge
/// @dev A bridge contract for depositing and withdrawing ether to and from the Eclipse rollup.
contract EtherBridge is
    IEtherBridge,
    CommonContainer,
    Initializable,
    AccessControlUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable,
    UUPSUpgradeable
{
    bytes32 public constant ETHER_BRIDGE_ID = keccak256("EtherBridge");

    /// @dev Calculation of constants for minimum deposit requirements.
    /// `MIN_DEPOSIT_LAMPORTS` ensures deposit data on Solar Eclipse is rent-exempt, based on:
    /// - `get_minimum_balance_for_rent_exemption` in Solar Eclipse for exemption calculations.
    /// - `Rent.minimum_balance(data_len)` formula from `/sdk/program/src/rent.rs` in Solar Eclipse:
    ///   `lamports_per_byte_year * data_len * exemption_threshold`.ceil()
    /// Constants:
    /// - `LAMPORTS_PER_YEAR`: Lamports charged per byte per year.
    /// - `EXEMPTION_THRESHOLD`: Set to 2, aligns with Solar Eclipse's threshold.
    /// - `DEPOSIT_RECEIPT_DATA_LEN`: Byte length of deposit receipts, detailed in
    ///   `eclipse-programs/blob/main/programs/canonical_bridge/src/state.rs`.
    /// - `MIN_DEPOSIT_LAMPORTS`: Product of the above constants.
    /// - `WEI_PER_LAMPORT`: Conversion rate from wei to lamports.
    /// These constants ensure deposit amounts meet Solar Eclipse's rent-exemption criteria, adapted for Ethereum's context.
    uint256 public constant MIN_DEPOSIT = MIN_DEPOSIT_LAMPORTS * WEI_PER_LAMPORT;
    uint256 private constant LAMPORTS_PER_YEAR = 3_480;
    uint256 private constant EXEMPTION_THRESHOLD = 2;
    uint256 private constant DEPOSIT_RECEIPT_DATA_LEN = 8 + 32 + 8 + 1;
    uint256 private constant MIN_DEPOSIT_LAMPORTS = (LAMPORTS_PER_YEAR * EXEMPTION_THRESHOLD * DEPOSIT_RECEIPT_DATA_LEN);
    uint256 private constant WEI_PER_LAMPORT = 1_000_000_000;

    /// @custom:storage-location erc7201:eclipse.ether_bridge.v1
    struct StorageV1 {
        bytes etherBridgeId;
        IMailbox mailboxProxy;
        ITreasury treasuryProxy;
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

    /// @dev Initializes the contract variables and deploys the treasury.
    /// @param mailboxAddress_ Address of the mailbox contract.
    /// @param treasuryAddress_ Address of the treasury contract.
    function initialize(address mailboxAddress_, address treasuryAddress_)
        public
        addressInitialized(mailboxAddress_)
        addressInitialized(treasuryAddress_)
        initializer
    {
        __AccessControl_init();
        __Pausable_init();
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);

        StorageV1 storage $ = _getStorageV1();
        $.mailboxProxy = IMailbox(mailboxAddress_);
        $.treasuryProxy = ITreasury(treasuryAddress_);
        $.etherBridgeId = abi.encode(ETHER_BRIDGE_ID);
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
        IEtherBridge.DepositMessage memory message =
            IEtherBridge.DepositMessage({sender: msg.sender, recipient: recipient, amountGwei: amountGwei});

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
    function _authorizeUpgrade(address) internal override onlyAuthority {}
}
