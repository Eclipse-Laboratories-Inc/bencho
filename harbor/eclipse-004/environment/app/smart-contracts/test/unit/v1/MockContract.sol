pragma solidity 0.8.21;

import {console2} from "forge-std/Test.sol";

contract MockContract {
    // Fallback function
    fallback() external payable {
        console2.log("MockContract fallback called");
    }
}
