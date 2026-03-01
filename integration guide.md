# ERC-721H Integration Guide (Accurate for v2.1.x)

This guide targets the current implementation in `src/ERC-721H.sol` and is written to avoid stale assumptions.

## 1) What You Are Integrating

`ERC721H` is an ERC-721-compatible contract with additional historical state.

- **Layer 1 (immutable):** `originalCreator(tokenId)`, `mintBlock(tokenId)`
- **Layer 2 (history):** `getOwnershipHistory`, `hasEverOwned`, pagination helpers
- **Layer 3 (current authority):** standard ERC-721 ownership/approval surface

Extra controls that affect transfer UX:

- **Intra-TX guard:** same token cannot transfer more than once in one transaction (`TokenAlreadyTransferredThisTx`)
- **Same-block guard:** same token cannot transfer twice in one block (`OwnerAlreadyRecordedForBlock`)
- **Optional cooldown:** `transferCooldownBlocks()`, owner-settable via `setTransferCooldown(uint256)`; reverts with `TransferCooldownActive`
- **Self-transfer blocked:** `from == to` reverts with `InvalidRecipient`

## 2) Contract Deployment Notes

Constructor:

```solidity
new ERC721H(name, symbol, mode)
```

`mode` is immutable:

- `0 = FULL`
- `1 = FLAG_ONLY`
- `2 = COMPRESSED`

If you use `ERC721HFactory` / `ERC721HCollection`, pass mode through factory deployment calls.

## 3) Ethers v6 Quick Start (Safe Patterns)

```ts
import { BrowserProvider, Contract } from "ethers";

const provider = new BrowserProvider(window.ethereum);
const signer = await provider.getSigner();
const nft = new Contract(NFT_ADDRESS, ERC721H_ABI, signer);

// Mint (owner-only on base ERC721H)
const mintTx = await nft.mint(await signer.getAddress());
const mintReceipt = await mintTx.wait();

const parsedTransfer = mintReceipt.logs
  .map((log: any) => {
    try { return nft.interface.parseLog(log); } catch { return null; }
  })
  .find((e: any) => e?.name === "Transfer");

const tokenId: bigint = parsedTransfer.args.tokenId;
console.log("Minted token", tokenId.toString());
```

Notes:

- ethers v6 returns `bigint` for integer values.
- Parse logs by event name, not index position (mint emits multiple events).

## 4) Transfer Integration (Do This)

```ts
async function transferWithHandling(from: string, to: string, tokenId: bigint) {
  try {
    const tx = await nft.transferFrom(from, to, tokenId);
    await tx.wait();
    return { ok: true };
  } catch (err: any) {
    const msg = String(err?.shortMessage || err?.message || "");

    if (msg.includes("OwnerAlreadyRecordedForBlock")) {
      return { ok: false, reason: "same_block_guard" };
    }
    if (msg.includes("TransferCooldownActive")) {
      return { ok: false, reason: "cooldown_active" };
    }
    if (msg.includes("TokenAlreadyTransferredThisTx")) {
      return { ok: false, reason: "same_tx_guard" };
    }
    if (msg.includes("InvalidRecipient")) {
      return { ok: false, reason: "invalid_recipient_or_self_transfer" };
    }

    return { ok: false, reason: "unknown", error: err };
  }
}
```

Important truth about cooldown behavior:

- Cooldown is checked against `lastTransferBlock[tokenId]`.
- `lastTransferBlock` is initialized at **mint**.
- So when cooldown > 0, the first post-mint transfer may be blocked until enough blocks pass.

## 5) History Queries by Mode

Read mode first:

```ts
const mode: number = Number(await nft.historyMode());
// 0 FULL, 1 FLAG_ONLY, 2 COMPRESSED
```

Behavior matrix:

- **FULL**
  - `getOwnershipHistory(tokenId)` returns full arrays
  - `getOwnerAtBlock(tokenId, blockNumber)` is meaningful (binary search)
  - `getHistoryHash(tokenId)` is typically zero / not used
