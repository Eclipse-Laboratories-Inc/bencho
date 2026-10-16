pragma solidity 0.8.21;

import {BaseScript} from "../Base.s.sol";
import {Treasury} from "../../../src/v1/Treasury.sol";

contract EmergencyWithdrawScript is BaseScript {
    function run(address payable treasuryProxyAddress, uint256 amount) public broadcast {
        Treasury treasury = Treasury(treasuryProxyAddress);
        treasury.emergencyWithdraw(amount);
    }
}
