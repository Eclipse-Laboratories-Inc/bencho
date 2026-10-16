pragma solidity 0.8.21;

import {DeploymentScript} from "../../../script/v1/Deployment.s.sol";
import "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import "openzeppelin-contracts-upgradeable/contracts/utils/PausableUpgradeable.sol";
import "openzeppelin-foundry-upgrades/Upgrades.sol";
import "forge-std/Test.sol";

contract DepositFlowIntegrationTest is Test {
    using Upgrades for address;

    DeploymentScript private script;
    address private relayer = 0x2e41249d178C628592F3E3d5F220F8586B349588;

    function upgradeProxyPublic(address proxy, string memory contractName, bytes memory data) public {
        return Upgrades.upgradeProxy(proxy, contractName, data);
    }

    function setUp() public {
        script = new DeploymentScript();
        script.run("Ethereum", "Eclipse", relayer);
    }

    function test_DepositFlow() public {
        bytes32 recipient = 0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef;
        uint256 depositAmount = 1 ether;

        assertEq(script.treasuryProxyAddress().balance, 0 ether);

        script.etherBridge().deposit{value: depositAmount}(recipient, depositAmount);

        assertEq(script.treasuryProxyAddress().balance, 1 ether);

        // TODO: add vm expect emit for all the events.  Below is a trace:
        //    [PASS] test_DepositFlow() (gas: 116010)
        //    Traces:
        //    [116010] DepositFlowIntegrationTest::test_DepositFlow()
        //    ├─ [2274] DeploymentScript::treasuryProxyAddress() [staticcall]
        //    │   └─ ← [Return] ERC1967Proxy: [0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512]
        //    ├─ [0] VM::assertEq(0, 0) [staticcall]
        //    │   └─ ← [Return]
        //    ├─ [2404] DeploymentScript::etherBridge() [staticcall]
        //    │   └─ ← [Return] ERC1967Proxy: [0xCf7Ed3AccA5a467e9e704C703E8D87F634fB0Fc9]
        //    ├─ [94262] ERC1967Proxy::deposit{value: 1000000000000000000}(0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef, 1000000000000000000 [1e18])
        //    │   ├─ [89443] EtherBridge::deposit{value: 1000000000000000000}(0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef, 1000000000000000000 [1e18]) [delegatecall]
        //    │   │   ├─ [49944] ERC1967Proxy::sendMessage(0x, 0x0bcb6b0b9168c058e28754b0255038028ff8515b5755d989d746fdd8b8f11d7e, 0x0000000000000000000000007fa9385be102ac3eac297483dd6233d62b3e14961234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef000000000000000000000000000000000000000000000000000000003b9aca00, 0x)
        //    │   │   │   ├─ [45062] Mailbox::sendMessage(0x, 0x0bcb6b0b9168c058e28754b0255038028ff8515b5755d989d746fdd8b8f11d7e, 0x0000000000000000000000007fa9385be102ac3eac297483dd6233d62b3e14961234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef000000000000000000000000000000000000000000000000000000003b9aca00, 0x) [delegatecall]
        //    │   │   │   │   ├─ emit MessageSent(to: 0x0bcb6b0b9168c058e28754b0255038028ff8515b5755d989d746fdd8b8f11d7e, toChainId: 0x564ccaf7594d66b1eaaea24fe01f0585bf52ee70852af4eac0cc4b04711cd0e2, message: 0x0000000000000000000000007fa9385be102ac3eac297483dd6233d62b3e14961234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef000000000000000000000000000000000000000000000000000000003b9aca00, extraData: 0x0000000000000000000000000000000000000000000000000b21e9652f1a9cb5)
        //    │   │   │   │   └─ ← [Return] true
        //    │   │   │   └─ ← [Return] true
        //    │   │   ├─ [10641] ERC1967Proxy::fallback{value: 1000000000000000000}()
        //    │   │   │   ├─ [5831] Treasury::receive{value: 1000000000000000000}() [delegatecall]
        //    │   │   │   │   ├─ emit TreasuryDeposit(from: ERC1967Proxy: [0xCf7Ed3AccA5a467e9e704C703E8D87F634fB0Fc9], amount: 1000000000000000000 [1e18])
        //    │   │   │   │   └─ ← [Stop]
        //    │   │   │   └─ ← [Return]
        //    │   │   ├─ emit Deposited(sender: DepositFlowIntegrationTest: [0x7FA9385bE102ac3EAc297483Dd6233D62b3e1496], recipient: 0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef, amountWei: 1000000000000000000 [1e18])
        //    │   │   └─ ← [Stop]
        //    │   └─ ← [Return]
        //    ├─ [274] DeploymentScript::treasuryProxyAddress() [staticcall]
        //    │   └─ ← [Return] ERC1967Proxy: [0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512]
        //    ├─ [0] VM::assertEq(1000000000000000000 [1e18], 1000000000000000000 [1e18]) [staticcall]
        //    │   └─ ← [Return]
        //    └─ ← [Return]
    }
}
