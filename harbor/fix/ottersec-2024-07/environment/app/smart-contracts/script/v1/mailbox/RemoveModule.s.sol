pragma solidity 0.8.21;

import {BaseScript} from "../Base.s.sol";
import {Mailbox} from "../../../src/v1/Mailbox.sol";

contract RemoveModuleScript is BaseScript {
    function run(address mailboxProxyAddress, bytes32 moduleId, address module) public broadcast {
        Mailbox mailbox = Mailbox(mailboxProxyAddress);
        mailbox.removeModule(moduleId, module);
    }
}
