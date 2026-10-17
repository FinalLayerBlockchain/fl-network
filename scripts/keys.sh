#!/bin/bash
set -e
D=${FL_KEYS_DIR:?set FL_KEYS_DIR to your key folder}
mkdir -p $D
cd $D
for n in treasury val1-consensus val2-consensus val3-consensus val1-operator val2-operator val3-operator; do
  [ -f $n.json ] || echo "$n $(~/flbsc/bin/flpq keygen $n.json)"
done
for n in *.json; do echo "$n $(~/flbsc/bin/flpq address $n)"; done
