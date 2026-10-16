pragma solidity 0.8.21;

import {Treasury} from "./Treasury.sol";
import {IRouter} from "./interfaces/IRouter.sol";
import {IRegistry} from "./interfaces/IRegistry.sol";
import {IEtherBridge} from "./interfaces/IEtherBridge.sol";
import {Initializable} from "openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/contracts/utils/ReentrancyGuardUpgradeable.sol";

/// @title EtherBridge
/// @dev A bridge contract for depositing and withdrawing ether to the Eclipse rollup.
contract EtherBridge is IEtherBridge, Initializable, UUPSUpgradeable, OwnableUpgradeable, ReentrancyGuardUpgradeable {
    uint256 private constant WEI_PER_GWEI = 1_000_000_000;
    uint256 private constant GWEI_LAMPORT_RATIO = 1;
    uint256 private constant MIN_DEPOSIT_AMOUNT = 1500000 gwei;
    uint256 private constant FEE_MARGIN = 20;
    uint256 private constant MIN_DEPOSIT_GAS_EXCLUDING_ROUTING = 100_000;
    uint256 private constant MIN_DEPOSIT_GAS_ONLY_ROUTING = 300_000;
    uint256 private constant MIN_DEPOSIT_GAS = MIN_DEPOSIT_GAS_EXCLUDING_ROUTING + MIN_DEPOSIT_GAS_ONLY_ROUTING;
    uint256 private constant MAX_DEPOSIT_AMOUNT = 1 ether;
    uint256 private constant MAX_WITHDRAW_AMOUNT = 1 ether;
    IRegistry private registry;
    IRouter private router;
    Treasury private treasury;

    /// @dev Ensures the deposit amount is greater than the minimum required amount.
    /// @param amount The amount to be deposited.
    modifier validDepositAmount(uint256 amount) {
        require(amount >= MIN_DEPOSIT_AMOUNT, "Deposit amount must be greater than equal to the minimum wei amount");
        require(amount <= MAX_DEPOSIT_AMOUNT, "Deposit amount must be less than equal to the max deposite amount");
        _;
    }

    /// @dev Ensures the fee provided is sufficient for transaction execution.
    /// @param fee The fee provided for the deposit.
    modifier sufficientFee(uint256 fee) {
        require(fee >= MIN_DEPOSIT_GAS * FEE_MARGIN, "Deposit fee amount is not enough to execute call");
        _;
    }

    /// @dev Ensures the Ether sent matches the total of the amount and fee and is less than max.
    /// @param amount The amount to be deposited.
    /// @param fee The fee provided for the deposit.
    modifier correctDepositValue(uint256 amount, uint256 fee) {
        require(msg.value == amount + fee, "Deposit amount and fee must match sent value");
        require(amount <= MAX_DEPOSIT_AMOUNT, "Amount cannot be more than the max deposit amount");
        _;
    }

    /// @dev Ensures the Ether to withdraw is less than the max withdraw amount
    /// @param amount The amount to be withdrawn.
    modifier correctWithdrawValue(uint256 amount) {
        require(amount <= MAX_WITHDRAW_AMOUNT, "Amount cannot be more than the max withdraw amount");
        _;
    }

    /// @dev Ensures the sender of the transaction matches the specified sender address.
    /// @param sender The expected sender address.
    modifier validSender(address sender) {
        require(msg.sender == sender, "The sender of the deposit does not match");
        _;
    }

    /// @dev Ensures the recipient address is set and not empty.
    /// @param recipient The recipient address in bytes32 format.
    modifier validRecipient(bytes32 recipient) {
        require(recipient != bytes32(0), "Recipient address is not set");
        _;
    }

    /// @dev Ensures the sender is the router
    modifier onlyRouter() {
        require(msg.sender == address(router), "Only router can call withdraw");
        _;
    }

    /// @dev Initializes the contract variables and deploys the treasury.
    /// @param registryAddress Address of the registry contract.
    function initialize(address registryAddress) external initializer {
        __Ownable_init(msg.sender);

        // Set registry
        require(registryAddress != address(0), "Invalid registry address");
        registry = IRegistry(registryAddress);

        // Set router
        address routerAddress = registry.getAddress("Router");
        router = IRouter(routerAddress);

        // Initialize and set treasury
        address payable treasuryAddress = payable(registry.getAddress("Treasury"));
        treasury = Treasury(treasuryAddress);
        treasury.initialize();
    }

    /// @notice Deposit ether by locking an amount of eth in the treasury.
    /// @dev Deposit uses a deposit fee to lock eth in a treasury contract and route a deposit message out.
    ///      The amount of wei gets deposited to the target chain such that 1 gwei = 1 lamport
    function deposit(bytes32 recipient, uint256 amount, uint256 fee)
        external
        payable
        override
        validDepositAmount(amount)
        sufficientFee(fee)
        correctDepositValue(amount, fee)
        validSender(msg.sender)
        validRecipient(recipient)
        nonReentrant
    {
        // Create deposit message with lamports
        uint256 lamportAmount = amount / WEI_PER_GWEI;
        uint256 feeAmount = fee / WEI_PER_GWEI;
        IEtherBridge.DepositMessage memory message = IEtherBridge.DepositMessage({
            sender: msg.sender,
            recipient: recipient,
            amount: lamportAmount,
            fee: feeAmount
        });

        // Encode message and route it out
        bytes memory encodedMessage = abi.encode(message);
        router.routeOutgoingMessage{gas: MIN_DEPOSIT_GAS_ONLY_ROUTING}(encodedMessage);

        // Lock ether by sending it to treasury
        (bool success,) = payable(address(treasury)).call{value: message.amount}("");
        require(success, "Transfer failed");

        emit Deposited(msg.sender, recipient, amount, fee);
    }

    /// @notice Initiates a withdrawal of locked Ether from treasury to the recipient
    /// @dev Emits the `Withdrawn` event upon successful processing of the withdrawal request.
    ///      Note that paying the relayer for withdraws is not yet implemented.
    /// @param message The `WithdrawMessage` containing the withdrawal details.
    function withdraw(WithdrawMessage calldata message)
        external
        override
        onlyRouter
        correctWithdrawValue(message.amount)
        nonReentrant
    {
        require(address(treasury).balance >= message.amount, "Insufficient funds in treasury for withdrawal");

        // Call the Treasury contract to withdraw funds to the recipient
        treasury.withdraw(payable(message.recipient), message.amount);

        // Emit the Withdrawn event
        emit Withdrawn(message.sender, message.recipient, message.amount);
    }

    /// @notice Get the current balance of eth stored in the treasury.
    /// @return The balance of the contract in wei.
    function getBalance() external view override returns (uint256) {
        return address(treasury).balance;
    }

    /// @notice Get the current balance of eth fees stored in this contract.
    /// @return The balance of the contract in wei.
    function getFeeBalance() external view override returns (uint256) {
        return address(this).balance;
    }

    /// @dev Estimates the fee using current tx price
    /// @return fee The estimated fee
    function estimateFee() public view returns (uint256 fee) {
        fee = FEE_MARGIN * MIN_DEPOSIT_GAS * tx.gasprice;
    }

    /// @dev Get the minimum deposit amount allowed
    /// @return amount The minimum deposit amount
    function minDepositAmount() public pure returns (uint256 amount) {
        amount = MIN_DEPOSIT_AMOUNT;
    }

    /// @dev required by the OZ UUPS module
    function _authorizeUpgrade(address) internal override onlyOwner {}
}
