#!/bin/bash
# usage: build.sh <go args...>   (runs in the bsc source tree)
cd ${FL_NODE_DIR:-../fl-node} || exit 1
export GOFLAGS=-buildvcs=false
"$@"