- **FLAG_ONLY**
  - `hasEverOwned` remains useful
  - history arrays are empty
  - `getOwnerAtBlock` may return zero-address for queries
- **COMPRESSED**
  - `hasEverOwned` remains useful
  - history arrays are empty
  - use `getHistoryHash(tokenId)` as final hash-chain commitment

`getOwnerAtTimestamp()` is **deprecated** and always returns `address(0)`. Use `getOwnerAtBlock()` instead.

## 5.1) Interface Detection

ERC-721H exposes three ERC-165 interface IDs:

- **`IERC721HCore`** (required) — minimal provenance primitives
- **`IERC721HAnalytics`** (optional) — convenience queries (may be O(n))
- **`IERC721H`** (legacy aggregate) — combines both

```ts
import { IERC721HCore, IERC721HAnalytics, IERC721H } from "./interfaces";

// Detect support level
const hasCore = await nft.supportsInterface(IERC721H_CORE_ID);
const hasAnalytics = await nft.supportsInterface(IERC721H_ANALYTICS_ID);
const hasLegacy = await nft.supportsInterface(IERC721H_LEGACY_ID);
```

New integrations should check for `IERC721HCore`. The legacy aggregate ID is supported for backward compatibility.

## 6) Pagination (Large Histories)

For scalable UI, use pagination instead of full-array reads:

```ts
const len = Number(await nft.getHistoryLength(tokenId));
const pageSize = 50;
for (let start = 0; start < len; start += pageSize) {
  const [owners, timestamps] = await nft.getHistorySlice(tokenId, start, pageSize);
  // render slice
}
```

Per-address pagination:

- `getEverOwnedTokensLength(account)` + `getEverOwnedTokensSlice(account, start, count)`
- `getCreatedTokensLength(account)` + `getCreatedTokensSlice(account, start, count)`

## 7) Compatibility Guidance (Marketplaces / Routers)

OpenSea-style operator flow is supported:

- seller calls `setApprovalForAll(marketOperator, true)`
- operator calls `transferFrom(seller, buyer, tokenId)`

But with constraints:

- transfer can still revert due to same-block guard / cooldown
- integrations must not assume “approved + owner = guaranteed immediate transfer”

Safe receiver behavior:

- `safeTransferFrom` to contracts requires valid `onERC721Received` selector
- invalid return value reverts

## 8) Burn Semantics

`burn(tokenId)` clears current ownership (Layer 3) but preserves historical data (Layer 1 and Layer 2 semantics).

After burn:

- `ownerOf(tokenId)` reverts
- `originalCreator(tokenId)` remains available
- `totalSupply()` decreases
- `totalMinted()` does not decrease

## 9) Minimal ABI Strategy (Best Practice)

Use generated ABI from the compiled artifact instead of manually curating JSON.

```bash
forge build
forge inspect ERC721H abi
```

This avoids integration drift as interfaces evolve.

## 10) Validation Commands (Current Repo)

Use these exact commands for reproducible checks:

```bash
# Full suite (unit + fuzz + invariants + compliance)
forge test

# Gas scenarios: mint, cold transfer, warm surrogate, re-transfer path, cooldown hit
forge test --match-path tests/ERC721H_Gas.t.sol --gas-report

# Compatibility flows: operator approvals, safeTransferFrom, receiver contracts, cooldown behavior
forge test --match-path tests/ERC721H_Compatibility.t.sol

# Compliance module tests: KYC, country, lock-up, holder cap, end-to-end pipeline
forge test --match-path tests/ERC721H_Compliance.t.sol

# Rollup behavior smoke tests (local + optional forks)
forge test --match-path tests/ERC721H_RollupForks.t.sol
```

Optional env vars for fork tests:

```bash
export OPTIMISM_RPC_URL="https://..."
export ARBITRUM_RPC_URL="https://..."
```

If RPC vars are unset, fork-specific tests skip and local smoke still runs.

