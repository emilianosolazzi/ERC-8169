# ERC-8169: On-Chain Provenance as a State Primitive

> **v2.1.0** — Library architecture + production factory
>
> **ERC-721 is a state machine with no memory. ERC-721H augments the EVM state model to include provenance — permanently, composably, without indexers.**
>
> *Positioned as an L2-native provenance primitive, not as "better NFT tracking."*

---

## What This Actually Is

This is not an NFT-tracking upgrade. It is a **state-augmentation standard**.

The EVM state model is stateless with respect to time: it records what *is*, never what *was*. Smart contracts can read storage slots, but they cannot read event logs. The moment a token transfers, provenance exists only in off-chain infrastructure — indexers that can go down, lag, and require trust.

ERC-721H extends the EVM state model to include a **temporal ownership dimension** — a structurally append-only provenance layer that is permanently readable by other contracts, verifiable without any off-chain component, and protected against retrospective manipulation.

This is the design intent. The NFT tracking consequences are a byproduct.

## The EVM Limitation

Standard ERC-721 stores exactly one ownership datum: the current holder. All historical provenance lives in `Transfer` event logs, which:

- Cannot be read by other smart contracts (no EVM opcode for log access)
- Require off-chain indexers (The Graph, Alchemy) that can go down
- Cannot power on-chain governance, royalty splits, or airdrops
- Require off-chain reconstruction for any on-chain use

## The Solution: Three-Layer Ownership

ERC-721H maintains three parallel layers of ownership data:

```
┌─────────────────────────────────────────────────────────────────┐
│ Layer 1 — Immutable Origin     (write-once at mint)             │
│   originalCreator[tokenId] = Alice                              │
│   mintBlock[tokenId] = 18_500_000                               │
├─────────────────────────────────────────────────────────────────┤
│ Layer 2 — Historical Trail     (append-only, never deleted)     │
│   ownershipHistory[tokenId] = [Alice, Bob, Charlie]             │
│   hasEverOwned[tokenId][Bob] = true        ← O(1) lookup       │
├─────────────────────────────────────────────────────────────────┤
│ Layer 3 — Current Authority    (standard ERC-721)               │
│   ownerOf(tokenId) = Charlie                                    │
└─────────────────────────────────────────────────────────────────┘
```

Layer 1 never changes. Layer 2 only grows. Layer 3 works exactly like ERC-721.

## Use Cases

| Use Case | What ERC-721 Does | What ERC-721H Does |
|:---------|:------------------|:-------------------|
| Art Provenance | Nothing — history lost | Full chain: artist → gallery → collector |
| Founder Benefits | Minter forgotten after transfer | `isOriginalOwner()` returns `true` forever |
| Early Adopter Airdrops | Requires off-chain Merkle proof | `isEarlyAdopter()` — one on-chain call |
| Proof-of-Custody | Event logs (off-chain reconstruction) | Storage slots (contract-queryable) |
| Gaming Veteran Status | Cannot prove past ownership | `hasEverOwned()` — O(1) on-chain |

## Quick Start

### Install

```bash
# Copy all source files into your project
cp src/IERC721H.sol           your-project/contracts/
cp src/ERC-721H.sol           your-project/contracts/
cp src/ERC721HStorageLib.sol  your-project/contracts/
cp src/ERC721HCoreLib.sol     your-project/contracts/
cp src/ERC-721HFactory.sol    your-project/contracts/  # optional -- factory + collection
```

### Deploy (Direct)

```solidity
import {ERC721H} from "./ERC-721H.sol";
import {ERC721HStorageLib} from "./ERC721HStorageLib.sol";

contract MyNFT is ERC721H {
  constructor() ERC721H("MyCollection", "MYC", ERC721HStorageLib.HistoryMode.FULL) {}

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        // Your metadata logic
    }
}
```

### Deploy (Factory — Recommended for Production)

```js
const factory = new ethers.Contract(FACTORY_ADDRESS, FACTORY_ABI, signer);
const salt = ethers.id("my-unique-salt");

// Predict address before deploying (same on any EVM chain)
const predicted = await factory.predictAddress(
  "Founders", "FNDR", 10000, "https://api.example.com/meta/",
  salt, await signer.getAddress()
);

// Deploy via CREATE2 — ownership auto-transfers to caller
const tx = await factory.deployCollection(
  "Founders", "FNDR", 10000, "https://api.example.com/meta/", salt
);
const rc = await tx.wait();
```

The factory deploys `ERC721HCollection` instances — production wrappers with batch minting, supply caps, public mint with pricing, and batch historical queries.

### Interact (ethers.js v6)

