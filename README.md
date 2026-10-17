# Final Layer network (fl-network)

Genesis, deployment and operations files for Final Layer, the post-quantum EVM Layer 1 built on
the [BNB Smart Chain client](https://github.com/bnb-chain/bsc). The node is
[fl-node](https://github.com/FinalLayerBlockchain/fl-node); the system contracts are
[fl-genesis-contracts](https://github.com/FinalLayerBlockchain/fl-genesis-contracts).

Final Layer previously ran on a java-tron based codebase. That network is retired; everything
here is for the current bsc-geth based chain.

## Mainnet

| Parameter | Value |
| --- | --- |
| Chain ID | `20261012` |
| Genesis | [`genesis.json`](genesis.json) (identical to `docker/genesis.json`) |
| Public RPC | `http://207.148.16.239:8545` |
| P2P port | `30311` |
| Block time | 3 s |

## Layout

| Path | Contents |
| --- | --- |
| `genesis.json` | Live mainnet genesis |
| `docker/` | Node image: `Dockerfile`, `entrypoint.sh` (joins mainnet through the bootnode, override with `FL_BOOTNODE`). Copy `geth` and `flpq` built from fl-node next to the Dockerfile |
| `fl-bsc-val@.service` | systemd unit for validator instances |
| `fl-explorer.service` | systemd unit for the explorer |
| `setup-server.sh` | Idempotent validator host setup |
| `rollout_storage.sh` | Storage rollout helper |
| `scripts/make_genesis.py` | Builds `genesis.json` from compiled fl-genesis-contracts and the validator key files |
| `scripts/genesis.sh`, `livegenesis.sh` | Genesis generation wrappers (`livegenesis.sh` also prints the genesis hash) |
| `scripts/build.sh` | Builds the node |
| `scripts/devnet.sh` | Local multi-validator devnet: `start`, `stop`, `status` |
| `scripts/e2e.sh` | End-to-end checks against a running node |
| `scripts/keys.sh` | Devnet key generation with `flpq` |
| `scripts/forge*.sh`, `foundry.sh` | Contract test helpers |
| `scripts/producers.sh`, `sigs.sh`, `inflation_probe.sh`, `wait_inflation.sh` | Operational probes: recent block producers, StakeHub state, daily inflation payout |

## Configuration

No keys or credentials are in this repository. Scripts read their inputs from the environment:

| Variable | Meaning |
| --- | --- |
| `FL_NODE_DIR` | fl-node checkout (default `../fl-node`) |
| `FL_CONTRACTS_DIR` | fl-genesis-contracts checkout (default `../fl-genesis-contracts`) |
| `FL_NETWORK_DIR` | this checkout (default `.`) |
| `FL_KEYS_DIR` | Folder with validator and operator key files (never commit these) |
| `FL_E2E_ECKEY` | Funded devnet-only key used by `e2e.sh` to confirm classical transactions are rejected |
| `FL_BOOTNODE` | Bootnode enode for the Docker image |

## Run a node with Docker

```shell
cp /path/to/fl-node/build/bin/geth /path/to/fl-node/flpq docker/
docker build -t finallayer-node docker
docker run -d -v fl-data:/data -p 8545:8545 -p 30311:30311 -p 30311:30311/udp finallayer-node
```

See [SECURITY.md](SECURITY.md) to report a vulnerability.
