#!/usr/bin/env bash
# One-command LOCAL demo: anvil + Permit2 + deploy a shared auction + serve the UI.
# (For a public Sepolia demo see demo/README.md.)
set -euo pipefail
cd "$(dirname "$0")/.."

RPC=http://127.0.0.1:8545
PERMIT2=0x000000000022D473030F116dDEE9F6B43aC78BA3
# anvil default account 0 acts as the issuer locally.
export PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

if ! cast block-number --rpc-url "$RPC" >/dev/null 2>&1; then
  echo "▸ starting anvil…"; anvil --silent &
  for _ in $(seq 1 40); do cast block-number --rpc-url "$RPC" >/dev/null 2>&1 && break; sleep 0.3; done
fi

# Permit2 must exist at its canonical address (the CCA pulls bid funds through it). On Sepolia it already does.
echo "▸ installing Permit2…"
CODE=0x$(grep -oE 'hex"[0-9a-f]+"' lib/permit2/test/utils/DeployPermit2.sol | head -1 | sed 's/hex"//;s/"//')
cast rpc anvil_setCode "$PERMIT2" "$CODE" --rpc-url "$RPC" >/dev/null

echo "▸ deploying + starting a shared auction…"
DURATION=${DURATION:-600} forge script script/DemoDeployLive.s.sol --rpc-url "$RPC" --broadcast >/dev/null
echo "▸ deployed — addresses in demo/web/addresses.json"

echo "▸ serving UI at http://localhost:8080  (connect MetaMask to localhost:8545, chain 31337)"
cd demo/web && python3 -m http.server 8080
