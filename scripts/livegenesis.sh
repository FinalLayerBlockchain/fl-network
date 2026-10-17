#!/bin/bash
export PATH=$HOME/.foundry/bin:$PATH
OUT=${FL_NETWORK_DIR:-.}/genesis.json
python3 ${FL_NETWORK_DIR:-.}/scripts/make_genesis.py ${FL_CONTRACTS_DIR:-../fl-genesis-contracts} ${FL_KEYS_DIR:?set FL_KEYS_DIR to your key folder} ~/flbsc/bin/flpq $OUT 2>&1 | tail -3
rm -rf /tmp/gh; ~/flbsc/bin/geth --datadir /tmp/gh init --state.scheme hash $OUT 2>&1 | grep "Successfully wrote genesis" | grep -o 'hash=0x[0-9a-f]*'; rm -rf /tmp/gh
python3 -c "import json;print('timestamp',int(json.load(open('$OUT'))['timestamp'],16))"
