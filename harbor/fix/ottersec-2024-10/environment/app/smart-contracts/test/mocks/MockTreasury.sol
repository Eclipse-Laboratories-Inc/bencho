// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

contract MockTreasury {
    bool isDepositOk;
    bool isWithdrawOk;
    bool withdrawReturnValue;
    error DepositFailed();
    error WithdrawFailed();

    constructor() {
        isDepositOk = true;
        isWithdrawOk = true;
        withdrawReturnValue = true;
    }

    function depositEth() external payable {
        // it receives ether
        if (!isDepositOk) revert DepositFailed();
    }

    function mockDepositEth(bool success) external {
        isDepositOk = success;
    }

    function withdrawEth(address, uint256, address, uint256) external view returns (bool success) {
        if (!isWithdrawOk) revert WithdrawFailed();
        return withdrawReturnValue;
    }

    function mockWithdrawEth(bool returnValue, bool success) external {
        withdrawReturnValue = returnValue;
        isWithdrawOk = success;
    }
}