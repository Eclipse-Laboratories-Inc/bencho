// All Rights Reserved
pragma solidity 0.8.21;

/**
 * @title ISemVer
 * @dev Interface for SemVer versioning within smart contracts.
 */
interface ISemVerV0 {
    /**
     * @dev Struct to hold the version components.
     * @param major The major version component, incremented for incompatible API changes.
     * @param minor The minor version component, incremented for added functionality in a backwards-compatible manner.
     * @param patch The patch version component, incremented for backwards-compatible bug fixes.
     */
    struct Version {
        uint8 major;
        uint8 minor;
        uint8 patch;
    }

    /**
     * @dev Returns the major, minor, and patch components of the version as a struct.
     * @return Version memory Returns the version details encapsulated in a Version struct.
     */
    function getVersionComponents() external pure returns (Version memory);
}
