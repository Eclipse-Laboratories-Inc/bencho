// All Rights Reserved
pragma solidity 0.8.21;

import "openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import "openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/contracts/utils/ReentrancyGuardUpgradeable.sol";

import "./interfaces/IMailboxV0.sol";
import "./CommonContainerV0.sol";
import "./interfaces/ISemVerV0.sol";

/// @title Mailbox
/// @dev Allows certain contracts to send and receive messages between Ethereum and Eclipse using a trusted relayer.
contract MailboxV0 is
    IMailboxV0,
    ISemVerV0,
    CommonContainerV0,
    Initializable,
    AccessControlUpgradeable,
    ReentrancyGuardUpgradeable,
    UUPSUpgradeable
{
    bytes32 public constant TRUSTED_RELAYER_ROLE = keccak256("TRUSTED_RELAYER_ROLE");
    bytes32 public constant MODULE_ROLE = keccak256("MODULE_ROLE");

    uint8 private constant MAJOR_VERSION = 1;
    uint8 private constant MINOR_VERSION = 0;
    uint8 private constant PATCH_VERSION = 0;

    // @dev Messages received from Eclipse include a security param which decodes into this structure.
    // @param nonce is random number used only once for a message which is received.
    struct EclipseSecurityParam {
        uint64 nonce;
    }

    // @dev Messages sent from Ethereum include a security param which is encoded using this structure.
    // @param nonce is random number used only once for sending a message.
    struct EthereumSecurityParam {
        uint64 nonce;
    }

    // @dev The params passed into initializer (useful for avoiding stack too deep issues)
    /// @param trustedRelayer_ The address of the trusted relayer.
    /// @param ids_ Module identifiers (hash of contract name) that can send messages through this mailbox.
    /// @param modules_ The addresses of the contracts that can send messages through this mailbox.
    /// @param ethereumChainId_ The chainId for this Ethereum chain.
    /// @param eclipseChainId_ The chainId for the Eclipse chain.
    struct InitParams {
        address initialOwner;
        address trustedRelayer;
        bytes32[] ids;
        address[] modules;
        string ethereumChainId;
        string eclipseChainId;
    }

    /// @custom:storage-location erc7201:eclipse.mailbox.v1
    struct StorageV1 {
        uint256 lastNonce;
        bytes32 ethereumChainId;
        bytes32 eclipseChainId;
        mapping(bytes32 => address) modulesById;
        mapping(uint64 => bool) receiveNonces;
        mapping(uint64 => bool) sendNonces;
    }

    // keccak256(abi.encode(uint256(keccak256("eclipse.mailbox.v1")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant STORAGE_V1_LOCATION = 0x8455de2eaf4bdcf2bc20fa04052c8c0cac25abccf9eccf721a14442c18547600;

    function _getStorageV1() internal pure returns (StorageV1 storage $) {
        assembly {
            $.slot := STORAGE_V1_LOCATION
        }
    }

    /// @dev Validates the chainId corresponds to the Ethereum chain.
    modifier ethereumChainIdValid(bytes memory chainId_) {
        require(decodeChainId(chainId_) == _getStorageV1().ethereumChainId, "Unsupported Ethereum chain id.");
        _;
    }

    /// @dev Validates the chainId corresponds to the Eclipse chain.
    modifier eclipseChainIdValid(bytes memory chainId_) {
        require(decodeChainId(chainId_) == _getStorageV1().eclipseChainId, "Unsupported Eclipse chain id.");
        _;
    }

    /// @dev Restricts the function call to only the trusted relayer.
    modifier onlyTrustedRelayer() {
        require(hasRole(TRUSTED_RELAYER_ROLE, msg.sender), "Only the trusted relayer can call this method.");
        _;
    }

    /// @dev Restricts the function call to only recognized modules.
    modifier onlyModule() {
        require(hasRole(MODULE_ROLE, msg.sender), "Only an authorized module can call this method.");
        _;
    }

    /// @dev Restricts the function call to only admins.
    modifier onlyAuthority() {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Only an admin can call this method.");
        _;
    }

    /// @dev Validates the length of module ids array and modules array
    modifier validateModuleArrays(bytes32[] calldata ids_, address[] calldata modules_) {
        require(ids_.length != 0, "Module identifiers must be initialized");
        require(modules_.length != 0, "Module addresses must be initialized");
        require(ids_.length == modules_.length, "Module identifiers and addresses must have same length");
        _;
    }

    /// @dev Constructor that disables initializers
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @dev Initializes the mailbox contract
    /// @param params the variable which contains all the fields needed to init
    function initialize(InitParams calldata params)
        public
        addressInitialized(params.initialOwner)
        addressInitialized(params.trustedRelayer)
        addressArrayInitialized(params.modules)
        bytes32ArrayInitialized(params.ids)
        bytesInitialized(bytes(params.ethereumChainId))
        bytesInitialized(bytes(params.eclipseChainId))
        initializer
    {
        require(params.ids.length == params.modules.length, "Module ids and addresses must have equal length");

        __AccessControl_init();
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();

        // Grant roles and update modules by id
        StorageV1 storage $ = _getStorageV1();
        _grantRole(DEFAULT_ADMIN_ROLE, params.initialOwner);
        _grantRole(TRUSTED_RELAYER_ROLE, params.trustedRelayer);

        for (uint256 i = 0; i < params.modules.length; i++) {
            bytes32 id = params.ids[i];
            address module = params.modules[i];
            _grantRole(MODULE_ROLE, module);
            $.modulesById[id] = module;
        }

        // Store chain ids and initial nonce seed
        $.ethereumChainId = generateChainId(params.ethereumChainId);
        $.eclipseChainId = generateChainId(params.eclipseChainId);
        $.lastNonce = generateRandomNonce();
    }

    /// @dev Retrieves the constant version details of the smart contract.
    function getVersionComponents() public pure override returns (Version memory) {
        return Version(MAJOR_VERSION, MINOR_VERSION, PATCH_VERSION);
    }

    /// @dev (NOT UNIT TESTED) Add module address by id and grant module role to that address
    function addModule(bytes32 moduleId, address module)
        external
        bytes32Initialized(moduleId)
        addressInitialized(module)
        onlyAuthority
    {
        StorageV1 storage $ = _getStorageV1();
        if ($.modulesById[moduleId] != address(0)) {
            revert("Module address for module id already set");
        }

        $.modulesById[moduleId] = module;
        _grantRole(MODULE_ROLE, module);
    }

    /// @dev (NOT UNIT TESTED) Remove module address by id and revoke module role for that address
    function removeModule(bytes32 moduleId, address module)
        external
        bytes32Initialized(moduleId)
        addressInitialized(module)
        onlyAuthority
    {
        StorageV1 storage $ = _getStorageV1();
        if ($.modulesById[moduleId] == address(0)) {
            revert("Module address for module id not yet set");
        }

        if ($.modulesById[moduleId] != module) {
            revert("Module address for module id does not match provided module address to remove/revoke");
        }

        delete $.modulesById[moduleId];
        _revokeRole(MODULE_ROLE, module);
    }

    /// @dev Receives messages from eclipse and send them to a specific module for processing.
    function receiveMessage(
        bytes memory eclipseChainId_,
        bytes memory sender_,
        bytes memory message_,
        bytes memory data_
    )
        external
        payable
        virtual
        override
        onlyTrustedRelayer
        bytesLengthEq32(eclipseChainId_)
        eclipseChainIdValid(eclipseChainId_)
        bytesInitialized(sender_)
        bytesInitialized(message_)
        bytesInitialized(data_)
        nonReentrant
        returns (bool)
    {
        // Validate and store the security param nonce
        StorageV1 storage $ = _getStorageV1();
        EclipseSecurityParam memory secParam = abi.decode(data_, (EclipseSecurityParam));
        require($.receiveNonces[secParam.nonce] == false, "Message with this nonce already received.");
        $.receiveNonces[secParam.nonce] = true;

        // Send the message to the module
        address module = $.modulesById[bytes32(sender_)];
        require(module != address(0), "Module does not exist.");
        (bool success,) = module.call(message_);
        require(success, "External call to module failed.");

        // Emit the message received event
        emit MessageReceived(sender_, eclipseChainId_, message_, data_);

        return true;
    }

    /// @dev Modules call this method to send messages out to Eclipse.
    function sendMessage(bytes memory, bytes memory receiver_, bytes memory message_, bytes memory)
        external
        payable
        virtual
        override
        onlyModule
        nonReentrant
        returns (bool)
    {
        // Create and set nonce
        StorageV1 storage $ = _getStorageV1();
        uint64 outboundNonce = generateRandomNonce();
        if ($.sendNonces[outboundNonce] == true) {
            revert("Nonce collision");
        }
        $.sendNonces[outboundNonce] = true;

        // Create security param
        bytes memory param = abi.encode(EthereumSecurityParam({nonce: outboundNonce}));
        emit MessageSent(receiver_, encodeChainId($.eclipseChainId), message_, param);

        return true;
    }

    /// @dev required by the OZ UUPS module
    function _authorizeUpgrade(address) internal virtual override onlyAuthority {}

    /// @dev Generates a pseudo-random nonce based on block properties and chained state.
    /// This function combines previous nonce state with the hash of the last block,
    /// current block timestamp, and block difficulty to produce a new nonce that is
    /// resistant to manipulation and harder to predict in advance given the params solidity supports.
    /// @return Returns a 64-bit nonce generated from various entropy sources.
    function generateRandomNonce() internal returns (uint64) {
        StorageV1 storage $ = _getStorageV1();
        // Combine unpredictable block properties with the last nonce to generate a new nonce.
        $.lastNonce = uint256(
            keccak256(abi.encodePacked($.lastNonce, blockhash(block.number - 1), block.timestamp, block.coinbase))
        );
        return uint64($.lastNonce); // Return the least significant 64 bits
    }
}