## 11) Frontend UX Recommendations

- Show explicit messages for known transfer constraints:
  - same block transfer blocked
  - cooldown window active
  - self-transfer invalid
  - compliance check failed (KYC, jurisdiction, lock-up, holder cap)
- When showing owners at historical blocks:
  - treat zero-address as "no recorded owner at that query point or mode limitation"
- In non-FULL modes, hide full-history UI and show mode-aware text.
- For compliant tokens, call `isTransferCompliant(from, to, tokenId)` before attempting transfers to surface specific failures to the user.

## 12) Regulatory Compliance Integration

ERC-721H includes an optional ERC-3643-inspired compliance framework under `src/compliance/`. This is useful for security tokens, RWAs, and any regulated asset issuance.

### Architecture

```
ERC721HCompliant (inherits ERC721H)
  └─ _beforeTokenTransfer() → ComplianceLib.enforceTransfer()
       ├─ KYCModule.canTransfer()          ← both parties verified?
       ├─ CountryRestrictModule.canTransfer() ← jurisdiction allowed?
       ├─ MaxHoldersModule.canTransfer()    ← holder cap check
       └─ LockUpModule.canTransfer()       ← lock-up expired?
  └─ _afterTokenTransfer() → MaxHoldersModule.onTransferCompleted()
```

### Deployment Steps

```solidity
// 1. Deploy shared identity registry
IdentityRegistry registry = new IdentityRegistry();
registry.registerIdentity(investor, 840, 2); // US, enhanced KYC

// 2. Deploy modules
KYCModule kyc = new KYCModule(address(registry), 1);
uint16[] memory blocked = new uint16[](2);
blocked[0] = 408; blocked[1] = 364; // KP, IR
CountryRestrictModule country = new CountryRestrictModule(address(registry), blocked);
MaxHoldersModule holders = new MaxHoldersModule(35); // Reg D cap
LockUpModule lockUp = new LockUpModule();

// 3. Deploy compliant token
ERC721HCompliant token = new ERC721HCompliant("SecurityNFT", "SEC", HistoryMode.FULL);

// 4. Wire modules
token.addComplianceModule(IComplianceModule(address(kyc)));
token.addComplianceModule(IComplianceModule(address(country)));
token.addComplianceModule(IComplianceModule(address(holders)));
token.addComplianceModule(IComplianceModule(address(lockUp)));

// 5. Authorize token contract on stateful modules
holders.setTokenContract(address(token));
lockUp.setTokenContract(address(token));
token.setMaxHoldersModule(holders);
```

### Pre-flight Transfer Check

```ts
// Check compliance before attempting transfer (avoids wasted gas)
const compliant = await token.isTransferCompliant(from, to, tokenId);
if (!compliant) {
  // Surface specific module failure to user
  console.log("Transfer blocked by compliance rules");
}
```

### Module Swap at Runtime

Modules are external contracts — upgrade compliance rules without redeploying the token:

```solidity
// Deploy updated KYC module with stricter requirements
KYCModule kycV2 = new KYCModule(address(registry), 2); // min level 2

// Hot-swap
token.removeComplianceModule(IComplianceModule(address(kycV1)));
token.addComplianceModule(IComplianceModule(address(kycV2)));
```

### Available Modules

| Module | Purpose | Regulatory Basis |
|:-------|:--------|:-----------------|
| `KYCModule` | Verify both parties have active KYC | AML/KYC |
| `CountryRestrictModule` | Block restricted jurisdictions (ISO 3166-1) | OFAC / sanctions |
| `MaxHoldersModule` | Cap unique token holders | Reg D Rule 506(b) |
| `LockUpModule` | Global + per-token time-based locks | Reg S / Reg D holding periods |

### Gas Impact

Each module adds ~2,600–5,000 gas per transfer (external STATICCALL). With 4 modules, expect ~10,000–20,000 gas overhead — negligible on L2.

---

This guide is intentionally constrained to behaviors verified in this repository’s current implementation and test suite.
