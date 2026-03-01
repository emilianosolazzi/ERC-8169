# ERC-721H Frontend Integration Guide

## 1. Quick Start (ethers.js v6)

```js
import { ethers } from "ethers";

const provider = new ethers.BrowserProvider(window.ethereum);
const signer   = await provider.getSigner();
const nft      = new ethers.Contract(NFT_ADDRESS, ERC721H_ABI, signer);

// ── Mint ──────────────────────────────────────────────
const tx = await nft.mint(await signer.getAddress());
const receipt = await tx.wait();

// Safe log parsing: ERC-721H emits multiple events per mint,
// so filter by name instead of relying on index order.
const transferEvent = receipt.logs
  .map(log => { try { return nft.interface.parseLog(log); } catch { return null; } })
  .find(parsed => parsed?.name === "Transfer");
const tokenId = transferEvent.args.tokenId;        // BigInt
console.log("Minted token", tokenId.toString());
// NOTE: ethers v6 returns BigInt. Use .toString() for display
// or Number(tokenId) for small collections only.

// ── Transfer ──────────────────────────────────────────
await (await nft.transferFrom(alice, bob, tokenId)).wait();
await (await nft.transferFrom(bob, charlie, tokenId)).wait();
// History now: [alice, bob, charlie]

// ── Read Three-Layer Model ────────────────────────────
const creator = await nft.originalCreator(tokenId);     // Layer 1 – immutable
const [owners, timestamps] = await nft.getOwnershipHistory(tokenId); // Layer 2 – [addresses], [timestamps]
const current = await nft.ownerOf(tokenId);              // Layer 3 – current

// ── Provenance Check ──────────────────────────────────
const wasFounder = await nft.hasEverOwned(tokenId, founder);  // O(1) lookup
const minted     = await nft.getOriginallyCreatedTokens(alice);

// ── Sybil Guard Query (block.number-based) ────────────
const ownerAtBlock = await nft.getOwnerAtBlock(tokenId, blockNumber);
// Returns address(0) if no ownership recorded at that block.
// UX: display "No owner recorded" — do NOT show raw 0x000...000.
// getOwnerAtTimestamp() is DEPRECATED — always returns address(0)

// ── Collection Stats ──────────────────────────────────
const active = await nft.totalSupply();   // excludes burned tokens
const minted2 = await nft.totalMinted();  // includes burned tokens

// ── Pagination (anti-griefing for large histories) ────
// PREFER getHistorySlice() over getOwnershipHistory() for scalable UIs.
// getOwnershipHistory() returns the full array — safe for small histories,
// but can hit RPC response limits or stall mobile wallets on heavily-traded tokens.
const len = await nft.getHistoryLength(tokenId);
const [slice, times] = await nft.getHistorySlice(tokenId, 0, 50);

// ── Burn (preserves Layer 1 & 2) ──────────────────────
await (await nft.burn(tokenId)).wait();
// totalSupply() decrements; totalMinted() unchanged
// originalCreator() and getOwnershipHistory() still return data
```

## 2. Demo: Frontend Panel

```
 ┌────────────────────────────────────────────────┐
 │  Token #1 – Provenance Report                  │
 ├────────────────────────────────────────────────┤
 │  Original Creator : 0xAlic...e   (Layer 1)     │
 │  Current Owner    : 0xChar...ie  (Layer 3)     │
 │  Total Supply     : 42  (active, excl. burned) │
 │  Total Minted     : 45  (historical, all-time)  │
 │                                                │
 │  Ownership History (Layer 2):                  │
 │    1. 0xAlic...e   — minted                    │
 │    2. 0xBob...b    — transfer                  │
 │    3. 0xChar...ie  — transfer                  │
 │                                                │
 │  hasEverOwned(0xBob) : true   (O(1) lookup)    │
 │  Originally Created  : [#1, #7, #12]           │
 └────────────────────────────────────────────────┘
```

## 3. Comparison Chart

> Comparison vs **minimal ERC-721** (non-enumerable). ERC-721Enumerable adds supply tracking but not provenance.

