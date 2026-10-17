#!/bin/bash
# Final Layer (PQ BSC) validator box setup. Idempotent.
set -e
B=/opt/fl-bsc
mkdir -p $B/bin $B/keys
chmod 700 $B/keys
install -m 755 /root/fl-upload/geth $B/bin/geth
install -m 755 /root/fl-upload/flpq $B/bin/flpq
cp /root/fl-upload/genesis.json $B/genesis.json
for i in 1 2 3; do install -m 600 /root/fl-upload/val$i-consensus.json $B/keys/; done
for i in 1 2 3; do
  D=$B/val$i
  if [ ! -d $D/geth/chaindata ]; then
    mkdir -p $D
    $B/bin/geth --datadir $D init --state.scheme hash $B/genesis.json > $D/init.log 2>&1
  fi
done
# fixed node key for val1 so the public bootnode enode never changes
[ -f $B/val1/geth/nodekey ] || openssl rand -hex 32 | tr -d '\n' > $B/val1/geth/nodekey
