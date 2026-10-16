pragma solidity 0.8.21;

import {BaseScript} from "./Base.s.sol";
import {IRegistry} from "../../src/v1/interfaces/IRegistry.sol";
import {Registry} from "../../src/v1/Registry.sol";
import {EtherBridge} from "../../src/v1/EtherBridge.sol";
import {Treasury} from "../../src/v1/Treasury.sol";
import {Mailbox} from "../../src/v1/Mailbox.sol";
import {Router} from "../../src/v1/Router.sol";

contract DeploymentScript is BaseScript {
    function run(uint256 sourceChainId, bytes32 targetChainId, address relayer) public broadcast {
        // Deploy contracts
        Registry registry = new Registry();
        Treasury treasury = new Treasury();
        EtherBridge etherBridge = new EtherBridge();
        Mailbox mailbox = new Mailbox();
        Router router = new Router();

        // Init registry and register contracts
        address registryAddress = address(registry);
        registry.initialize();
        registry.registerContract("Registry", registryAddress, IRegistry.ContractType.REGISTRY);
        registry.registerContract("Treasury", address(treasury), IRegistry.ContractType.MODULE);
        registry.registerContract("EtherBridge", address(etherBridge), IRegistry.ContractType.MODULE);
        registry.registerContract("Mailbox", address(mailbox), IRegistry.ContractType.MAILBOX);
        registry.registerContract("Router", address(router), IRegistry.ContractType.ROUTER);

        // Initialize bridge & mailbox
        etherBridge.initialize(registryAddress);
        mailbox.initialize(abi.encode(sourceChainId), abi.encode(targetChainId), relayer, registryAddress);

        // Finally, init router last
        router.initialize(registryAddress);
    }
}
