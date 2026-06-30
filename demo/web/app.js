import {
  createPublicClient, createWalletClient, custom, http, defineChain, parseAbi, parseAbiItem, formatUnits
} from 'https://esm.sh/viem@2.21.55';
import { sepolia } from 'https://esm.sh/viem@2.21.55/chains';

const anvil = defineChain({
  id: 31337, name: 'anvil', nativeCurrency: { name: 'Ether', symbol: 'ETH', decimals: 18 },
  rpcUrls: { default: { http: ['http://127.0.0.1:8545'] } },
});
const READ_RPC = { 11155111: 'https://sepolia.gateway.tenderly.co', 31337: 'http://127.0.0.1:8545' };
const CHAINS = { 11155111: sepolia, 31337: anvil };

const erc20 = parseAbi([
  'function faucet()', 'function approve(address,uint256) returns (bool)',
  'function balanceOf(address) view returns (uint256)', 'function allowance(address,address) view returns (uint256)',
]);
const registryAbi = parseAbi([
  'function latest() view returns (address)', 'function count() view returns (uint256)',
  'function createAndRegister() returns (address)', 'function DEPOSIT() view returns (uint128)',
]);
const padAbi = parseAbi([
  'function bid(uint128 amount, uint16 discount)', 'function end()', 'function unwind()',
  'function redeem(uint256 shares) returns (uint256, uint256)',
  'function clearingDiscount() view returns (uint16)', 'function DEPOSIT() view returns (uint128)',
  'function ended() view returns (bool)', 'function unwound() view returns (bool)',
  'function proceeds() view returns (uint256)', 'function SHARE() view returns (address)',
  'function poolId() view returns (bytes32)',
]);
const bidEvent = parseAbiItem('event BidPlaced(address indexed bidder, uint128 amount, uint16 discount)');
const MAX_UINT = (1n << 256n) - 1n;
const ONE = 10n ** 18n;

let cfg, chain, publicClient, walletClient, account = null;
let registryAddr = null, lp = null, shareAddr = null, currentPoolId = null;
let depositUsd = 0, maxDiscount = 100, isEnded = false, isUnwound = false, myShares = 0n;

const $ = (id) => document.getElementById(id);
const fmt = (n, d = 0) => Number(n).toLocaleString('en-US', { maximumFractionDigits: d });
const short = (a) => a.slice(0, 6) + '…' + a.slice(-4);
function log(m, c = '') { const e = $('log'); e.innerHTML += `<div class="${c}">${m}</div>`; e.scrollTop = e.scrollHeight; }

async function send(addr, abi, fn, args = []) {
  const { request } = await publicClient.simulateContract({ account, address: addr, abi, functionName: fn, args });
  const hash = await walletClient.writeContract(request);
  await publicClient.waitForTransactionReceipt({ hash });
}

async function connect() {
  if (!window.ethereum) { log('✗ no wallet found — install MetaMask', 'err'); return; }
  const [addr] = await window.ethereum.request({ method: 'eth_requestAccounts' });
  const wid = await window.ethereum.request({ method: 'eth_chainId' });
  if (parseInt(wid, 16) !== cfg.chainId) {
    try { await window.ethereum.request({ method: 'wallet_switchEthereumChain', params: [{ chainId: '0x' + cfg.chainId.toString(16) }] }); }
    catch { log(`✗ switch your wallet to chain ${cfg.chainId}`, 'err'); return; }
  }
  account = addr;
  walletClient = createWalletClient({ account: addr, chain, transport: custom(window.ethereum) });
  $('me').textContent = short(addr); $('connect').textContent = short(addr);
  refresh();
  log('✓ connected ' + short(addr), 'ok');
}

async function faucet() {
  try { log('faucet…'); await send(cfg.usdc, erc20, 'faucet'); log('✓ faucet', 'ok'); refresh(); }
  catch (e) { log('✗ ' + (e.shortMessage || e.message), 'err'); }
}

// Point the client at the latest registered auction; reset local state if it changed.
async function syncAuction() {
  const latest = await publicClient.readContract({ address: registryAddr, abi: registryAbi, functionName: 'latest' });
  const count = await publicClient.readContract({ address: registryAddr, abi: registryAbi, functionName: 'count' });
  $('i-index').textContent = count.toString();
  if (latest === '0x0000000000000000000000000000000000000000') { lp = null; return; }
  if (latest !== lp) {
    lp = latest;
    shareAddr = await publicClient.readContract({ address: lp, abi: padAbi, functionName: 'SHARE' });
    currentPoolId = await publicClient.readContract({ address: lp, abi: padAbi, functionName: 'poolId' });
    const dep = await publicClient.readContract({ address: lp, abi: padAbi, functionName: 'DEPOSIT' });
    depositUsd = Number(formatUnits(dep, 18));
    $('i-deposit').textContent = fmt(depositUsd, 0);
    $('i-auc').textContent = short(lp);
    $('positions-card').style.display = 'none';
    $('settle-note').textContent = ''; $('redeem-note').style.display = 'none';
  }
}