```js
const nft = new ethers.Contract(address, ERC721H_ABI, signer);

// Mint
const tx = await nft.mint(recipientAddress);
const rc = await tx.wait();

// Query all three layers
const creator = await nft.originalCreator(tokenId);       // Layer 1
const history = await nft.getOwnershipHistory(tokenId);    // Layer 2
const current = await nft.ownerOf(tokenId);                // Layer 3

// O(1) historical check
const wasHolder = await nft.hasEverOwned(tokenId, someAddress);

// Historical owner at any arbitrary block — O(log n) binary search
const pastOwner = await nft.getOwnerAtBlock(tokenId, 18_500_000);

// Full provenance in one call
const report = await nft.getProvenanceReport(tokenId);

// Paginated queries (anti-griefing for large histories)
const [slice, times] = await nft.getHistorySlice(tokenId, 0, 50);
const ownedSlice = await nft.getEverOwnedTokensSlice(alice, 0, 50);

// Detect ERC-721H support
const isHistorical = await nft.supportsInterface(IERC721H_ID);
```

## API Reference

### Layer 1 — Immutable Origin

| Function | Returns | Gas |
|:---------|:--------|:----|
| `originalCreator(tokenId)` | `address` — who minted it | Free |
| `mintBlock(tokenId)` | `uint256` — block number at mint | Free |
| `isOriginalOwner(tokenId, account)` | `bool` | Free |
| `getOriginallyCreatedTokens(creator)` | `uint256[]` — all tokens minted by address | Free |
| `isEarlyAdopter(account, blockThreshold)` | `bool` — minted before block N? | Free |

### Layer 2 — Historical Trail

| Function | Returns | Gas |
|:---------|:--------|:----|
| `hasEverOwned(tokenId, account)` | `bool` — O(1) mapping lookup | Free |
| `getOwnershipHistory(tokenId)` | `(address[], uint256[])` — owners + timestamps | Free |
| `getTransferCount(tokenId)` | `uint256` — number of transfers | Free |
| `getEverOwnedTokens(account)` | `uint256[]` — all tokens ever held (deduplicated) | Free |
| `getOwnerAtBlock(tokenId, blockNumber)` | `address` — O(log n) binary search over `_ownershipBlocks` | Free |
| `getOwnerAtTimestamp(tokenId, timestamp)` | **DEPRECATED** — always returns `address(0)`. Use `getOwnerAtBlock`. | Free |
| `getHistoryLength(tokenId)` | `uint256` — entries in ownership history | Free |
| `getHistorySlice(tokenId, start, count)` | `(address[], uint256[])` — paginated slice (anti-griefing) | Free |
| `getEverOwnedTokensLength(account)` | `uint256` — total tokens ever held by address | Free |
| `getEverOwnedTokensSlice(account, start, count)` | `uint256[]` — paginated per-address token list | Free |
| `getCreatedTokensLength(creator)` | `uint256` — total tokens minted by address | Free |
| `getCreatedTokensSlice(creator, start, count)` | `uint256[]` — paginated per-creator token list | Free |

### Layer 3 — Current Authority (ERC-721 Compatible)

| Function | Returns | Gas |
|:---------|:--------|:----|
| `ownerOf(tokenId)` | `address` | Free |
| `balanceOf(account)` | `uint256` | Free |
| `transferFrom(from, to, tokenId)` | — | ~170,000 |
| `safeTransferFrom(from, to, tokenId)` | — | ~173,000 |
| `approve(to, tokenId)` | — | ~32,000 |
| `setApprovalForAll(operator, approved)` | — | ~38,000 |

### Aggregate

| Function | Returns | Gas |
|:---------|:--------|:----|
| `getProvenanceReport(tokenId)` | Full report (creator, block, owner, transfers, history) | Free |
| `totalSupply()` | `uint256` — active tokens (excludes burned) | Free |
| `totalMinted()` | `uint256` — all-time minted (includes burned) | Free |

### Lifecycle

| Function | Behavior | Gas |
|:---------|:---------|:----|
| `mint(to)` | Creates token, sets all 3 layers (`virtual` — overridable) | ~332,000 |
| `_mint(to)` | Internal primitive — no access control. Used by inheritors for custom mint paths (batch, public, allowlist). | ~332,000 |
| `burn(tokenId)` | Clears Layer 3, **preserves Layer 1 & 2** | ~10,000–25,000 |
| `transferOwnership(newOwner)` | Contract admin transfer | ~25,000 |

### ERC721HCollection (via ERC721HFactory)

