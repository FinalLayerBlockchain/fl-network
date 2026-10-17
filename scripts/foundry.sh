#!/bin/bash
set -e
if [ ! -x ~/.foundry/bin/forge ]; then
  curl -sL https://foundry.paradigm.xyz | bash >/dev/null 2>&1
  ~/.foundry/bin/foundryup >/tmp/foundryup.log 2>&1 || tail -20 /tmp/foundryup.log
fi
~/.foundry/bin/forge --version