async function reset() {
  if (!account) return;
  $('reset').disabled = true;
  try {
    const dep = await publicClient.readContract({ address: registryAddr, abi: registryAbi, functionName: 'DEPOSIT' });
    const bal = await publicClient.readContract({ address: cfg.usdc, abi: erc20, functionName: 'balanceOf', args: [account] });
    if (bal < dep) { log('faucet dUSDC for the deposit…'); await send(cfg.usdc, erc20, 'faucet'); }
    const allow = await publicClient.readContract({ address: cfg.usdc, abi: erc20, functionName: 'allowance', args: [account, registryAddr] });
    if (allow < dep) { log('approve registry for the deposit…'); await send(cfg.usdc, erc20, 'approve', [registryAddr, MAX_UINT]); }
    log('creating a new auction for everyone…');
    await send(registryAddr, registryAbi, 'createAndRegister');
    log('✓ new auction created & registered — all clients will switch to it', 'ok');
    await refresh();
  } catch (e) { log('✗ ' + (e.shortMessage || e.message), 'err'); refresh(); }
}

async function placeBid() {
  if (!account || !lp) return;
  const btn = $('bid'); btn.disabled = true;
  try {
    const amount = Number($('bidAmount').value), discount = Number($('bidDiscount').value);
    if (!(amount > 0)) { log('✗ enter an amount > 0', 'err'); return; }
    if (discount < 0 || discount > maxDiscount) { log(`✗ discount must be 0–${maxDiscount} bps`, 'err'); return; }
    const amt = BigInt(Math.floor(amount)) * ONE;
    const allow = await publicClient.readContract({ address: cfg.usdc, abi: erc20, functionName: 'allowance', args: [account, lp] });
    if (allow < amt) { log('approving dUSDC (one time)…'); await send(cfg.usdc, erc20, 'approve', [lp, MAX_UINT]); }
    log(`bid ${amount} dUSDC @ ${discount}bp…`);
    await send(lp, padAbi, 'bid', [amt, discount]);
    log('✓ bid placed', 'ok'); await refresh();
  } catch (e) { log('✗ ' + (e.shortMessage || e.message), 'err'); }
  finally { btn.disabled = isEnded; }
}

async function endAuction() {
  if (!account || !lp) return;
  $('end').disabled = true;
  try {
    log('ending auction (anyone can) — clearing + building position…');
    await send(lp, padAbi, 'end');
    const proceeds = await publicClient.readContract({ address: lp, abi: padAbi, functionName: 'proceeds' });
    log('✓ ended — proceeds to issuer: ' + fmt(formatUnits(proceeds, 18), 2) + ' dUSDC', 'ok');
    showPositions(proceeds); await refresh();
  } catch (e) { log('✗ ' + (e.shortMessage || e.message), 'err'); refresh(); }
}

async function unwind() {
  if (!account || !lp) return;
  $('unwind').disabled = true;
  try {
    log('ending lockup — withdrawing liquidity (anyone can)…');
    await send(lp, padAbi, 'unwind');
    log('✓ lockup ended — holders can now redeem', 'ok'); await refresh();
  } catch (e) { log('✗ ' + (e.shortMessage || e.message), 'err'); refresh(); }
}

async function redeem() {
  if (!account || !lp || myShares === 0n) return;
  $('redeem').disabled = true;
  try {
    log('redeeming ' + fmt(formatUnits(myShares, 18), 0) + ' shares…');
    await send(lp, padAbi, 'redeem', [myShares]);
    log('✓ redeemed — pro-rata dQQQ + dANT sent to you', 'ok');
    $('redeem-note').style.display = 'block';
    $('redeem-note').textContent = 'Redeemed. Your shares were burned and your pro-rata dQQQ + dANT were sent to your wallet.';
    await refresh();
  } catch (e) { log('✗ ' + (e.shortMessage || e.message), 'err'); refresh(); }
}

function uniswapPoolUrl() {
  if (cfg.chainId !== 11155111 || !currentPoolId) return null;
  return `https://app.uniswap.org/explore/pools/ethereum_sepolia/${currentPoolId}`;
}