| Function | Behavior | Gas |
|:---------|:---------|:----|
| `batchMint(to, quantity)` | Owner-only batch mint to one address | ~332k × n |
| `batchMintTo(recipients[])` | Owner-only airdrop — one token per address | ~332k × n |
| `publicMint(quantity)` | Payable public mint with per-wallet limits + supply cap | ~332k × n |
| `batchTokenSummary(tokenIds[])` | Batch provenance: creator, block, owner, transfer count | Free |
| `batchOwnerAtBlock(tokenIds[], block)` | Batch historical snapshot — O(log n) per token | Free |
| `batchHasEverOwned(tokenIds[], account)` | Batch ownership check — O(1) per token | Free |
| `batchOriginalCreator(tokenIds[])` | Batch creator lookup | Free |
| `batchTransferCount(tokenIds[])` | Batch activity metric | Free |
| `setBaseURI(uri)` / `setMintPrice(price)` / `setMaxPerWallet(n)` / `togglePublicMint()` | Admin configuration | ~25k each |
| `withdraw()` | Withdraw all ETH revenue to owner | ~25k |

## Gas Overhead

| Operation | ERC-721 | ERC-721H | Overhead | Why |
|:----------|:--------|:---------|:---------|:----|
| Mint | ~50,000 | ~332,000 | +564% | 3 layers + Sybil guards (EIP-1153 transient + block.number) + history |
| Transfer | ~50,000 | ~170,000 | +240% | 2 SSTOREs (history, block) + Sybil guards + dedup |
| Burn | ~30,000 | ~10,000–25,000 | -67% to -17% | Skips refunds — Layer 1 & 2 preserved; varies with storage warmth |
| Read | Free | Free | — | All queries are `view` |

> More suitable for rollups (Arbitrum, Base, Optimism) where write costs are significantly lower. On L1, this is the explicit trade-off for permanent trustless provenance with dual Sybil protection. Gas numbers are approximate cold-path measurements; actual costs vary with storage warmth and network conditions.

## Security

- **Reentrancy**: `_transfer()` uses `nonReentrant` modifier with dedicated `Reentrancy()` error. All state mutations complete before external calls.
- **Access Control**: `mint()` restricted to `onlyOwner`. `burn()` restricted to token owner or approved.
- **O(1) Lookups**: `hasEverOwned()` uses a dedicated mapping — no unbounded iteration.
- **Deduplication**: `_everOwnedTokens` deduped via `_hasOwnedToken` — wash trading cannot bloat per-address lists.
- **Self-Transfer Prevention**: `from == to` reverts with `InvalidRecipient()` — blocks history pollution without real ownership change.
- **ERC-721 Behavioral Divergence**: Optional cooldown (`transferCooldownBlocks`) and self-transfer prevention intentionally make this a constrained ERC-721 variant, not a pure behavioral superset.
- **Burn Semantics**: `totalSupply()` decrements on burn; `totalMinted()` does not. `HistoricalTokenBurned` event signals Layer-3-only deletion to indexers.
- **Sybil Protection (Dual-Layer)**:
  - **Intra-TX**: `oneTransferPerTokenPerTx` modifier using EIP-1153 transient storage blocks A→B→C→D chains within one transaction
  - **Inter-TX**: Uses `lastTransferBlock[tokenId]` — if the last recorded block equals `block.number`, transfer reverts with `OwnerAlreadyRecordedForBlock()`. Uses `block.number`, not `block.timestamp`, to prevent validator manipulation.
- **Cooldown Semantics**: Cooldown compares against `lastTransferBlock`, which is initialized at mint; with non-zero cooldown, first post-mint transfer may require waiting the configured block interval.
- **O(log n) Historical Queries**: `getOwnerAtBlock()` uses binary search over `_ownershipBlocks[]` to resolve the owner at any arbitrary past block — not just transfer blocks.
- **COMPRESSED Proof Model**: `getHistoryHash(tokenId)` exposes only the latest commitment hash, not per-step hashes. Inclusion is verified off-chain by replaying the ordered transfer sequence and recomputing the chain (`H0 = keccak256(0x00, owner, block, timestamp)`, `Hn = keccak256(Hn-1, owner, block, timestamp)`) then comparing the final hash.
- **ERC-165**: `supportsInterface()` returns `true` for ERC-165, ERC-721, ERC-721 Metadata, `IERC721HCore` (required), and `IERC721HAnalytics` (optional). Legacy `IERC721H` aggregate ID is also supported for backward compatibility.

## Repository Structure

