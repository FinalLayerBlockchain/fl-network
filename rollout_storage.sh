#!/bin/bash
# Storage rollout (2026-10-12).
#   val1: unchanged (archive, full history): public RPC :8545, explorer source, bootnode.
#   val2: --gcmode full, keeps full block history (second full-history copy).
#   val3..5: --gcmode full --history.blocks 600000 (geth minimum; deletes nothing for ~21 days).
#   val2..5: [Eth] TrieTimeout = 2s of block processing, so a crash only rewinds a few
#            thousand blocks (default 10 min ~ 600k empty blocks = the whole pruning window).
# One validator at a time; each must catch up (and seal if active) before the next.
# Re-runnable. Rollback and crash recovery: see the end of this file.
set -uo pipefail
B=/opt/fl-bsc
UNIT=/etc/systemd/system/fl-bsc-val@.service
TS=$(date +%Y%m%d%H%M)
die() { echo "ABORT: $*"; echo "rollback: cp $UNIT.bak-store-$TS $UNIT; for i in 1 2 3 4 5; do cp $B/val\$i.env.bak-store-$TS $B/val\$i.env; cp $B/val\$i.toml.bak-store-$TS $B/val\$i.toml; done; systemctl daemon-reload; systemctl restart fl-bsc-val@<n>"; exit 1; }
num() { local v; v=$("$@" 2>/dev/null) || v=""; [[ "$v" =~ ^[0-9]+$ ]] && echo "$v" || echo 0; }
head_of() { num $B/bin/geth attach --exec eth.blockNumber $B/val$1/geth.ipc; }
store_for() { case $1 in 1) echo "--gcmode archive";; 2) echo "--gcmode full";; *) echo "--gcmode full --history.blocks 600000";; esac; }

# 1. backups
cp $UNIT $UNIT.bak-store-$TS || die "backup unit"
for i in 1 2 3 4 5; do cp $B/val$i.env $B/val$i.env.bak-store-$TS && cp $B/val$i.toml $B/val$i.toml.bak-store-$TS || die "backup val$i"; done

# 2. per-validator settings first (unused until the unit references them)
for i in 1 2 3 4 5; do
  sed -i '/^STORE_FLAGS=/d' $B/val$i.env
  echo "STORE_FLAGS=$(store_for $i)" >> $B/val$i.env
  if [ $i != 1 ] && ! grep -q '^\[Eth\]' $B/val$i.toml; then printf '\n[Eth]\nTrieTimeout = 2000000000\n' >> $B/val$i.toml; fi
done

# 3. unit: hard-coded archive -> per-validator setting (skip if already done)
if grep -q -- '--gcmode archive' $UNIT; then sed -i 's/--gcmode archive/$STORE_FLAGS/' $UNIT; fi
grep -q 'STORE_FLAGS' $UNIT || die "unit does not reference STORE_FLAGS"
systemctl daemon-reload

# 4. rolling restart of 2..5
for i in 2 3 4 5; do
  ETH=$(grep '^ETHERBASE=' $B/val$i.env | cut -d= -f2 | tr -d '"'); ETH=${ETH#0x}
  WANT=$(store_for $i)
  echo "== val$i (0x$ETH) -> $WANT"
  systemctl restart fl-bsc-val@$i
  sleep 10
  PID=$(systemctl show -p MainPID --value fl-bsc-val@$i)
  { systemctl is-active -q fl-bsc-val@$i && [ "$PID" != 0 ]; } || die "val$i not running after restart (journalctl -u fl-bsc-val@$i)"
  ARGS=$(tr '\0' ' ' < /proc/$PID/cmdline)
  echo "$ARGS" | grep -q -- "$WANT " || die "val$i flags missing: $ARGS"
  if [ $i = 2 ] && echo "$ARGS" | grep -q -- "--history.blocks"; then die "val2 must keep full history"; fi
  ok=0
  for t in $(seq 1 40); do
    h1=$(head_of 1); hi=$(head_of $i)
    if [ "$h1" -gt 0 ] && [ "$hi" -gt 0 ] && [ $((h1 - hi)) -le 2 ]; then ok=1; break; fi
    sleep 3
  done
  [ $ok = 1 ] || die "val$i did not catch up (val1=$h1 val$i=$hi)"
  VALS=$($B/bin/geth attach --exec "JSON.stringify(parlia.getValidators())" $B/val1/geth.ipc 2>/dev/null)
  [ -n "$VALS" ] || die "could not read the validator set"
  if echo "$VALS" | grep -qi "$ETH"; then
    start=$(head_of 1); sealed=0
    for t in $(seq 1 30); do
      sleep 3
      n=$(head_of 1)
      for b in $(seq $((start + 1)) $n); do
        $B/bin/geth attach --exec "eth.getBlock($b).miner" $B/val1/geth.ipc 2>/dev/null | grep -qi "$ETH" && { sealed=$b; break; }
      done
      [ $sealed != 0 ] && break
    done
    [ $sealed != 0 ] || die "val$i is in the active set but sealed nothing for 90s"
    echo "val$i ok: in sync, sealed block $sealed"
  else
    echo "val$i ok: in sync (not in the active set this epoch)"
  fi
done
echo "rollout done"

# Rollback (all validators back to archive):
#   cp $UNIT.bak-store-<TS> $UNIT; for i in 1 2 3 4 5; do cp $B/val$i.env.bak-store-<TS> $B/val$i.env;
#   cp $B/val$i.toml.bak-store-<TS> $B/val$i.toml; done; systemctl daemon-reload;
#   then restart val2..5 one at a time.
# Recovery if a pruned validator crash-loops ("Failed to truncate head block"):
#   systemctl stop fl-bsc-val@N; cd /opt/fl-bsc/valN/geth; keep nodekey; rm -rf chaindata triedb;
#   /opt/fl-bsc/bin/geth --datadir /opt/fl-bsc/valN init --state.scheme hash /opt/fl-bsc/genesis.json;
#   systemctl start fl-bsc-val@N   (full-syncs from val1/val2, which keep full history)
