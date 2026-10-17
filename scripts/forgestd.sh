#!/bin/bash
cd ${FL_CONTRACTS_DIR:-../fl-genesis-contracts}
rm -rf lib/forge-std; mkdir -p lib/forge-std
curl -sL https://github.com/foundry-rs/forge-std/archive/refs/tags/v1.7.3.tar.gz | tar xz -C lib/forge-std --strip-components=1
mkdir -p lib/forge-std/lib/ds-test
curl -sL https://github.com/dapphub/ds-test/archive/e282159d5170298eb2455a6c05280ab5a73a4ef0.tar.gz | tar xz -C lib/forge-std/lib/ds-test --strip-components=1
ls lib/forge-std/src/Test.sol lib/forge-std/lib/ds-test/src/test.sol
