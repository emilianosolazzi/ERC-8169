# ERC-721H (ERC-8169) — Current Implementation Snapshot (v2.1.x)

This document is a factual, implementation-aligned overview for reviewers and integrators.

## What ERC-721H Adds

ERC-721H extends ERC-721-compatible contracts with on-chain historical state:

- **Layer 1 (immutable origin):** `originalCreator(tokenId)`, `mintBlock(tokenId)`
- **Layer 2 (historical trail):** append-only ownership history + O(1) `hasEverOwned`
- **Layer 3 (current authority):** standard ERC-721 ownership and approvals

## Behavior Profile

ERC-721 interfaces remain compatible, with documented constraints:

- Self-transfer is rejected (`InvalidRecipient`)
- Same token cannot transfer twice in one transaction (`TokenAlreadyTransferredThisTx`)
- Same token cannot transfer twice in one block (`OwnerAlreadyRecordedForBlock`)
- Optional cooldown can block transfers until block interval elapses (`TransferCooldownActive`)

Cooldown is anchored on `lastTransferBlock`, which is initialized at mint.

## History Modes

Configurable at deployment (immutable):

- **FULL (0):** arrays + flags, richest query surface
- **FLAG_ONLY (1):** flags only, no history arrays
- **COMPRESSED (2):** hash commitment + flags, no arrays

COMPRESSED exposes final commitment via `getHistoryHash(tokenId)`; proof replay is off-chain.

## Reference Contracts

- Core: `src/ERC-721H.sol`
- Interface: `src/IERC721H.sol`
- Storage library: `src/ERC721HStorageLib.sol`
- Query library: `src/ERC721HCoreLib.sol`
- Factory + production wrapper: `src/ERC-721HFactory.sol`

## Verified Test Evidence (Current Repo)

Latest full run in this repository:

- **12 suites**
- **211 tests passed**
- **0 failed**

Coverage includes:

- Unit and integration paths
- Fuzz/property tests
- Stateful invariants
- Compatibility flows (operator approvals, safe transfers, receivers, cooldown behavior)
- Rollup smoke tests (local + optional Optimism/Arbitrum forks)
- Gas scenario tests (mint, cold transfer, warm surrogate, re-transfer path, cooldown-hit)

## Reproducible Commands

```bash
# Full suite
forge test

# Gas scenarios
forge test --match-path tests/ERC721H_Gas.t.sol --gas-report

# Compatibility flows
forge test --match-path tests/ERC721H_Compatibility.t.sol

# Invariants
forge test --match-path tests/ERC721H_Invariant.t.sol --ffi

# Rollup smoke (set RPCs to enable fork checks)
forge test --match-path tests/ERC721H_RollupForks.t.sol
```

Optional fork env vars:

```bash
export OPTIMISM_RPC_URL="https://..."
export ARBITRUM_RPC_URL="https://..."
```

## Positioning

ERC-721H is best described as a **state-augmentation extension** for ERC-721-compatible ecosystems:

- Interface-compatible for wallets/tooling
- Behaviorally constrained where anti-grief controls are enabled
- Tunable tradeoff surface across FULL / FLAG_ONLY / COMPRESSED modes

This is intended for contexts where on-chain historical composability is a first-class requirement.
