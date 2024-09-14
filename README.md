## Arcade

Arcade is an asynchronous player versus puzzle gaming framework for the EVM. Arcade also has supports zkSync compatibility.

## Usage

To build for generic EVM, use `forge`. To build for zkSync, use `npx hardhat`.

### Build

```shell
$ forge build # for EVM
$ npx hardhat compile --network abstractTestnet # for zkSync
```

### Test

```shell
$ forge test
```

### Format

```shell
$ forge fmt
```

### Gas Snapshots

```shell
$ forge snapshot
```

### Anvil

```shell
$ anvil
```

### Deploy
EVM, create a `.env` file with the following
```dotenv
DEPLOYER_PRIVATE_KEY=<deployer_private_key>
PROTOCOL_OWNER=<protocol_owner_public_key>
```
and then run
```shell
$ forge script --rpc-url <rpc_url> ./script/Deploy.s.sol --force --broadcast
```

For zkSync, set environment variables
```shell
$ npx hardhat vars set DEPLOYER_PRIVATE_KEY
$ npx hardhat vars set PROTOCOL_OWNER
```
and then run
```shell
$ npx hardhat deploy-zksync --script deploy.ts
```

### Cast

```shell
$ cast <subcommand>
```

### Help

```shell
$ forge --help
$ anvil --help
$ cast --help
```