function showPositions(proceeds) {
  const half = depositUsd / 2;
  const tr = [['±3%', 10], ['±13%', 20], ['±62%', 30], ['±232%', 40]].map(([w, p]) =>
    `<div class="kv"><span>${w} tranche (${p}%)</span><span><b>${fmt(half * p / 100, 0)}</b> dUSDC/side</span></div>`).join('');
  $('settle-note').textContent = `Settled. Proceeds ${fmt(formatUnits(proceeds, 18), 2)} dUSDC → issuer. Deposit minted into dQQQ + dANT and seeded as a 4-tranche v4 position.`;
  $('positions').innerHTML =
    `<div class="kv"><span class="a">init price</span><span>1 dQQQ = ${fmt(cfg.qqqPriceUsd / cfg.antPriceUsd, 3)} dANT</span></div>` + tr;
  const url = uniswapPoolUrl();
  $('pool-link').innerHTML = url
    ? `<a class="btn" href="${url}" target="_blank" rel="noopener" style="text-decoration:none">View pool on Uniswap ↗</a>`
    : '';
  $('positions-card').style.display = 'block';
}

async function loadBids() {
  try {
    const block = await publicClient.getBlockNumber();
    const fromBlock = block > 9000n ? block - 9000n : 0n;
    const logs = await publicClient.getLogs({ address: lp, event: bidEvent, fromBlock, toBlock: 'latest' });
    return logs.map(l => ({ amount: Number(formatUnits(l.args.amount, 18)), discount: Number(l.args.discount) }));
  } catch (e) { log('⚠ could not load bids: ' + (e.shortMessage || e.message), 'err'); return []; }
}

function chart(bids, clearingBps) {
  const W = 680, H = 360, m = { l: 64, r: 22, t: 22, b: 44 }, pw = W - m.l - m.r, ph = H - m.t - m.b;
  const maxD = maxDiscount || 1;
  const byLvl = new Map(); for (const b of bids) byLvl.set(b.discount, (byLvl.get(b.discount) || 0) + b.amount);
  const total = bids.reduce((s, b) => s + b.amount, 0);
  const yMax = Math.max(depositUsd, total) * 1.15 || 1;
  const X = (d) => m.l + (d / maxD) * pw, Y = (v) => m.t + ph - (v / yMax) * ph;
  const pts = [[0, 0]]; let run = 0;
  for (const lv of [...byLvl.keys()].sort((a, b) => a - b)) {
    const add = byLvl.get(lv);
    if (lv === 0) { run += add; pts.push([0, run]); } else { pts.push([lv, run]); run += add; pts.push([lv, run]); }
  }
  pts.push([maxD, run]);
  const line = pts.map(p => `${X(p[0])},${Y(Math.min(p[1], yMax))}`).join(' ');
  let g = '';
  for (const v of [0, .25, .5, .75, 1].map(f => f * yMax)) {
    g += `<line x1="${m.l}" y1="${Y(v)}" x2="${m.l + pw}" y2="${Y(v)}" stroke="#20262e"/>`;
    g += `<text x="${m.l - 8}" y="${Y(v) + 4}" text-anchor="end" fill="#8b949e" font-size="11">${fmt(v / 1000, 1)}k</text>`;
  }
  for (const d of [0, .5, 1].map(f => Math.round(f * maxD)))
    g += `<text x="${X(d)}" y="${m.t + ph + 20}" text-anchor="middle" fill="#8b949e" font-size="11">${d} bp</text>`;
  g += `<text x="${m.l + pw / 2}" y="${H - 4}" text-anchor="middle" fill="#8b949e" font-size="12">discount accepted (bps) →</text>`;
  g += `<line x1="${m.l}" y1="${Y(depositUsd)}" x2="${m.l + pw}" y2="${Y(depositUsd)}" stroke="var(--accent2)" stroke-width="2" stroke-dasharray="6 5"/>`;
  g += `<text x="${m.l + pw - 4}" y="${Y(depositUsd) - 7}" text-anchor="end" fill="var(--accent2)" font-size="11">total value ${fmt(depositUsd / 1000, 1)}k</text>`;
  g += `<polygon points="${X(0)},${Y(0)} ${line} ${X(maxD)},${Y(0)}" fill="rgba(255,0,122,.08)"/>`;
  g += `<polyline points="${line}" fill="none" stroke="var(--accent)" stroke-width="2.5"/>`;
  if (clearingBps != null && total > 0) {
    const x = X(Math.min(clearingBps, maxD));
    g += `<line x1="${x}" y1="${m.t}" x2="${x}" y2="${m.t + ph}" stroke="#fff" stroke-width="1" stroke-dasharray="3 4" opacity=".75"/>`;
    g += `<circle cx="${x}" cy="${Y(Math.min(total, depositUsd, yMax))}" r="6" fill="#fff" stroke="var(--accent)" stroke-width="3"/>`;
  }
  $('chart').innerHTML = `<svg class="chart" viewBox="0 0 ${W} ${H}"><rect x="${m.l}" y="${m.t}" width="${pw}" height="${ph}" fill="transparent" stroke="#20262e"/>${g}</svg>`;
}

