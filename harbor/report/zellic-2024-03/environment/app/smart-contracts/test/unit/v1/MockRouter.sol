pragma solidity 0.8.21;

import "../../../src/v1/interfaces/IRouter.sol";

contract MockRouter is IRouter {
    event IncomingMessageRouted(bytes sender, bytes message);
    event OutgoingMessageRouted(bytes message);

    bool private shouldRevert;
    bool private shouldConsumeAllGas;

    function routeIncomingMessage(bytes calldata sender, bytes calldata message) external payable override {
        if (shouldRevert) {
            revert("MockRouter: Forced revert");
        }
        if (shouldConsumeAllGas) {
            while (true) {} // Consume all gas
        }
        emit IncomingMessageRouted(sender, message);
    }

    function routeOutgoingMessage(bytes calldata message) external payable override {
        if (shouldRevert) {
            revert("MockRouter: Forced revert");
        }
        if (shouldConsumeAllGas) {
            while (true) {} // Consume all gas
        }
        emit OutgoingMessageRouted(message);
    }

    function setShouldRevert(bool _shouldRevert) external {
        shouldRevert = _shouldRevert;
    }

    function setShouldConsumeAllGas(bool _shouldConsumeAllGas) external {
        shouldConsumeAllGas = _shouldConsumeAllGas;
    }
}
