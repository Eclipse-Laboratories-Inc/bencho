// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import { Test, console2 } from "../../lib/forge-std/src/Test.sol";
import { ERC1967Proxy } from "../../lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";

// Reprentations of contracts to upgrade and their states.
import { OldTreasuryMock } from "../mocks/OldTreasuryMock.sol";

// Representations of the new contracts with simple, controllable behavior.
import { MockTreasury } from "../mocks/MockTreasury.sol";

// New contracts derived from upgraded treasury and new CanonicalBridge
import { Treasury } from "../../src/v1/Treasury.sol";
import { CanonicalBridge } from "../../src/v1/CanonicalBridge.sol";


contract DeployAndUpgradeFixture is Test {

    bytes32 public constant MODULE1_ID = keccak256("MODULE1");
    bytes32 public constant MODULE2_ID = keccak256("MODULE2");
    
    address public constant NULL_ADDRESS = address(0);
    bytes32 public constant DEFAULT_ADMIN_ROLE = bytes32(0);
    bytes32 public constant DEPOSITOR_ROLE = keccak256("Depositor");
    bytes32 public constant WITHDRAW_AUTHORITY_ROLE = keccak256("WithdrawalAuthority");
    bytes32 public constant WITHDRAW_CANCELLER_ROLE = keccak256("WithdrawalCanceller");
    bytes32 public constant FRAUD_WINDOW_SETTER_ROLE = keccak256("FraudWindowSetter");
    bytes32 public constant PAUSER_ROLE = keccak256("Pauser");
    bytes32 public constant STARTER_ROLE = keccak256("Starter");
    bytes32 public constant UPGRADER_ROLE = keccak256("Upgrader");
    bytes32 public constant EMERGENCY_ROLE = keccak256("Emergency");
    bytes32 public constant TRUSTED_RELAYER_ROLE = keccak256("TRUSTED_RELAYER_ROLE");
    bytes32 public constant MODULE_ROLE = keccak256("MODULE_ROLE");
    bytes32 public constant ADMIN_AUTHORITY_ROLE = keccak256("ADMIN_AUTHORITY_ROLE");

    MockTreasury public mockTreasury;
    CanonicalBridge public bridgeWithMockedDependencies;

    OldTreasuryMock public oldTreasuryImpl;
    OldTreasuryMock public oldTreasury;
    ERC1967Proxy public treasuryProxy;
    Treasury public treasury;
    CanonicalBridge public canonicalBridge;

    string public ethereumChainId = "1";
    string public eclipseChainId = "2";

    address public deployer = address(this);
    address public newOwner = makeAddr("newOwner");
    address public notBridge = makeAddr("notBridge");

    address public admin = makeAddr("admin");
    address public emergencyOperator = makeAddr("emergency");
    address public trustedRelayer = makeAddr("trustedRelayer");
    address public bridgeTroll = makeAddr("troll");
    address public nonAdmin = makeAddr("nonAdmin");
    address public nonRelayer = makeAddr("nonRelayer");
    address public nonModule = makeAddr("nonModule");
    address public pauser = makeAddr("pauser");
    address public starter = makeAddr("starter");
    address public recipient = makeAddr("receipient");
    address public feeRecipient = makeAddr("feeRecipient");
    address public withdrawalAuthority = makeAddr("withdrawalAuthority");
    address public depositor = makeAddr("depositor");

    address public module1Addr = makeAddr("module1");
    address public module2Addr = makeAddr("module2");

    event Initialized(uint64 version);
    event Upgraded(address indexed implementation);
    event Reinitialized(address admin);
    event TreasuryReinitialized(address admin, address oldOwner);
    event RoleGranted(bytes32 indexed role, address indexed account, address indexed sender);

    error InvalidInitialization();
    error AccessControlUnauthorizedAccount(address sender, bytes32 role);

    event Deployed(address indexed deployer, address owner, address treasuryAddress);
    event FraudWindowSet(address indexed sender, uint256 durationSeconds);

    /// @notice Deploy mocks and upgrade to initial configuration. 
    /// @dev Arranges permissions with default Troll and human intervention possibilities. Admin controls ACLs.
    /// @param admin_ The address that will receive the admin authority, or 0x0 and one will be assigned.
    function deployMocksAndUpgrade(address admin_) public {
        deployOldTreasuryMockAndUpgrade();
        deployNewCanonicalBridge();

        if (admin_ != NULL_ADDRESS) admin = admin_;

        // The admin controls ACL
        vm.startPrank(admin);
    
        // The bridge is authoritative for treasury deposits and withdrawals
        vm.expectEmit(true, true, true, true);
        emit RoleGranted(DEPOSITOR_ROLE, address(canonicalBridge), admin);
        treasury.grantRole(DEPOSITOR_ROLE, address(canonicalBridge));

        vm.expectEmit(true, true, true, true);
        emit RoleGranted(WITHDRAW_AUTHORITY_ROLE, address(canonicalBridge), admin);
        treasury.grantRole(WITHDRAW_AUTHORITY_ROLE, address(canonicalBridge));

        // The bridge recognizes the external bridge troll for fraud-intervention functions. See the contract 
        // initializers and constructors for default human intervention roles that are granted to the admin.

        vm.expectEmit(true, true, true, true);
        emit RoleGranted(WITHDRAW_CANCELLER_ROLE, bridgeTroll, admin); 
        canonicalBridge.grantRole(WITHDRAW_CANCELLER_ROLE, bridgeTroll);

        vm.expectEmit(true, true, true, true);
        emit RoleGranted(PAUSER_ROLE, bridgeTroll, admin); 
        canonicalBridge.grantRole(PAUSER_ROLE, bridgeTroll);

        vm.expectEmit(true, true, true, true);
        emit RoleGranted(STARTER_ROLE, bridgeTroll, admin); 
        canonicalBridge.grantRole(STARTER_ROLE, bridgeTroll);

        mockTreasury = new MockTreasury();
        bridgeWithMockedDependencies = new CanonicalBridge(admin, address(mockTreasury));
    }

    function deployOldTreasuryMockAndUpgrade() public {
        oldTreasuryImpl = new OldTreasuryMock();

        // upgradeable TreasuryMock
        treasuryProxy = new ERC1967Proxy(
            address(oldTreasuryImpl),
            abi.encodeWithSelector(oldTreasuryImpl.initialize.selector, admin)
        );
        oldTreasury = OldTreasuryMock(payable(address(treasuryProxy)));

        vm.deal(depositor, 200000 ether);
        payable(address(oldTreasury)).transfer(100 ether);

        Treasury newTreasuryImpl = new Treasury();

        vm.expectEmit(true, true, true, true);
        emit Upgraded(address(newTreasuryImpl));

        vm.expectEmit(true, true, true, true);
        emit TreasuryReinitialized(admin, admin);

        vm.expectEmit(true, true, true, true);
        emit RoleGranted(DEFAULT_ADMIN_ROLE, admin, admin);

        vm.expectEmit(true, true, true, true);
        emit RoleGranted(PAUSER_ROLE, admin, admin);

        vm.expectEmit(true, true, true, true);
        emit RoleGranted(STARTER_ROLE, admin, admin);

        vm.expectEmit(true, true, true, true);
        emit RoleGranted(UPGRADER_ROLE, admin, admin);   

        vm.expectEmit(true, true, true, true);
        emit RoleGranted(EMERGENCY_ROLE, admin, admin);

        vm.expectEmit(true, true, true, true);
        emit Initialized(2);

        vm.startPrank(admin);

        // Upgrade the Treasury
        oldTreasury.upgradeToAndCall(
            address(newTreasuryImpl),
            abi.encodeWithSelector(Treasury.reinitialize.selector)
        );

        // Set the treasury instance to point to the proxy with the new implementation
        treasury = Treasury(payable(address(treasuryProxy)));
    }

    function deployNewCanonicalBridge() private {

        /// @dev Foundry misses events that emit during construction.

        // vm.expectEmit(true, true, true, true);
        // emit Deployed(address(this), admin, address(treasury));

        // vm.expectEmit(true, true, true, true);
        // emit FraudWindowSet(address(this), 7 days);

        canonicalBridge = new CanonicalBridge(
            admin, 
            address(treasury)
        );
    }
}
