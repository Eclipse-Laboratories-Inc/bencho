# Ethereum Bridge Smart Contracts

This repository contains the Ethereum smart contracts designed for facilitating ether transactions between the Ethereum blockchain and the Eclipse rollup. These contracts provide interfaces for secure interactions through relayers and support upgrades and access control.

## Introduction

### Purpose
The Ethereum Bridge Smart Contracts enable secure and verifiable transfer of ether between Ethereum and the Eclipse rollup.

### Key Features
- Cross-chain Ether transfers
- Role-based access control
- Upgradeable Treasury contract (UUPS pattern)
- Immutable CanonicalBridge contract
- Pausable functionality
- Fraud window for withdrawal processing
- Emergency withdrawal mechanism

### Security Assurances
- Multiple roles for segregation of duties
- Treasury safeguards with controlled access
- CanonicalBridge safeguards including minimum deposit amounts and fraud windows
- Controlled upgrade process

## Project Structure

### Contract Versions
- src/v0: Previous version of contracts
- src/v1: Current version of contracts

### Directory Layout
- src: Source code for contracts
- test: Unit tests and coverage reports

## Components

### Treasury
Acts as a secure vault for ether deposits, with controlled deposit and withdrawal mechanisms.

### CanonicalBridge
Handles the deposit and withdrawal of ether, interfacing directly with end users. It's immutable, providing a fixed and auditable interface. Can only be replaced via role grants in the Treasury.

### Upgrader0to1
Facilitates the upgrade process from v0 to v1 contracts, managing role assignments and contract interactions.

## Security and Access Control

- Role-based access control for critical functions
- Immutable CanonicalBridge requires explicit Treasury authorization for withdrawals
- Fraud window allows for challenge period on withdrawals
- Emergency functions for critical situations

## Development

### Prerequisites
- [Foundry](https://github.com/foundry-rs/foundry)

### Setup
Install dependencies:

```bash
make install-forge-deps
```

### Build

```bash
make forge-build
```

## Testing

### Running Unit Tests

```bash
forge clean
forge build
forge test
```

### Generating Coverage Report
Due to incompatibility with OpenZeppelin's Upgrades.sol, coverage excludes the Upgrader0to1 contract.

Run the coverage script:

```bash
./coverage.sh
```

Or manually:

```bash
forge coverage --report lcov --report-file ./test/coverage/lcov.info --no-match-test test_upgrader0To1
genhtml -o ./test/coverage_report ./test/coverage/lcov.info
```

View the HTML report in `./test/coverage_report/index.html`.

## Deployment Options

### Direct Deployment of v1 Contracts (Testing)
1. Deploy Treasury (implementation and UUPS proxy)
2. Deploy CanonicalBridge
3. Configure roles and permissions

### Upgrade Process Deployment (v0 to v1)
1. Deploy v0 contracts
2. Deploy v1 Treasury implementation
3. Deploy Upgrader0to1
4. Pause v0 contracts and transfer ownership
5. Execute upgrade via Upgrader0to1
6. Verify post-upgrade configuration

## Mainnet Upgrade Process

1. Pre-upgrade Steps:
   - Pause existing contracts
   - Grant necessary ownership to the upgrader
2. Deploy Treasury implementation
3. Upgrade Execution:
   - Multisig initiates upgrade through Upgrader0to1
4. Post-upgrade Verification:
   - Confirm correct deployment and role assignments

## Known Issues and Limitations

- Coverage report incorrectly reports certain CanonicalBridge lines have not been tested
- Coverage report does not include Upgrader0to1 which is covered in unit tests due to tool incompatibility