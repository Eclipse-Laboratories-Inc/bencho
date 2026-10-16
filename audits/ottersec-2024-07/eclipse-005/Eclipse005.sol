// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {EtherBridge} from "../../src/v1/EtherBridge.sol";
import {Test} from "forge-std/Test.sol";

contract Eclipse005_Test is Test {
    function test_audit_minDepositCoversRentOverhead() external {
        uint256 lamportsPerByteYear = 3480;
        uint256 exemptionThreshold = 2;
        uint256 dataLen = 49;
        uint256 accountStorageOverhead = 128;
        uint256 requiredLamports = lamportsPerByteYear * exemptionThreshold * (dataLen + accountStorageOverhead);
        EtherBridge bridge = new EtherBridge();
        assertGe(bridge.MIN_DEPOSIT() / 1_000_000_000, requiredLamports);
    }
}