| Feature                          | ERC-721          | ERC-721H              |
|:---------------------------------|:-----------------|:----------------------|
| Track current owner              | Yes              | Yes                   |
| Track original creator           | No               | Yes (immutable)       |
| Track full ownership history     | No (events only) | Yes (on-chain array)  |
| `hasEverOwned()` lookup          | N/A              | O(1) via mapping      |
| Airdrop to original minters      | No               | Yes (`getOriginallyCreatedTokens`) |
| Founder / early-adopter benefits | No               | Yes (survives transfer) |
| Provenance proof                 | Fragile (logs)   | Solid (native)        |
| History survives burn            | No               | Yes (Layer 1 & 2 persist) |
| Reentrancy protection            | Varies           | Built-in (`nonReentrant`) |
| Access-controlled mint           | Varies           | `onlyOwner`           |
| Burn support                     | Varies           | Yes (owner/approved)  |
| Sybil protection                 | No               | Yes (dual-layer: EIP-1153 tstore + block.number) |
| `totalSupply()` (active)         | No (ERC-721Enum) | Yes (excludes burned) |
| `totalMinted()` (historical)     | No               | Yes (includes burned) |
| Pagination (`getHistorySlice`)   | N/A              | Yes (anti-griefing)   |

## 4. Key ABI Snippet

```json
[
  "function mint(address to) external returns (uint256)",
  "function burn(uint256 tokenId) external",
  "function transferFrom(address from, address to, uint256 tokenId) external",
  "function safeTransferFrom(address from, address to, uint256 tokenId) external",
  "function safeTransferFrom(address from, address to, uint256 tokenId, bytes data) external",
  "function approve(address to, uint256 tokenId) external",
  "function setApprovalForAll(address operator, bool approved) external",
  "function getApproved(uint256 tokenId) view returns (address)",
  "function isApprovedForAll(address account, address operator) view returns (bool)",
  "function ownerOf(uint256 tokenId) view returns (address)",
  "function balanceOf(address account) view returns (uint256)",
  "function totalSupply() view returns (uint256)",
  "function totalMinted() view returns (uint256)",
  "function tokenURI(uint256 tokenId) view returns (string)",
  "function originalCreator(uint256 tokenId) view returns (address)",
  "function mintBlock(uint256 tokenId) view returns (uint256)",
  "function isOriginalOwner(uint256 tokenId, address account) view returns (bool)",
  "function isCurrentOwner(uint256 tokenId, address account) view returns (bool)",
  "function hasEverOwned(uint256 tokenId, address account) view returns (bool)",
  "function getOwnershipHistory(uint256 tokenId) view returns (address[], uint256[])",
  "function getTransferCount(uint256 tokenId) view returns (uint256)",
  "function getEverOwnedTokens(address account) view returns (uint256[])",
  "function getOriginallyCreatedTokens(address creator) view returns (uint256[])",
  "function isEarlyAdopter(address account, uint256 blockThreshold) view returns (bool)",
  "function getOwnerAtBlock(uint256 tokenId, uint256 blockNumber) view returns (address)",
  "function getOwnerAtTimestamp(uint256 tokenId, uint256 timestamp) pure returns (address)",
  "function getHistoryLength(uint256 tokenId) view returns (uint256)",
  "function getHistorySlice(uint256 tokenId, uint256 start, uint256 count) view returns (address[], uint256[])",
  "function getProvenanceReport(uint256 tokenId) view returns (address, uint256, address, uint256, address[], uint256[])",
  "function historyMode() view returns (uint8)",
  "function getHistoryHash(uint256 tokenId) view returns (bytes32)",
  "function transferCooldownBlocks() view returns (uint256)",
  "function setTransferCooldown(uint256 blocks) external",
  "function name() view returns (string)",
  "function symbol() view returns (string)",
  "function owner() view returns (address)",
  "function transferOwnership(address newOwner) external"
]
```

## 5. Gas Estimates

