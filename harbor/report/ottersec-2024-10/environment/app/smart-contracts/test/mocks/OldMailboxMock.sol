// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import "openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import "openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/contracts/utils/ReentrancyGuardUpgradeable.sol";

/// @title Enhanced Mailbox Mock Contract
/// @dev Allows certain contracts to send and receive messages between Ethereum and Eclipse using a trusted relayer.
/// @notice This contract includes additional view functions to inspect the entire state.
contract OldMailboxMock is
    Initializable,
    AccessControlUpgradeable,
    ReentrancyGuardUpgradeable,
    UUPSUpgradeable
{
    bytes32 public constant TRUSTED_RELAYER_ROLE = keccak256("TRUSTED_RELAYER_ROLE");
    bytes32 public constant MODULE_ROLE = keccak256("MODULE_ROLE");
    bytes32 public constant ADMIN_AUTHORITY_ROLE = keccak256("ADMIN_AUTHORITY_ROLE");

    uint8 private constant MAJOR_VERSION = 1;
    uint8 private constant MINOR_VERSION = 0;
    uint8 private constant PATCH_VERSION = 0;

    /// @dev The params passed into initializer (useful for avoiding stack too deep issues)
    /// @param initialOwner The address of the initial owner with admin rights.
    /// @param trustedRelayer The address of the trusted relayer.
    /// @param ids Module identifiers (hash of contract name) that can send messages through this mailbox.
    /// @param modules The addresses of the contracts that can send messages through this mailbox.
    /// @param ethereumChainId The chainId for this Ethereum chain.
    /// @param eclipseChainId The chainId for the Eclipse chain.
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

    /// @dev Retrieves the storage struct
    /// @return $ The StorageV1 struct
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

    /// @dev Initializes the mailbox contract
    /// @param params The variable which contains all the fields needed to init
    function initialize(InitParams calldata params)
        public
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

    /// @dev Required by the OZ UUPS module
    /// @param newImplementation Address of the new implementation
    function _authorizeUpgrade(address newImplementation) 
        internal 
        virtual 
        override 
        onlyRole(DEFAULT_ADMIN_ROLE) {}

    /// @dev Generates a pseudo-random nonce based on block properties and chained state.
    /// @return Returns a 64-bit nonce generated from various entropy sources.
    function generateRandomNonce() internal returns (uint64) {
        StorageV1 storage $ = _getStorageV1();
        // Combine unpredictable block properties with the last nonce to generate a new nonce.
        $.lastNonce = uint256(
            keccak256(abi.encodePacked($.lastNonce, blockhash(block.number - 1), block.timestamp, block.coinbase))
        );
        return uint64($.lastNonce); // Return the least significant 64 bits
    }

    /// @dev Generates a chain ID from a string
    /// @param _chainId The chain ID as a string
    /// @return The generated chain ID as bytes32
    function generateChainId(string memory _chainId) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(_chainId));
    }
}
