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

    function test_keep_minDepositIsNotExcessive() external {
        uint256 requiredLamports = 3480 * 2 * (49 + 128);
        EtherBridge bridge = new EtherBridge();
        // At most 2x the rent-exempt minimum: raising the floor far above the
        // requirement is not a fix, it prices out legitimate deposits.
        assertLe(bridge.MIN_DEPOSIT() / 1_000_000_000, requiredLamports * 2);
    }
}
