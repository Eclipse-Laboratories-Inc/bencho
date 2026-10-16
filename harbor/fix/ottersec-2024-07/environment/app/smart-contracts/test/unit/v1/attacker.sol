pragma solidity 0.8.21;

import {ITreasury} from "../../../src/v1/interfaces/ITreasury.sol";
import "forge-std/Test.sol";

contract ReentrantAttacker {
    ITreasury public treasury;
    uint256 private counter = 0;

    constructor(address _treasury) {
        treasury = ITreasury(_treasury);
    }

    // Fallback or receive function to perform the re-entrancy attack
    receive() external payable {
        treasury.emergencyWithdraw(0.1 ether);
    }

    // Function to initiate the attack
    function attack() external payable {
        treasury.emergencyWithdraw(0.2 ether);
    }
}
