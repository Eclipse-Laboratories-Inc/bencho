pragma solidity 0.8.21;

/// @title Common Container
/// @dev Contains modifiers for validating `ChainId`, `bytesArray` init status and address validation.
abstract contract CommonContainer {
    function encodeChainId(bytes32 _chainId) internal pure returns (bytes memory) {
        return abi.encode(_chainId);
    }

    function generateChainId(string memory _chainId) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(_chainId));
    }

    function decodeChainId(bytes memory _encodedChainId) internal pure returns (bytes32) {
        return abi.decode(_encodedChainId, (bytes32));
    }

    /// @dev Ensures that address is non-zero.
    modifier addressInitialized(address _address) {
        require(_address != address(0), "CommonUtility: zero address");
        _;
    }

    /// @dev Ensures that all addresses are non-zero.
    modifier addressArrayInitialized(address[] memory _addresses) {
        require(_addresses.length > 0, "CommonUtility: addresses is empty");
        for (uint256 i = 0; i < _addresses.length; i++) {
            require(_addresses[i] != address(0), "CommonUtility: zero address in array");
        }
        _;
    }

    /// @dev Ensures that bytes have been initialized with data.
    modifier bytesInitialized(bytes memory _data) {
        require(_data.length > 0, "CommonUtility: empty bytes");
        _;
    }

    /// @dev Ensures that array of bytes have been initialized with data.
    modifier bytesArrayInitialized(bytes[] memory _data) {
        require(_data.length > 0, "CommonUtility: empty bytes array");
        for (uint256 i = 0; i < _data.length; i++) {
            require(_data[i].length > 0, "CommonUtility: empty bytes in bytes array");
        }
        _;
    }

    /// @dev Ensures that bytes32 data is initialized with data.
    modifier bytes32Initialized(bytes32 _data) {
        require(_data != bytes32(0), "CommonUtility: empty bytes32");
        _;
    }

    /// @dev Ensures that an array of bytes32 data is initialized.
    modifier bytes32ArrayInitialized(bytes32[] memory _data) {
        require(_data.length > 0, "CommonUtility: empty bytes32 array");
        for (uint256 i = 0; i < _data.length; i++) {
            require(_data[i] != bytes32(0), "CommonUtility: empty bytes32 in bytes32 array");
        }
        _;
    }

    /// @dev Ensures that bytes data is exactly equal to 32.
    modifier bytesLengthEq32(bytes memory _data) {
        require(_data.length == 32, "CommonUtility: bytes must be 32 bytes long");
        _;
    }
}
