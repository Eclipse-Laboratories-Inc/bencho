pragma solidity 0.8.21;

import "../../../src/v1/CommonContainer.sol";
import "forge-std/Test.sol";

contract CommonContainerTest is Test, CommonContainer {
    function setUp() public {
        // No specific setup is required for CommonContainer
    }

    // External dummy functions for testing modifiers
    function checkAddressInitialized(address a) external addressInitialized(a) {}
    function checkAddressArrayInitialized(address[] calldata addresses) external addressArrayInitialized(addresses) {}
    function checkBytesInitialized(bytes calldata data) external bytesInitialized(data) {}
    function checkBytesArrayInitialized(bytes[] calldata data) external bytesArrayInitialized(data) {}
    function checkBytes32Initialized(bytes32 data) external bytes32Initialized(data) {}
    function checkBytes32ArrayInitialized(bytes32[] calldata data) external bytes32ArrayInitialized(data) {}
    function checkBytesLengthEq32(bytes calldata data) external bytesLengthEq32(data) {}

    function testEncodeChainId_ValidInput() public {
        bytes32 input = keccak256("chain123");
        bytes memory result = encodeChainId(input);
        assertEq(result, abi.encode(input), "Encoded output does not match expected value.");
    }

    function testGenerateChainId_ValidString() public {
        string memory input = "chain123";
        bytes32 result = generateChainId(input);
        assertEq(result, keccak256(abi.encodePacked(input)), "Generated chain ID does not match expected value.");
    }

    function testDecodeChainId_ValidInput() public {
        bytes32 expected = keccak256("chain123");
        bytes memory encoded = abi.encode(expected);
        bytes32 decoded = decodeChainId(encoded);
        assertEq(decoded, expected, "Decoded chain ID does not match expected value.");
    }

    // Test cases using external calls to test modifiers
    function testAddressInitialized_NonZeroAddress() public {
        this.checkAddressInitialized(address(0x1));
    }

    function testAddressInitialized_ZeroAddress() public {
        vm.expectRevert("CommonUtility: zero address");
        this.checkAddressInitialized(address(0));
    }

    function testAddressArrayInitialized_AllValidAddresses() public {
        address[] memory testAddresses = new address[](2);
        testAddresses[0] = address(0x1);
        testAddresses[1] = address(0x2);
        this.checkAddressArrayInitialized(testAddresses);
    }

    function testAddressArrayInitialized_ContainsZeroAddress() public {
        address[] memory testAddresses = new address[](2);
        testAddresses[0] = address(0x1);
        testAddresses[1] = address(0);
        vm.expectRevert("CommonUtility: zero address in array");
        this.checkAddressArrayInitialized(testAddresses);
    }

    function testBytesInitialized_NonEmptyBytes() public {
        bytes memory testData = "data";
        this.checkBytesInitialized(testData);
    }

    function testBytesInitialized_EmptyBytes() public {
        bytes memory testData = "";
        vm.expectRevert("CommonUtility: empty bytes");
        this.checkBytesInitialized(testData);
    }

    function testBytesArrayInitialized_AllNonEmpty() public {
        bytes[] memory testDataArray = new bytes[](2);
        testDataArray[0] = "data";
        testDataArray[1] = "more data";
        this.checkBytesArrayInitialized(testDataArray);
    }

    function testBytesArrayInitialized_ContainsEmptyBytes() public {
        bytes[] memory testDataArray = new bytes[](2);
        testDataArray[0] = "data";
        testDataArray[1] = "";
        vm.expectRevert("CommonUtility: empty bytes in bytes array");
        this.checkBytesArrayInitialized(testDataArray);
    }

    function testBytesArrayInitialized_EmptyArray() public {
        bytes[] memory testDataArray = new bytes[](0);
        vm.expectRevert("CommonUtility: empty bytes array");
        this.checkBytesArrayInitialized(testDataArray);
    }

    function testBytes32Initialized_NonEmptyBytes32() public {
        bytes32 testData = keccak256("data");
        this.checkBytes32Initialized(testData);
    }

    function testBytes32Initialized_EmptyBytes32() public {
        bytes32 testData = bytes32(0);
        vm.expectRevert("CommonUtility: empty bytes32");
        this.checkBytes32Initialized(testData);
    }

    function testBytes32ArrayInitialized_AllNonEmpty() public {
        bytes32[] memory testDataArray = new bytes32[](3);
        testDataArray[0] = keccak256("data");
        testDataArray[1] = keccak256("more data");
        testDataArray[2] = keccak256("yet more data");
        this.checkBytes32ArrayInitialized(testDataArray);
    }

    function testBytes32ArrayInitialized_ContainsEmptyBytes32() public {
        bytes32[] memory testDataArray = new bytes32[](2);
        testDataArray[0] = keccak256("data");
        testDataArray[1] = bytes32(0);
        vm.expectRevert("CommonUtility: empty bytes32 in bytes32 array");
        this.checkBytes32ArrayInitialized(testDataArray);
    }

    function testBytes32ArrayInitialized_EmptyArray() public {
        bytes32[] memory testDataArray = new bytes32[](0);
        vm.expectRevert();
        this.checkBytes32ArrayInitialized(testDataArray);
    }

    function testBytesLengthEq32_Exactly32Bytes() public {
        bytes memory testData = new bytes(32);
        this.checkBytesLengthEq32(testData);
    }

    function testBytesLengthEq32_Not32Bytes_Longer() public {
        bytes memory testData = new bytes(33);
        vm.expectRevert("CommonUtility: bytes must be 32 bytes long");
        this.checkBytesLengthEq32(testData);
    }

    function testBytesLengthEq32_Not32Bytes_Shorter() public {
        bytes memory testData = new bytes(31);
        vm.expectRevert("CommonUtility: bytes must be 32 bytes long");
        this.checkBytesLengthEq32(testData);
    }

    function testAddressArrayInitialized_AllNonZeroAddresses() public {
        address[] memory testAddresses = new address[](3);
        testAddresses[0] = address(0x1);
        testAddresses[1] = address(0x2);
        testAddresses[2] = address(0x3);
        this.checkAddressArrayInitialized(testAddresses);
    }

    function testAddressArrayInitialized_MixedZeroAndNonZeroAddresses() public {
        address[] memory testAddresses = new address[](3);
        testAddresses[0] = address(0);
        testAddresses[1] = address(0x2);
        testAddresses[2] = address(0);
        vm.expectRevert("CommonUtility: zero address in array");
        this.checkAddressArrayInitialized(testAddresses);
    }

    function testBytesInitialized_SingleByte() public {
        bytes memory testData = new bytes(1);
        testData[0] = 0x01;
        this.checkBytesInitialized(testData);
    }

    function testBytesArrayInitialized_AlternatingEmptyAndNonEmpty() public {
        bytes[] memory testDataArray = new bytes[](3);
        testDataArray[0] = "data";
        testDataArray[1] = "";
        testDataArray[2] = "more data";
        vm.expectRevert("CommonUtility: empty bytes in bytes array");
        this.checkBytesArrayInitialized(testDataArray);
    }

    function testBytes32ArrayInitialized_MixedZeroAndNonZero() public {
        bytes32[] memory testDataArray = new bytes32[](3);
        testDataArray[0] = keccak256("data");
        testDataArray[1] = bytes32(0);
        testDataArray[2] = keccak256("more data");
        vm.expectRevert("CommonUtility: empty bytes32 in bytes32 array");
        this.checkBytes32ArrayInitialized(testDataArray);
    }

    function testBytesLengthEq32_NonEmpty32Bytes() public {
        bytes memory testData = new bytes(32);
        for (uint256 i = 0; i < testData.length; i++) {
            testData[i] = bytes1(uint8(i));
        }
        this.checkBytesLengthEq32(testData);
    }
}