async function refresh() {
  try {
    $('block').textContent = (await publicClient.getBlockNumber()).toString();
    $('conn').classList.add('ok'); $('conn-text').textContent = `chain ${cfg.chainId}`;
    await syncAuction();
    if (account) {
      const bal = await publicClient.readContract({ address: cfg.usdc, abi: erc20, functionName: 'balanceOf', args: [account] });
      $('my-bal').textContent = fmt(formatUnits(bal, 18), 0);
      $('reset').disabled = false;
    }
    if (!lp) {
      $('stage-pill').textContent = 'NO AUCTION'; $('i-status').textContent = 'no active auction — Reset to start one';
      ['bid', 'end', 'unwind', 'redeem'].forEach(id => $(id).disabled = true);
      chart([], null); return;
    }
    isEnded = await publicClient.readContract({ address: lp, abi: padAbi, functionName: 'ended' });
    isUnwound = await publicClient.readContract({ address: lp, abi: padAbi, functionName: 'unwound' });
    const clearingBps = Number(await publicClient.readContract({ address: lp, abi: padAbi, functionName: 'clearingDiscount' }));
    const bids = await loadBids();
    $('s-disc').textContent = clearingBps + ' bps';
    $('s-price').textContent = ((10000 - clearingBps) / 10000).toFixed(4);
    $('s-demand').textContent = fmt(bids.reduce((s, b) => s + b.amount, 0), 0) + ' dUSDC';
    $('s-grad').textContent = isUnwound ? 'unwound' : isEnded ? 'settled' : 'open';
    $('stage-pill').textContent = isUnwound ? 'UNWOUND' : isEnded ? 'SETTLED' : 'BIDDING';
    $('i-status').textContent = isUnwound ? 'lockup ended — holders can redeem'
      : isEnded ? 'settled — position built (lockup active)' : 'open — anyone can bid or end';
    $('bid-hint').textContent = `↳ bid any discount from 0 to ${maxDiscount} bps — the clearing discount is set when the auction ends`;

    if (account && shareAddr) {
      myShares = await publicClient.readContract({ address: shareAddr, abi: erc20, functionName: 'balanceOf', args: [account] });
      $('my-shares').textContent = fmt(formatUnits(myShares, 18), 0);
      $('bid').disabled = isEnded;
      $('end').disabled = isEnded;
      $('unwind').disabled = !isEnded || isUnwound;
      $('redeem').disabled = !isUnwound || myShares === 0n;
    }
    if (isEnded && $('positions-card').style.display === 'none') {
      const proceeds = await publicClient.readContract({ address: lp, abi: padAbi, functionName: 'proceeds' });
      showPositions(proceeds);
    }
    chart(bids, clearingBps);
  } catch (e) {
    $('conn').classList.remove('ok'); $('conn-text').textContent = 'cannot reach chain';
  }
}

async function boot() {
  try { cfg = await (await fetch('./addresses.json')).json(); }
  catch { log('✗ could not load addresses.json — deploy first', 'err'); return; }
  if (!cfg.registry) { log('✗ addresses.json has no registry — run DemoRegistryDeploy', 'err'); return; }
  chain = CHAINS[cfg.chainId] || anvil;
  publicClient = createPublicClient({ chain, transport: http(READ_RPC[cfg.chainId] || READ_RPC[31337]) });
  registryAddr = cfg.registry;
  maxDiscount = cfg.maxDiscountBps || 100;
  $('i-maxd').textContent = maxDiscount + ' bps';
  $('connect').onclick = connect;
  $('faucet').onclick = faucet;
  $('bid').onclick = placeBid;
  $('end').onclick = endAuction;
  $('unwind').onclick = unwind;
  $('redeem').onclick = redeem;
  $('reset').onclick = reset;
  await refresh();
  setInterval(refresh, 5000);
}
boot();
