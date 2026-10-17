#!/bin/bash
set -e
export PATH=$HOME/.foundry/bin:$PATH
mkdir -p ~/flbsc/net
python3 ${FL_NETWORK_DIR:-.}/scripts/make_genesis.py \
  ${FL_CONTRACTS_DIR:-../fl-genesis-contracts} \
  ${FL_KEYS_DIR:?set FL_KEYS_DIR to your key folder} ~/flbsc/bin/flpq ~/flbsc/net/genesis.json 2>&1 | grep -v "^Compiling\|^Solc\|^Warning\|^ *-->\|^ *|" | tail -25
