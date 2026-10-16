# Ethereum bridge smart contracts

The Ethereum smart-contracts define an interface for relayers and end users to deposit and withdraw ether using canonical bridge.

Specifically, relayers interact with a `Mailbox` contract using an EIP-6170 interface.  End users interact with the `EtherBridge` contracts to deposit and withdraw ether.

The `Router` and `Registry` smart contracts are used to enable communications between the `Mailbox` and `EtherBridge`.

## Organization

At a high-level the project has a src, test, script and specs folder.

The `specs` folder contains a high-level description of the intended features and behavior of each smart-contract. It should define how the `test` and `src` folders are implemented.

The `script` folder contains local, testnet and mainnet deployment scripts.

## Usage

The smart-contracts are built, deployed and tested using [Foundry](https://github.com/foundry-rs/foundry). 

Please consult the official [foundry documentation](https://book.getfoundry.sh/) for a detailed explanation. 

Our mono-repo has a Makefile to simplify building the project

### Dependencies

You must have forge nightly installed. 

To install the library dependencies use the makefile at the root and call:

```bash
make install-forge-deps
```

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
export SENDER=<key>
forge script script/v1/Deployment.s.sol --sig "run(uint256,bytes32,address)" <chain-id> <target-chain-id-bytes> <relayer-public-key> --rpc-url <rpc-url> --broadcast
```
