pragma solidity 0.8.21;

import "../../../src/v1/interfaces/IRegistry.sol";

contract MockRegistry is IRegistry {
    mapping(string => address) private contractAddresses;
    mapping(address => string) private contractIdentifiers;
    mapping(address => ContractType) private contractTypes;

    function registerContract(string memory identifier, address contractAddress, ContractType contractType)
        external
        override
    {
        require(contractAddress != address(0), "Invalid address");
        require(contractAddresses[identifier] == address(0), "Identifier already registered");
        contractAddresses[identifier] = contractAddress;
        contractIdentifiers[contractAddress] = identifier;
        contractTypes[contractAddress] = contractType;
        emit ContractRegistered(identifier, contractAddress);
    }

    function unregisterContract(string memory identifier) external {
        address contractAddress = contractAddresses[identifier];
        require(contractAddress != address(0), "Identifier not registered");

        delete contractAddresses[identifier];
        delete contractIdentifiers[contractAddress];
        delete contractTypes[contractAddress];

        emit ContractUnregistered(identifier, contractAddress);
    }

    function getAddress(string memory identifier) external view override returns (address) {
        return contractAddresses[identifier];
    }

    function getIdentifier(address addr) external view override returns (string memory) {
        return contractIdentifiers[addr];
    }

    function getContractType(address addr) external view override returns (ContractType) {
        return contractTypes[addr];
    }
}
