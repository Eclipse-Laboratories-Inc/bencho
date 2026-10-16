pragma solidity 0.8.21;

import {Script} from "forge-std/Script.sol";

abstract contract BaseScript is Script {
    /// @dev Default dev mnemonic
    string internal constant DEV_MNEMONIC = "test test test test test test test test test test test junk";

    /// @dev The address of the transaction sender.
    address internal sender;

    /// @dev Used to derive the broadcaster's address if $ETH_FROM is not defined.
    string internal mnemonic;

    /// @dev Used to control the start adn stop of vm for broadcast
    modifier broadcast() {
        vm.startBroadcast(sender);
        _;
        vm.stopBroadcast();
    }

    /// @dev Initializes the tx sender address from an env variable and if not set tries to set it using mnemonic
    constructor() {
        sender = vm.envOr({name: "SENDER", defaultValue: address(0)});
        if (sender == address(0)) {
            mnemonic = vm.envOr({name: "MNEMONIC", defaultValue: DEV_MNEMONIC});
            (sender,) = deriveRememberKey({mnemonic: mnemonic, index: 0});
        }
    }
}
