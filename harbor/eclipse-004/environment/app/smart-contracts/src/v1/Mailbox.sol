pragma solidity 0.8.21;

import {IRoutableMailbox as IMailbox} from "./interfaces/IRoutableMailbox.sol";
import {IRegistry} from "./interfaces/IRegistry.sol";
import {IRouter} from "./interfaces/IRouter.sol";
import {Initializable} from "openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/contracts/utils/ReentrancyGuardUpgradeable.sol";
import {ECDSA} from "openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";

/// @title Mailbox
/// @dev This contract implements the mailbox interface for relayers which communicate with Ethereum.
contract Mailbox is IMailbox, Initializable, UUPSUpgradeable, OwnableUpgradeable, ReentrancyGuardUpgradeable {
    using ECDSA for bytes32;

    uint64 private nonceCounter = 0;
    bytes private ethereumChainId;
    bytes private eclipseChainId;
    address private relayer;
    mapping(uint64 => bool) private receiveNonces;
    mapping(uint64 => bool) private sendNonces;
    IRouter public router;
    IRegistry public registry;

    // @dev Messages received from Eclipse include a security param which decodes into this structure.
    // @param nonce is random number used only once for a message which is received.
    // @param authoritySignature is an ECDSA signature set by an authority via web3.eth.sign(rollupChainid, senderAddress, message, nonce)
    struct EclipseSecurityParam {
        uint64 nonce;
        bytes authoritySignature;
    }

    // @dev Messages sent to Ethereum include a security param which is encoded using this structure.
    // @param nonce is random number used only once for sending a message.
    // @param receipt_root is the patricia-merkle trie's root in the Ethereum block header containing event logs for that block.
    // @param proof is the merkle path proof for a particular event log.
    struct EthereumSecurityParam {
        uint64 nonce;
    }

    /// @dev Ensures that the chain id is less than equal to 32 bytes long.
    modifier chainIdMaxLength(bytes memory _data) {
        require(_data.length <= 32, "bytes must be 32 bytes long");
        _;
    }

    /// @dev Ensures that an address is not 0
    modifier addressIsSet(address _addr) {
        require(_addr != address(0), "Address is zero and should be initialized to a non-zero value.");
        _;
    }

    /// @dev Restricts the function call to only the authorized relayer.
    modifier onlyRelayer() {
        require(msg.sender == relayer, "Only the relayer can call this method.");
        _;
    }

    /// @dev Ensures that only the router can invoke the associated functions.
    modifier onlyRouter() {
        address routerAddress = registry.getAddress("Router");
        require(msg.sender == routerAddress, "Only the router can call this method.");
        _;
    }

    /// @dev Ensures the provided message is initialized.
    modifier initializedMessage(bytes memory message_) {
        require(message_.length > 0, "Message must be provided");
        _;
    }

    /// @dev Validates the chainId corresponds to the Eclipse chain.
    modifier validEclipseChainId(bytes memory chainId_) {
        require(bytes32(chainId_) == bytes32(eclipseChainId), "Unsupported Eclipse chain id.");
        _;
    }

    /// @dev Ensures the chainId matches the Ethereum chain.
    modifier validEthereumChainId(bytes memory chainId_) {
        require(bytes32(chainId_) == bytes32(ethereumChainId), "Unsupported Ethereum chain id.");
        _;
    }

    /// @dev Ensures the encoded identifier for the contract is less than equal to 32 bytes
    modifier validEncodedIdentifierLength(bytes memory addr) {
        require(addr.length <= 32, "The encoded identifier must be less than equal to 32 bytes");
        _;
    }

    /// @dev Initializes the mailbox contract with necessary parameters to enable inter-chain messaging.
    /// @param _ethereumChainId The chainId for this Ethereum chain.
    /// @param _eclipseChainId The chainId for the Eclipse chain.
    /// @param _relayer The address of the trusted relayer to authorize message passing.
    /// @param _registryAddress The address of the registry contract to look up addresses of smart-contracts.
    function initialize(
        bytes memory _ethereumChainId,
        bytes memory _eclipseChainId,
        address _relayer,
        address _registryAddress
    ) public chainIdMaxLength(_ethereumChainId) chainIdMaxLength(_eclipseChainId) addressIsSet(_relayer) initializer {
        __Ownable_init(msg.sender);

        ethereumChainId = _ethereumChainId;
        eclipseChainId = _eclipseChainId;
        relayer = _relayer;
        registry = IRegistry(_registryAddress);
        require(_isRegistryContract(_registryAddress), "Invalid registry contract");

        address routerAddress = registry.getAddress("Router");
        require(_isRouterContract(routerAddress), "Invalid router contract");
        router = IRouter(routerAddress);
    }

    /// @dev Receives and processes messages from other chains, ensuring they conform to the expected rollup chainId.
    function receiveMessage(
        bytes memory eclipseChainId_,
        bytes memory sender_,
        bytes memory message_,
        bytes memory data_
    )
        external
        payable
        override
        onlyRelayer
        validEclipseChainId(eclipseChainId_)
        validEncodedIdentifierLength(sender_)
        nonReentrant
        returns (bool)
    {
        // TODO: Consider moving this logic into a 'light client' smart-contract based on chain-id (ie to support Celestia, etc.)
        // Validate the receive nonce and authority signature.
        EclipseSecurityParam memory secParam = abi.decode(data_, (EclipseSecurityParam));
        require(receiveNonces[secParam.nonce] == false, "Message with this nonce already received.");

        bytes32 hash = keccak256(abi.encodePacked(eclipseChainId_, sender_, message_, secParam.nonce));
        require(ECDSA.recover(hash, secParam.authoritySignature) == relayer, "Invalid relayer signature");

        // Route the message
        router.routeIncomingMessage(sender_, message_);

        // Update the nonce
        receiveNonces[secParam.nonce] = true;

        // Emit the message received event
        emit MessageReceived(sender_, eclipseChainId_, message_);

        return true;
    }

    /// @dev Handles messages from the router, updates nonce, encodes and calls sendMessage
    function mailOutgoingMessage(bytes memory to_, bytes memory message_)
        external
        override
        onlyRouter
        validEncodedIdentifierLength(to_)
        initializedMessage(message_)
        nonReentrant
    {
        // Increment and update the outbound nonce for the recipient
        uint64 outboundNonce = generateRandomNonce();
        sendNonces[outboundNonce] = true;

        // Encode the updated nonce in the security param and send the message
        EthereumSecurityParam memory param =
            EthereumSecurityParam({nonce: outboundNonce});
        bytes memory securityParam = abi.encode(param);
        sendMessage(ethereumChainId, to_, message_, securityParam);
    }

    /// @dev Facilitates the sending of messages ensuring only the router can initiate this and the source chain is the settlement chain.
    function sendMessage(
        bytes memory ethereumChainId_,
        bytes memory receiver_,
        bytes memory message_,
        bytes memory securityParam_
    ) public payable override onlyRouter validEthereumChainId(ethereumChainId_) returns (bool) {
        emit MessageSent(receiver_, ethereumChainId_, message_, securityParam_);

        return true;
    }

    /// @dev Function to check if a contract at a given address is of type ROUTER
    function _isRouterContract(address contractAddress) internal view returns (bool) {
        IRegistry.ContractType contractType = registry.getContractType(contractAddress);
        return contractType == IRegistry.ContractType.ROUTER;
    }

    /// @dev Function to check if a contract at a given address is of type REGISTRY
    function _isRegistryContract(address contractAddress) internal view returns (bool) {
        IRegistry.ContractType contractType = registry.getContractType(contractAddress);
        return contractType == IRegistry.ContractType.REGISTRY;
    }

    /// @dev required by the OZ UUPS module
    function _authorizeUpgrade(address) internal override onlyOwner {}

    /// @dev helps to generate a unique random nonce
    function generateRandomNonce() public returns (uint64) {
        nonceCounter++;
        uint256 largeNonce =
            uint256(keccak256(abi.encodePacked(block.timestamp, block.difficulty, msg.sender, nonceCounter)));
        return uint64(largeNonce); // Automatically keeps only the 64 least significant bits
    }
}
