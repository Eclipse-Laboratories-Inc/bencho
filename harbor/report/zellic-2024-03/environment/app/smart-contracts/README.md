# Ethereum bridge smart contracts

The Ethereum smart-contracts define an interface for relayers and end users to deposit and withdraw ether using canonical bridge.

Specifically, relayers interact with a `Mailbox` contract using an EIP-6170 interface.  End users interact with the `EtherBridge` contracts to deposit and withdraw ether.

The `Router` and `Registry` smart contracts are used to enable communications between the `Mailbox` and `EtherBridge`.

Currently there are a few issues that are not yet resolved in the smart-contracts.  They are listed here:

* UUPS proxy upgrades have not been fully designed, implemented and tested though some partial research has been done.  UUPS is useful in that we plan on eventually freezing the upgradeability of these contracts.
* It is intended that a different multi-sig deployment authority will deploy the contracts, but the treasury will be managed by another party or perhaps will remain not upgradeable.
* Withdraws have not been unit tested
* Registry should potentially be refactored to use an AccessList or a better RBA mechanism that is built into a library like Open-Zeppelin instead of using our custom one.
* The project only has a simple integration test for deposits and needs more thorough integration testing.

Note that the simulated mailbox is not to be deployed, but is used only for integration testing internally. 

## Organization

At a high-level the project has a src, test, script and specs folder.

The `src` has a folder for the major version currently implemented (`v1`).

The `test` folder contains unit tests which can be run using `forge test`

The `specs` folder contains a high-level description of the intended features and behavior of each smart-contract.

The `script` folder contains deployment scripts.

More details on the smart-contract design can be found in the `specs` folder.

## Usage

The smart-contracts are built, deployed and tested using [Foundry](https://github.com/foundry-rs/foundry). 

Please consult the official [foundry documentation](https://book.getfoundry.sh/) for a detailed explanation. 

Our mono-repo has a Makefile to simplify building the project, but ensure you call 

```bash
make install-forge-deps
```

prior to building, testing and deploying.

### Building

To build the smart-contracts ensure that the forge-deps are installed and run

```bash
make forge-build 
```

### Testing

To test the project use the following command:
```bash
make forge-test 
```

### Deployment

To deploy the smart contracts first, you must have an RPC url for an Ethereum node and a private key.

A simple way to run a deployment on a local network is to use anvil.

Note that the `SENDER` environmental variable should be set prior to executing that command.  Alternatively, a `MNEMONIC` environmental variable can be set instead of `SENDER`.

The smart-contracts deployment is not in the Makefile.  

To deploy the smart-contracts use this command:

```bash
forge script script/v1/Deployment.s.sol --sig "run(uint256,bytes32,address)" <chain-id> <target-chain-id-bytes> <relayer-public-key> --rpc-url <rpc-url> --broadcast
```

## Contributing

Please refer to the top-level contributing guide for a more detailed description of the required steps.
