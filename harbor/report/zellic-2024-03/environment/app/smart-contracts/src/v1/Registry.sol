pragma solidity 0.8.21;

import {Initializable} from "openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {IRegistry} from "./interfaces/IRegistry.sol";

/// @title Registry
/// @dev A contract to manage addresses of other contracts.
contract Registry is IRegistry, Initializable, UUPSUpgradeable, OwnableUpgradeable {
    mapping(string => address) private identifierAddress;
    mapping(address => string) private addressIdentifier;
    mapping(address => ContractType) private addressContractType;

    /// @dev Initializes the Registry contract setting the owner.
    function initialize() public initializer {
        __Ownable_init(msg.sender);
    }

    /// @dev required by the OZ UUPS module
    function _authorizeUpgrade(address) internal override onlyOwner {}

    /// @dev Only callable by the owner. Emits the `ContractRegistered` event.
    function registerContract(string memory identifier, address contractAddress, ContractType contractType)
        external
        override
        onlyOwner
    {
        require(bytes(identifier).length != 0, "Invalid contract identifier");
        require(contractAddress != address(0), "Invalid contract address");
        identifierAddress[identifier] = contractAddress;
        addressIdentifier[contractAddress] = identifier;
        addressContractType[contractAddress] = contractType;
        emit ContractRegistered(identifier, contractAddress);
    }

    /// @dev Unregisters a contract by its identifier.
    /// @param identifier The identifier of the contract to unregister.
    function unregisterContract(string memory identifier) external onlyOwner {
        address contractAddress = identifierAddress[identifier];
        require(contractAddress != address(0), "Contract not registered");

        // Remove the entries from both mappings
        delete identifierAddress[identifier];
        delete addressIdentifier[contractAddress];

        emit ContractUnregistered(identifier, contractAddress);
    }

    /// @dev Retrieve the address of a registered contract by its identifier.
    function getAddress(string memory identifier) external view override returns (address) {
        address addr = identifierAddress[identifier];
        require(addr != address(0), "Identifier not registered");
        return addr;
    }

    /// @dev Retrieve the identifier of a registered contract by its address.
    function getIdentifier(address addr) external view override returns (string memory) {
        string memory id = addressIdentifier[addr];
        require(bytes(id).length != 0, "Address not registered");
        return id;
    }

    /// @dev Retrieve the contract type of a registered contract by its address.
    function getContractType(address addr) external view returns (ContractType) {
        string memory id = addressIdentifier[addr];
        require(bytes(id).length != 0, "Address not registered");
        return addressContractType[addr];
    }
}
