pragma solidity 0.8.21;

import {IRegistry} from "../../../src/v1/interfaces/IRegistry.sol";
import {Registry} from "../../../src/v1/Registry.sol";
import {IEtherBridge} from "../../../src/v1/interfaces/IEtherBridge.sol";
import {Treasury} from "../../../src/v1/Treasury.sol";
import {EtherBridge} from "../../../src/v1/EtherBridge.sol";
import {IRoutableMailbox as IMailbox} from "../../../src/v1/interfaces/IRoutableMailbox.sol";
import {Mailbox} from "../../../src/v1/Mailbox.sol";
import {IRouter} from "../../../src/v1/interfaces/IRouter.sol";
import {Router} from "../../../src/v1/Router.sol";
import {Test, console2} from "forge-std/Test.sol";

contract Deposit_Integration_Test is Test {
    uint256 constant DEFAULT_GAS_PRICE = 1 wei;
    IRegistry registry;
    address registryAddress;
    IEtherBridge etherBridge;
    IMailbox mailbox;
    IRouter router;

    event Deposited(address indexed sender, bytes32 indexed recipient, uint256 amount, uint256 fee);

    function setUp() public virtual {
        // Prepare registry
        Registry _registry = new Registry();
        registryAddress = address(_registry);
        _registry.initialize();

        // Create contracts
        Treasury _treasury = new Treasury();
        EtherBridge _etherBridge = new EtherBridge();
        Mailbox _mailbox = new Mailbox();
        Router _router = new Router();

        // Register contracts
        _registry.registerContract("Registry", registryAddress, IRegistry.ContractType.REGISTRY);
        _registry.registerContract("Treasury", address(_treasury), IRegistry.ContractType.MODULE);
        _registry.registerContract("EtherBridge", address(_etherBridge), IRegistry.ContractType.MODULE);
        _registry.registerContract("Mailbox", address(_mailbox), IRegistry.ContractType.MAILBOX);
        _registry.registerContract("Router", address(_router), IRegistry.ContractType.ROUTER);

        // Initialize bridge (also inits treasury)
        _etherBridge.initialize(registryAddress);

        // Init mailbox
        bytes memory _sourceChainId = abi.encode(uint256(31337));
        bytes memory _targetChainId = abi.encode(uint256(313373));
        address _relayer = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266; // TODO: change from alice to relayer key
        _mailbox.initialize(_sourceChainId, _targetChainId, _relayer, registryAddress);

        // Init router
        _router.initialize(registryAddress);

        // Set interfaces to point to contracts
        registry = IRegistry(registryAddress);
        etherBridge = IEtherBridge(address(_etherBridge));
        mailbox = IMailbox(address(_mailbox));
        router = IRouter(address(_router));
    }

    function test_DepositEther_Success() external {
        vm.txGasPrice(DEFAULT_GAS_PRICE);

        uint256 depositAmount = etherBridge.minDepositAmount();
        uint256 fee = etherBridge.estimateFee();
        uint256 total = fee + depositAmount;

        IEtherBridge.DepositMessage memory message = IEtherBridge.DepositMessage({
            sender: address(this),
            recipient: bytes32(uint256(uint160(address(this)))),
            amount: depositAmount,
            fee: fee
        });

        //        vm.expectEmit(true, true, false, false);
        //        emit Deposited(address(this), message.recipient, depositAmount, fee);

        bytes32 recipient = bytes32(uint256(uint160(address(this))));
        etherBridge.deposit{value: total}(recipient, depositAmount, fee);
    }
}
