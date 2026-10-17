#!/bin/bash
export PATH=$HOME/.foundry/bin:$PATH
cd ${FL_CONTRACTS_DIR:-../fl-genesis-contracts}
forge build --skip test --skip script 2>&1 | grep -B2 -A12 -i "error" | head -60
