pragma solidity 0.8.21;

import {BaseScript} from "../Base.s.sol";
import {Treasury} from "../../../src/v1/Treasury.sol";

contract OwnerFundTreasuryScript is BaseScript {
    function run(address payable treasuryProxyAddress, uint256 depositAmount) public broadcast {
        (bool success,) = treasuryProxyAddress.call{value: depositAmount}("");
        require(success, "Unable to manually deposit ether into treasury");
    }
}