```
src/
├── IERC721HCore.sol         Core interface -- required minimal provenance primitives
├── IERC721HAnalytics.sol    Analytics interface -- optional convenience queries (O(n))
├── IERC721H.sol             Legacy aggregate interface (Core + Analytics)
├── ERC-721H.sol             Core contract (v2.1.0) -- 3-layer ownership, 3 history modes
├── ERC721HStorageLib.sol    Library -- low-level storage, Sybil guard, binary search, pagination
├── ERC721HCoreLib.sol       Library -- provenance report, transfer count, early adopter
└── ERC-721HFactory.sol      Factory (CREATE2) + ERC721HCollection (production wrapper)
tests/
├── ERC721H_Full.t.sol
├── ERC721H_HistoryModes.t.sol
├── ERC721H_Cooldown.t.sol
├── ERC721H_Factory.t.sol
└── ...
document/EIP/
└── erc-8169.md              EIP specification
└── README.md                This file
```

1. **Core Interface**: `src/IERC721HCore.sol` — required minimal provenance surface (O(1)/O(log n) views, events)
2. **Analytics Interface**: `src/IERC721HAnalytics.sol` — optional convenience queries, O(n)-safe for off-chain use
3. **Legacy Interface**: `src/IERC721H.sol` — backward-compatible aggregate of Core + Analytics
4. **Core Implementation**: `src/ERC-721H.sol` — v2.1.0, library architecture, 3 history modes (FULL/FLAG_ONLY/COMPRESSED), cooldown guard
5. **Storage Library**: `src/ERC721HStorageLib.sol` — HistoryStorage struct, recordMint/recordTransfer, binary search, Sybil guard, pagination
6. **Core Library**: `src/ERC721HCoreLib.sol` — buildProvenanceReport, getTransferCount, isEarlyAdopter
7. **Factory + Collection**: `src/ERC-721HFactory.sol` — permissionless CREATE2 deployer + production wrapper with batch mint, batch queries, supply cap, public mint
8. **EIP Document**: `document/EIP/erc-8169.md` — Preamble, Abstract, Motivation, Specification, Rationale, Backwards Compatibility, Reference Implementation, Security Considerations
9. **Status**: Draft
10. **Category**: Standards Track → ERC
11. **Requires**: EIP-165, EIP-721


## Architecture (v2.1.0)

```
┌───────────────────────────────────────────────────┐
│  ERC721HFactory (permissionless CREATE2 deployer) │
│    → deploys ERC721HCollection instances           │
│    → registry + predictAddress for cross-chain     │
├───────────────────────────────────────────────────┤
│  ERC721HCollection (production wrapper)            │
│    inherits ERC721H                                │
│    + batch minting (batchMint, batchMintTo)        │
│    + public mint (price, per-wallet limits, cap)   │
│    + 5 batch historical query functions            │
│    + configurable metadata URI + withdraw          │
├───────────────────────────────────────────────────┤
│  ERC-721H.sol (core contract)                      │
│    uses ERC721HStorageLib  (storage, Sybil, search)│
│    uses ERC721HCoreLib     (provenance, analytics) │
└───────────────────────────────────────────────────┘
```

- `_mint()` is `internal` — inheritors build custom mint paths on top
- `mint()` is `virtual` — overridable with supply caps, allowlists, etc.
- Libraries use `internal` functions → inlined at compile time, zero external call overhead
- Factory deploys full contracts (not clones) → no delegatecall risks, no initializer footguns
- CREATE2 with deployer-mixed salt → deterministic cross-chain addresses, front-run resistant

## Backwards Compatibility

ERC-721H preserves ERC-721 interfaces and ecosystem compatibility, but is a **behaviorally constrained variant** when self-transfer prevention and/or transfer cooldown are enabled. Every ERC-721H token remains a valid ERC-721 contract integration target for wallets, marketplaces, and libraries, while adding historical state semantics and optional transfer constraints.

## Reviewer Validation Matrix

Run these to reproduce ERC-review-focused evidence:

```bash
# Full regression (unit + fuzz + invariants)
forge test

# Gas scenarios (mint, cold transfer, warm transfer surrogate,
# re-transfer path, cooldown-hit revert)
forge test --match-path tests/ERC721H_Gas.t.sol --gas-report

# Compatibility flows (approval operator, safeTransferFrom, receiver behavior, cooldown guidance)
forge test --match-path tests/ERC721H_Compatibility.t.sol

# Cross-implementation smoke tests (local + optional rollup forks)
forge test --match-path tests/ERC721H_RollupForks.t.sol
```

Optional fork env vars for rollup behavior checks:

```bash
export OPTIMISM_RPC_URL="https://..."
export ARBITRUM_RPC_URL="https://..."
forge test --match-path tests/ERC721H_RollupForks.t.sol
```

When RPC URLs are not set, rollup fork tests are skipped by design and local Anvil smoke behavior still executes.

## Author

**Emiliano Solazzi** — 2026

## License

[MIT](LICENSE)
