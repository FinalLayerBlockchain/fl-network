#!/usr/bin/env python3
"""Build the Final Layer genesis.

Run inside WSL from any directory:
  python3 make_genesis.py <genesis-contract-repo> <keys-dir> <flpq-binary> <out-genesis.json>

Steps: set Final Layer parameters in the system contracts, fetch the pinned
OpenZeppelin packages (sha512 checked), compile with forge, render the genesis.
"""
import base64
import hashlib
import json
import os
import re
import subprocess
import sys
import tarfile
import time
import urllib.request

repo, keys_dir, flpq, out_path = sys.argv[1:5]
CHAIN_ID = 20261012
TOTAL_SUPPLY_WEI = 5_000_000_000 * 10**18

OZ = [
    ("contracts", "https://registry.npmjs.org/@openzeppelin/contracts/-/contracts-4.9.6.tgz",
     "xSmezSupL+y9VkHZJGDoCBpmnB2ogM13ccaYDWqJTfS3dbuHkgjuwDFUmaFauBCboQMGB/S5UqUl2y54X99BmA=="),
    ("contracts-upgradeable", "https://registry.npmjs.org/@openzeppelin/contracts-upgradeable/-/contracts-upgradeable-4.9.6.tgz",
     "m4iHazOsOCv1DgM7eD7GupTJ+NFVujRZt1wzddDPSVGpWdKq1SKkla5htKG7+IS4d2XOCtzkUNwRZ7Vq5aEUMA=="),
]


def addr_of(name):
    with open(os.path.join(keys_dir, name + ".json")) as f:
        return json.load(f)["address"]


def edit(path, fn):
    p = os.path.join(repo, "contracts", path)
    s = open(p, encoding="utf-8").read()
    s2 = fn(s)
    open(p, "w", encoding="utf-8", newline="\n").write(s2)


def sub1(pattern, repl, s):
    s2, n = re.subn(pattern, repl, s, count=1)
    if n != 1:
        raise SystemExit("pattern not found: " + pattern)
    return s2


# ---------------------------------------------------------------- dependencies
for name, url, integrity in OZ:
    dest = os.path.join(repo, "node_modules", "@openzeppelin", name)
    if os.path.isdir(dest):
        continue
    data = urllib.request.urlopen(url).read()
    got = base64.b64encode(hashlib.sha512(data).digest()).decode()
    if got != integrity:
        raise SystemExit("integrity mismatch for " + url)
    tmp = "/tmp/" + name + ".tgz"
    open(tmp, "wb").write(data)
    os.makedirs(dest, exist_ok=True)
    with tarfile.open(tmp) as t:
        for m in t.getmembers():
            m.name = m.name.split("/", 1)[1] if "/" in m.name else m.name
            if m.name and not m.name.startswith("/") and ".." not in m.name:
                t.extract(m, dest)
    print("installed @openzeppelin/" + name)

# ---------------------------------------------------------------- parameters
treasury = addr_of("treasury")
consensus = [addr_of("val%d-consensus" % i) for i in (1, 2, 3)]
gv = subprocess.check_output([flpq, "genesis-validators"] + consensus).decode()
init_bytes = re.search(r"INIT_VALIDATORSET_BYTES=([0-9a-f]+)", gv).group(1)
extra_data = re.search(r"EXTRA_DATA=(0x[0-9a-f]+)", gv).group(1)


def validator_set(s):
    s = sub1(r'bytes public constant INIT_VALIDATORSET_BYTES =[^;]*;',
             'bytes public constant INIT_VALIDATORSET_BYTES = hex"%s";' % init_bytes, s)
    if "validatorExtraSet[i].voteAddress=validatorSetPkg.voteAddrs[i];" not in s:
        # Same as the upstream "dev" generator: record the identifiers at init so
        # getMiningValidators has an extra entry for every genesis validator.
        s = sub1(r"(\n\s*)(for \(uint256 i; i < validatorSetPkg\.validatorSet\.length; \+\+i\) \{)",
                 r"\1ValidatorExtra memory validatorExtra;\1\2", s)
        s = sub1(r"(\n(\s*)currentValidatorSet\.push\(validatorSetPkg\.validatorSet\[i\]\);)",
                 r"\1\n\2validatorExtraSet.push(validatorExtra);\n\2validatorExtraSet[i].voteAddress=validatorSetPkg.voteAddrs[i];", s)
    return s


