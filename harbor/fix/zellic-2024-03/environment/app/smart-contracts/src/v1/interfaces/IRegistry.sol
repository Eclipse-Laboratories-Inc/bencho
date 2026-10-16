pragma solidity 0.8.21;

/// @title IRegistry
/// @dev Interface for a registry contract that can register and look up smart-contract addresses and identifiers.
interface IRegistry {
    enum ContractType {
        REGISTRY,
        MAILBOX,
        ROUTER,
        MODULE,
        OTHER
    }

    /// @notice Emitted when a new contract address is registered or an existing one is updated.
    /// @param identifier The identifier of the contract.
    /// @param contractAddress The registered address for the contract.
    event ContractRegistered(string identifier, address contractAddress);

    /// @notice Emitted when an added contract address is unregistered.
    /// @param identifier The identifier of the contract.
    /// @param contractAddress The registered address for the contract.
    event ContractUnregistered(string identifier, address contractAddress);

    /// @notice Register or update the address using it's identifier.
    /// @param identifier The identifier of the contract.
    /// @param contractAddress The address to register under the given identifier.
    function registerContract(string memory identifier, address contractAddress, ContractType contractType) external;

    /// @notice Retrieve the address of a registered contract by its identifier.
    /// @param identifier The identifier of the contract to retrieve.
    /// @return The address of the registered contract, or the zero address if not found.
    function getAddress(string memory identifier) external view returns (address);

    /// @notice Retrieve the identifier of a registered contract by its address.
    /// @param addr The address of the contract to retrieve.
    /// @return The identifier of the registered contract or an empty string if not found
    function getIdentifier(address addr) external view returns (string memory);

    /// @notice Retrieve the contract type of a registered contract by its address.
    /// @dev This function will either return a contract type or throw an exception
    /// @param addr The address of the contract.
    /// @return The contract type of the registered contract.
    function getContractType(address addr) external view returns (ContractType);
}
