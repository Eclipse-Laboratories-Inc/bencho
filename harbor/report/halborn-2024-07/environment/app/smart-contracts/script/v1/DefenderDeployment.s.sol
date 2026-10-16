pragma solidity 0.8.21;

import {BaseScript} from "./Base.s.sol";
import {EtherBridge} from "../../src/v1/EtherBridge.sol";
import {Treasury} from "../../src/v1/Treasury.sol";
import {Mailbox} from "../../src/v1/Mailbox.sol";
import "openzeppelin-foundry-upgrades/Defender.sol";
import "openzeppelin-foundry-upgrades/Upgrades.sol";

contract DeploymentScript is BaseScript {
    address public treasuryProxyAddress;
    address public etherBridgeProxyAddress;
    address public mailboxProxyAddress;

    Treasury public treasury;
    EtherBridge public etherBridge;
    Mailbox public mailbox;

    function run(string memory defenderRelayerId) public broadcast {
        ApprovalProcessResponse memory upgradeApprovalProcess = Defender.getUpgradeApprovalProcess();

        if (upgradeApprovalProcess.via == address(0)) {
            revert(
                string.concat(
                    "Upgrade approval process with id ",
                    upgradeApprovalProcess.approvalProcessId,
                    " has no assigned address"
                )
            );
        }

        Options memory opts;
        opts.defender.useDefenderDeploy = true;
        opts.defender.relayerId = defenderRelayerId;

        // Deploy all proxies with empty init data
        bytes memory emptyInitData = "";
        treasuryProxyAddress = Upgrades.deployUUPSProxy("Treasury.sol:Treasury", emptyInitData, opts);
        etherBridgeProxyAddress = Upgrades.deployUUPSProxy("EtherBridge.sol:EtherBridge", emptyInitData, opts);
        mailboxProxyAddress = Upgrades.deployUUPSProxy("Mailbox.sol:Mailbox", emptyInitData, opts);
    }
}
