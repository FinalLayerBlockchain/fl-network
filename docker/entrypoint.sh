#!/bin/sh
# Full/RPC node by default. Extra geth flags can be appended to `docker run`.
# Validator: mount the key and set FL_PQ_VALIDATOR_KEY=/keys/<file>.json and pass
#   --mine --miner.etherbase <consensus address>
set -e
BOOTNODE=${FL_BOOTNODE:-enode://d0041c941958a3038fdd775f18ef64cf51e45cdac5c2e812b34b239c4a8c6d9a28cf14588e694ad458bf2204e4b6e8dd6adfb187b6456f530a7b310dd2fcd3b0@207.148.16.239:30311}
if [ ! -d /data/geth/chaindata ]; then
  geth --datadir /data init --state.scheme hash /finallayer/genesis.json
fi
exec geth --datadir /data --networkid 20261012 --port 30311 --bootnodes "$BOOTNODE" \
  --http --http.addr 0.0.0.0 --http.port 8545 --http.vhosts '*' --http.api eth,net,web3,txpool \
  --syncmode full --state.scheme hash "$@"