def system_reward(s):
    if "operators[VALIDATOR_CONTRACT_ADDR] = true;" in s:
        return s
    s = sub1(r"(\n(\s*)numOperator = 2;)",
             r"\n\2operators[VALIDATOR_CONTRACT_ADDR] = true;\n\2operators[SLASH_CONTRACT_ADDR] = true;\n\2numOperator = 4;", s)
    return s


# No protector: nobody can pause staking or governance or blacklist anyone.
# Governance can still appoint one by an on-chain vote (updateParam
# "stakeHubProtector" / "governorProtector").
NO_PROTECTOR = "0x000000000000000000000000000000000000dEaD"


def protector(s):
    return sub1(r"__Protectable_init_unchained\([^)]*\);", "__Protectable_init_unchained(%s);" % NO_PROTECTOR, s)


edit("BSCValidatorSet.sol", validator_set)
edit("SystemReward.sol", system_reward)
edit("StakeHub.sol", protector)
edit("BSCGovernor.sol", protector)
edit("TokenRecoverPortal.sol", protector)

# ---------------------------------------------------------------- compile
subprocess.check_call(["forge", "build", "--skip", "test", "--skip", "script"], cwd=repo)


def runtime(contract):
    with open(os.path.join(repo, "out", contract + ".sol", contract + ".json")) as f:
        code = json.load(f)["deployedBytecode"]["object"]
    return code if code.startswith("0x") else "0x" + code


codes = {
    "validatorContract": runtime("BSCValidatorSet"),
    "systemRewardContract": runtime("SystemReward"),
    "slashContract": runtime("SlashIndicator"),
    "tendermintLightClient": runtime("TendermintLightClient"),
    "tokenHub": runtime("TokenHub"),
    "relayerHub": runtime("RelayerHub"),
    "relayerIncentivize": runtime("RelayerIncentivize"),
    "govHub": runtime("GovHub"),
    "tokenManager": runtime("TokenManager"),
    "crossChain": runtime("CrossChain"),
    "staking": runtime("Staking"),
    "stakeHub": runtime("StakeHub"),
    "stakeCredit": runtime("StakeCredit"),
    "governor": runtime("BSCGovernor"),
    "govToken": runtime("GovToken"),
    "timelock": runtime("BSCTimelock"),
    "tokenRecoverPortal": runtime("TokenRecoverPortal"),
}

# ---------------------------------------------------------------- render
tpl = open(os.path.join(repo, "genesis-template.json"), encoding="utf-8").read()
tpl = re.sub(r"\{% for v in initHolders %\}.*?\{% endfor %\}", "", tpl, flags=re.S)
values = dict(codes)
values["chainId"] = str(CHAIN_ID)
values["extraData"] = extra_data
values["initLockedBNBOnTokenHub"] = "0x0"
for k, v in values.items():
    tpl = tpl.replace("{{%s}}" % k, v)
if "{{" in tpl or "{%" in tpl:
    raise SystemExit("unrendered placeholders remain")
tpl = re.sub(r",(\s*[}\]])", r"\1", tpl)  # drop trailing commas left by the template
g = json.loads(tpl)

g["timestamp"] = hex(int(time.time()))
# Every scheduled fork with blob parameters needs an entry (blobs are unused on
# Final Layer since only PQ transactions are accepted).
bs = g["config"].setdefault("blobSchedule", {})
for fork in ("cancun", "prague", "osaka"):
    bs.setdefault(fork, {"target": 3, "max": 6, "baseFeeUpdateFraction": 3338477})
alloc = g["alloc"]
for a, acc in alloc.items():
    if acc.get("balance") not in ("0x0", "0x00", "0"):
        raise SystemExit("unexpected genesis balance at " + a)
alloc[treasury.lower().replace("0x", "")] = {"balance": hex(TOTAL_SUPPLY_WEI)}
# Final Layer post-quantum key registry (rotation state). Nonce 1 and an INVALID
# opcode keep it from ever being treated as an empty account.
alloc["0000000000000000000000000000000000005051"] = {"balance": "0x0", "nonce": "0x1", "code": "0xfe"}

total = sum(int(acc.get("balance", "0x0"), 16) for acc in alloc.values())
assert total == TOTAL_SUPPLY_WEI, total

with open(out_path, "w") as f:
    json.dump(g, f, indent=2)
print("genesis written:", out_path)
print("chainId", CHAIN_ID, "treasury", treasury, "supply 5,000,000,000 FL")
print("validators", consensus)
