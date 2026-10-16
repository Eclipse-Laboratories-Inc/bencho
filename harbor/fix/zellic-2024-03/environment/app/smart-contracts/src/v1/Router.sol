pragma solidity 0.8.21;

import {Initializable} from "openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/contracts/utils/ReentrancyGuardUpgradeable.sol";
import {IRouter} from "./interfaces/IRouter.sol";
import {IRegistry} from "./interfaces/IRegistry.sol";
import {IRoutableMailbox as IMailbox} from "./interfaces/IRoutableMailbox.sol";

/// @title Router
/// @dev A contract to route messages to the appropriate contracts.
/// Works in tandem with a Registry to retrieve contract addresses.
contract Router is IRouter, Initializable, UUPSUpgradeable, OwnableUpgradeable, ReentrancyGuardUpgradeable {
    IRegistry private registry;
    IMailbox private mailbox;

    /// @dev Check if the caller is a module contract
    modifier onlyModuleContract() {
        require(_isModuleContract(msg.sender), "Caller is not a module contract");
        _;
    }

    /// @dev Check if the caller is a module contract
    modifier onlyMailboxContract() {
        require(_isMailboxContract(msg.sender), "Caller is not the mailbox contract");
        _;
    }

    /// @dev Initializes the router using the registry address.
    /// @param registryAddress The address of the deployed Registry contract.
    function initialize(address registryAddress) public initializer {
        __Ownable_init(msg.sender);

        registry = IRegistry(registryAddress);
        address mailboxAddress = registry.getAddress("Mailbox");
        mailbox = IMailbox(mailboxAddress);
    }

    /// @dev required by the OZ UUPS module
    function _authorizeUpgrade(address) internal override onlyOwner {}

    /// @notice Routes a message to the appropriate destination based on the identifier.
    /// @dev It retrieves the Ethereum address using a lookup in the registry by identifier.
    /// @param encodedIdentifier The encoded identifier represented as bytes.
    /// @param message The message to route.
    function routeIncomingMessage(bytes calldata encodedIdentifier, bytes calldata message)
        external
        payable
        override
        onlyMailboxContract
        nonReentrant
    {
        string memory identifier = abi.decode(encodedIdentifier, (string));
        address actualAddress = registry.getAddress(identifier);
        require(actualAddress != address(0), "This identifier does not have a registered address");
        require(
            registry.getContractType(actualAddress) == IRegistry.ContractType.MODULE, "This address is not a module"
        );

        (bool success,) = actualAddress.call(message);
        require(success, "External call failed");
    }

    /// @notice Routes an outgoing message to a mailbox
    /// @dev It retrieves the Mailbox address from the Registry and then forwards the message.
    /// @param message The arbitrary message intended for the external chain or service.
    function routeOutgoingMessage(bytes calldata message) external payable override onlyModuleContract nonReentrant {
        string memory identifier = registry.getIdentifier(msg.sender);
        bytes memory destination = bytes(identifier);
        mailbox.mailOutgoingMessage(destination, message);
    }

    /// @dev Function to check if a contract at a given address is of type MODULE
    function _isModuleContract(address contractAddress) internal view returns (bool) {
        IRegistry.ContractType contractType = registry.getContractType(contractAddress);
        return contractType == IRegistry.ContractType.MODULE;
    }

    /// @dev Function to check if a contract at a given address is of type MAILBOX
    function _isMailboxContract(address contractAddress) internal view returns (bool) {
        IRegistry.ContractType contractType = registry.getContractType(contractAddress);
        return contractType == IRegistry.ContractType.MAILBOX;
    }

    /// @dev Function to check if a contract at a given address is of type REGISTRY
    function _isRegistryContract(address contractAddress) internal view returns (bool) {
        IRegistry.ContractType contractType = registry.getContractType(contractAddress);
        return contractType == IRegistry.ContractType.REGISTRY;
    }
}
