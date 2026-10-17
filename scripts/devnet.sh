#!/bin/bash
# usage: devnet.sh start|stop|status
K=${FL_KEYS_DIR:?set FL_KEYS_DIR to your key folder}
N=~/flbsc/net
G=${GETH:-~/flbsc/bin/geth}
start_node() {
  # per-node storage flags: STORE<i> (default archive, like the live validators before 2026-10-12)
  local i=$1 D=$N/node$1 ADDR store
  store=STORE$1; store=${!store:---gcmode archive}
  if [ ! -d $D/geth/chaindata ]; then
    mkdir -p $D
    $G --datadir $D init --state.scheme hash $N/genesis.json > $D/init.log 2>&1 || { tail -20 $D/init.log; exit 1; }
  fi
  ADDR=$(python3 -c "import json;print(json.load(open('$K/val$i-consensus.json'))['address'])")
  FL_PQ_VALIDATOR_KEY=$K/val$i-consensus.json nohup $G --datadir $D --networkid 20261012     --port $((30310+i)) --http --http.addr 127.0.0.1 --http.port $((8544+i)) --http.api eth,net,web3,parlia,admin,txpool,debug     --ws=false --nat extip:127.0.0.1 --mine --miner.etherbase $ADDR --syncmode full $store --state.scheme hash     --rpc.allow-unprotected-txs=false ${BOOT:+--bootnodes $BOOT} --verbosity 3 >> $D/node.log 2>&1 &
}
case "$1" in
start)
  pkill -f "datadir $N/node"; while pgrep -f "datadir $N/node" >/dev/null; do sleep 1; done
  BOOT=""
  for i in 1 2 3; do
    start_node $i
    sleep 4
    if [ -z "$BOOT" ]; then
      BOOT=$(curl -s -X POST -H 'Content-Type: application/json' --data '{"jsonrpc":"2.0","id":1,"method":"admin_nodeInfo","params":[]}' http://127.0.0.1:8545 | python3 -c "import sys,json;print(json.load(sys.stdin)['result']['enode'])")
      echo "bootnode: $BOOT"
    fi
  done
  ;;
restart)
  # restart one node with its storage flags, e.g. STORE3="--gcmode full --history.blocks 600000" devnet.sh restart 3
  # (kill=1 simulates a crash instead of a clean stop)
  i=$2
  if [ "$KILL" = 1 ]; then pkill -9 -f "datadir $N/node$i "; else pkill -f "datadir $N/node$i "; fi
  while pgrep -f "datadir $N/node$i " >/dev/null; do sleep 1; done
  BOOT=$(curl -s -X POST -H 'Content-Type: application/json' --data '{"jsonrpc":"2.0","id":1,"method":"admin_nodeInfo","params":[]}' http://127.0.0.1:8545 | python3 -c "import sys,json;print(json.load(sys.stdin)['result']['enode'])")
  [ "$i" = 1 ] && BOOT=""
  start_node $i; echo "node$i restarted"
  ;;
stop) pkill -f "datadir $N/node"; while pgrep -f "datadir $N/node" >/dev/null; do sleep 1; done; echo stopped ;;
status)
  for i in 1 2 3; do
    curl -s -X POST -H 'Content-Type: application/json' --data '{"jsonrpc":"2.0","id":1,"method":"eth_blockNumber","params":[]}' http://127.0.0.1:$((8544+i)) | python3 -c "import sys,json;print('node$i block',int(json.load(sys.stdin)['result'],16))" 2>/dev/null || echo "node$i down"
    curl -s -X POST -H 'Content-Type: application/json' --data '{"jsonrpc":"2.0","id":1,"method":"net_peerCount","params":[]}' http://127.0.0.1:$((8544+i)) | python3 -c "import sys,json;print('  peers',int(json.load(sys.stdin)['result'],16))" 2>/dev/null
  done
  ;;
esac