| Operation  | ERC-721   | ERC-721H (FULL) | FLAG_ONLY | COMPRESSED | Overhead (FULL) |
|:-----------|:----------|:----------------|:----------|:-----------|:----------------|
| Mint       | ~50,000   | ~332,000        | ~150,000  | ~180,000   | +564%           |
| Transfer   | ~50,000   | ~170,000        | ~70,000   | ~90,000    | +240%           |
| Burn       | ~30,000   | ~10,000         | ~10,000   | ~10,000    | -67%            |
| Read history | Free    | Free            | Free      | Free       | —               |

> **Trade-off**: Higher write gas for permanent on-chain provenance with dual Sybil protection.
>
> Gas numbers are approximate cold-path measurements. Actual costs vary with storage warmth, approval state, and L1 vs L2.
> FLAG_ONLY and COMPRESSED estimates are approximate.

## 6. Same-Block Transfer Limit

⚠️ The dual Sybil guard enforces **one transfer per token per block** (and one per transaction).

If a user tries to transfer a token that already moved in the current block, the transaction reverts with `OwnerAlreadyRecordedForBlock()`.

**Frontend handling:**
```js
try {
  await (await nft.transferFrom(from, to, tokenId)).wait();
} catch (err) {
  if (err.message.includes("OwnerAlreadyRecordedForBlock")) {
    alert("This token was already transferred this block. Please retry next block.");
  }
}
```

Marketplaces should surface a friendly message — this is intentional Sybil protection, not a bug.

## 6b. Transfer Cooldown (L2 Anti-Griefing)

On L2s where gas is cheap, an attacker can transfer once per block for thousands of blocks to inflate history storage. The **configurable transfer cooldown** mitigates this:

```js
// Set 300 block cooldown (~5 min on Arbitrum/Base)
await (await nft.setTransferCooldown(300)).wait();

// Check current cooldown
const cooldown = await nft.transferCooldownBlocks();

// Transfers within cooldown window revert with TransferCooldownActive()
try {
  await (await nft.transferFrom(from, to, tokenId)).wait();
} catch (err) {
  if (err.message.includes("TransferCooldownActive")) {
    alert("Please wait before transferring this token again.");
  }
}
```

**Recommended values:**
- L1: `0` (gas cost is natural deterrent)
- L2, moderate: `50–300` blocks (~1–5 min)
- L2, anti-wash: `1800+` blocks (~30+ min)

## 6c. History Modes

ERC-721H supports three history modes, set at construction (immutable):

| Mode | Gas per Transfer | `getOwnershipHistory()` | `hasEverOwned()` | `getOwnerAtBlock()` |
|:-----|:----------------|:-----------------------|:-----------------|:--------------------|
| **FULL** (0) | ~170k | ✓ Full arrays | ✓ O(1) | ✓ O(log n) |
| **FLAG_ONLY** (1) | ~70k | ✗ Empty | ✓ O(1) | ✗ Returns 0 |
| **COMPRESSED** (2) | ~90k | ✗ Empty | ✓ O(1) | ✗ Returns 0 |

```js
// Check mode
const mode = await nft.historyMode();
// 0 = FULL, 1 = FLAG_ONLY, 2 = COMPRESSED

// COMPRESSED mode: retrieve hash chain commitment
const hash = await nft.getHistoryHash(tokenId);
// Verify off-chain by replaying Transfer events and recomputing:
// H₀ = keccak256(0x00 ‖ creator ‖ mintBlock ‖ mintTimestamp)
// Hₙ = keccak256(Hₙ₋₁ ‖ newOwner ‖ block ‖ timestamp)
```

## 7. Indexer Integration

Unlike standard ERC-721, ERC-721H does **not** require off-chain indexers to reconstruct ownership history:

| Capability | ERC-721 | ERC-721H |
|:-----------|:--------|:---------|
| Current owner | On-chain | On-chain |
| Full ownership history | Requires indexer (The Graph, Alchemy) | On-chain (`getOwnershipHistory`) |
| "Has ever owned?" check | Requires indexer | On-chain O(1) (`hasEverOwned`) |
| Original minter | Requires indexer | On-chain (`originalCreator`) |

Subgraphs become **optional** — useful for caching and UI performance, but no longer mandatory for correctness. The source of truth lives in contract storage, not event logs.
