# RWA Launcher — Live Demo

A shared, on-chain demo of the [RWA Launcher](../docs/RWALauncherSpec.md): one auction is created at deploy
time, then **anyone with a wallet can faucet test dUSDC and bid a discount**. The settlement price moves as
bids come in; once the auction ends, anyone can settle it — routing proceeds to the issuer and seeding a
multi-range Uniswap v4 LP position.

## Contracts (`contracts/`)

- **`DemoERC20.sol`** — mintable ERC20. `faucet()` is open to anyone (demo USDC); `mint()` is restricted to
  the owner and authorized minters (the per-side token minters for dQQQ / dANT).
- **`DemoController.sol`** — thin front end the UI calls: `bid(auction, amount, maxPrice)` wraps the Permit2
  flow so a bidder only needs to approve dUSDC to the controller. Demo defaults only.
- The auction is a real `RWALauncher` + `ContinuousClearingAuction`. On chains that enforce EIP-170 the
  launcher is deployed **directly** (the `RWALauncherFactory` embeds the launcher's creation code and is
  ~252 bytes over the limit — fine to keep for local use, but a production factory would use a CREATE2
  init-code-hash pattern).

## Run locally

Requirements: [Foundry](https://book.getfoundry.sh) (`anvil`, `cast`, `forge`), `python3`, and a wallet
(e.g. MetaMask) you can point at `localhost:8545`.

```bash
./demo/run.sh
```

Starts anvil, installs Permit2, deploys + starts a shared auction (writing `demo/web/addresses.json`), and
serves the UI at <http://localhost:8080>. Connect MetaMask to `localhost:8545` (chain id 31337).

## Deploy to Sepolia (public, shared)

Permit2 is already at its canonical address on Sepolia, and the demo deploys its own PoolManager + tokens,
so it is self-contained.

1. Fund the deployer in `demo/.deployer.env` (gitignored) with Sepolia ETH (~0.3 ETH is plenty).
2. Deploy + start the auction:

   ```bash
   export $(grep -v '^#' demo/.deployer.env | xargs)        # loads PRIVATE_KEY
   export SEPOLIA_RPC=https://ethereum-sepolia-rpc.publicnode.com   # or your own
   DURATION=600 forge script script/DemoDeployLive.s.sol --rpc-url "$SEPOLIA_RPC" --broadcast
   ```

   `DURATION` is the auction length in blocks (~12s each on Sepolia; 600 ≈ 2h). `DEPOSIT`, `MAX_DISCOUNT_BPS`,
   and `REQUIRED` are also overridable via env.

3. Host `demo/web/` on any static host (GitHub Pages, `npx serve demo/web`, etc.) and share the URL. Visitors
   connect MetaMask (Sepolia), click **Faucet**, set an amount + discount, and **Place bid**.

## How it behaves

- **Settlement price** holds at the floor (max discount) until cumulative bids exceed the deposit, then rises
  toward 0 bps as more demand fills — the white marker on the chart reads the live on-chain clearing price.
- **Ending**: the auction ends when its end block is reached (no on-demand mining on a real chain). After that
  the **Settle** button (callable by anyone) runs `build()` — minting dQQQ + dAnthropic from the deposit and
  seeding the ±5/10/50/100 bp v4 position.

## Notes

- Test/demo only. Tokens are valueless; prices are placeholders (1 dQQQ = 500 dUSDC, 1 dAnthropic = 150 dUSDC).
- Re-running the deploy starts a fresh auction and rewrites `addresses.json`; reload the page.
