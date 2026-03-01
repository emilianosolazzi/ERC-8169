// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/**
 * @title ERC721HStorageLib — Low-Level Storage Operations for ERC-721H
 * @author Emiliano Solazzi — 2026
 * @notice Manages Layer 1 (Immutable Origin) and Layer 2 (Historical Trail) storage.
 * @dev All functions are `internal` and inlined at compile time — zero runtime gas overhead.
 *      Callers maintain a single `HistoryStorage` struct that holds all ownership mappings.
 *
 *      HistoryStorage contains:
 *        Layer 1: originalCreator, mintBlock, createdTokens
 *        Layer 2: ownershipHistory, ownershipTimestamps, ownershipBlocks,
 *                 everOwnedTokens, hasOwnedToken
 *
 *      HISTORY MODES (configurable per-contract):
 *        - FULL (0):       Default. Complete arrays + flags. Supports all queries.
 *        - FLAG_ONLY (1):  Only hasOwnedToken mapping — no arrays. Minimal storage.
 *                          getOwnershipHistory() returns empty. hasEverOwned() still O(1).
 *                          ~60% gas savings per transfer vs FULL mode.
 *        - COMPRESSED (2): Hash-chain commitment + flags. On-chain proof of history
 *                          without arrays. historyHash is updated on each transfer:
 *                          newHash = keccak256(prevHash, owner, block, timestamp).
 *                          Full history must be reconstructed off-chain from events.
 *
 *      Key operations:
 *        - recordMint()          : Initialize Layer 1 + Layer 2 at mint
 *        - recordTransfer()      : Append to Layer 2 on transfer (auto-deduplicates)
 *        - isSameBlockTransfer() : Sybil guard derived from existing data — zero extra storage
 *        - getOwnerAtBlock()     : O(log n) binary search for owner at any arbitrary block
 *        - Pagination helpers    : Anti-griefing slices for large histories
 *
 * @custom:version 2.1.0
 */
library ERC721HStorageLib {
    // ──────────────────────────────────────────────
    //  History Mode Enum
    // ──────────────────────────────────────────────

    /// @notice Configurable history storage mode.
    /// @dev Set once at construction. Cannot be changed after deployment.
    ///      FULL:       Arrays + flags. All queries supported. Highest gas cost.
    ///      FLAG_ONLY:  Flags only. hasEverOwned() works. No arrays. Lowest gas cost.
    ///      COMPRESSED: Hash chain + flags. On-chain commitment, off-chain reconstruction.
    enum HistoryMode {
        FULL,        // 0: Default — complete arrays
        FLAG_ONLY,   // 1: Only hasOwnedToken mapping, no arrays  
        COMPRESSED   // 2: Hash chain + flags, no arrays
    }

    // ──────────────────────────────────────────────
    //  Storage Struct
    // ──────────────────────────────────────────────

    struct HistoryStorage {
        /// @dev History mode — set once at construction.
        HistoryMode mode;

        /// @dev Layer 1: Immutable Origin
        mapping(uint256 => address) originalCreator;
        mapping(uint256 => uint256) mintBlock;
        mapping(address => uint256[]) createdTokens;

        /// @dev Layer 2: Historical Trail (FULL mode uses all; FLAG_ONLY uses only hasOwnedToken)
        mapping(uint256 => address[]) ownershipHistory;
        mapping(uint256 => uint256[]) ownershipTimestamps;
        mapping(uint256 => uint256[]) ownershipBlocks;
        mapping(address => uint256[]) everOwnedTokens;
        mapping(uint256 => mapping(address => bool)) hasOwnedToken;

        /// @dev COMPRESSED mode: hash chain per token — keccak256(prevHash, owner, block, timestamp)
        mapping(uint256 => bytes32) historyHash;

        /// @dev Per-token last transfer block — used by cooldown guard in all modes
        ///      (redundant with ownershipBlocks in FULL mode but needed for FLAG_ONLY/COMPRESSED)
        mapping(uint256 => uint256) lastTransferBlock;
    }

    // ──────────────────────────────────────────────
    //  Write Operations
    // ──────────────────────────────────────────────

    /// @notice Records Layer 1 (origin) and Layer 2 (first history entry) at mint.
    /// @dev Behavior varies by history mode:
    ///      FULL:       Full arrays + flags + createdTokens
    ///      FLAG_ONLY:  hasOwnedToken flag + lastTransferBlock only (no arrays)
    ///      COMPRESSED: Hash chain + flag + lastTransferBlock (no arrays)
    /// @param self      The HistoryStorage struct in storage
    /// @param tokenId   The newly minted token ID
    /// @param to        The mint recipient (becomes originalCreator)
    /// @param blockNum  The current block number
    /// @param timestamp The current block timestamp
    function recordMint(
        HistoryStorage storage self,
        uint256 tokenId,
        address to,
        uint256 blockNum,
        uint256 timestamp
    ) internal {
        // Layer 1: immutable origin (always recorded regardless of mode)
        self.originalCreator[tokenId] = to;
        self.mintBlock[tokenId] = blockNum;
        self.lastTransferBlock[tokenId] = blockNum;

        // Layer 2: mode-dependent history recording
        if (self.mode == HistoryMode.FULL) {
            self.createdTokens[to].push(tokenId);
            self.ownershipHistory[tokenId].push(to);
            self.ownershipTimestamps[tokenId].push(timestamp);
            self.ownershipBlocks[tokenId].push(blockNum);
            self.everOwnedTokens[to].push(tokenId);
        } else if (self.mode == HistoryMode.COMPRESSED) {
            self.createdTokens[to].push(tokenId);
            // Initialize hash chain: H₀ = keccak256(0x00, to, blockNum, timestamp)
            self.historyHash[tokenId] = keccak256(
                abi.encodePacked(bytes32(0), to, blockNum, timestamp)
            );
        }
        // FLAG_ONLY and COMPRESSED both set the flag
        self.hasOwnedToken[tokenId][to] = true;
    }

    /// @notice Appends a new owner to Layer 2 history on transfer.
    /// @dev Mode-dependent:
    ///      FULL:       Appends to arrays + deduplicates everOwnedTokens.
    ///      FLAG_ONLY:  Sets hasOwnedToken flag only. No arrays touched.
    ///      COMPRESSED: Updates hash chain + sets flag. No arrays.
    function recordTransfer(
        HistoryStorage storage self,
        uint256 tokenId,
        address to,
        uint256 blockNum,
        uint256 timestamp
    ) internal {
        self.lastTransferBlock[tokenId] = blockNum;

        if (self.mode == HistoryMode.FULL) {
            self.ownershipHistory[tokenId].push(to);
            self.ownershipTimestamps[tokenId].push(timestamp);
            self.ownershipBlocks[tokenId].push(blockNum);

            if (!self.hasOwnedToken[tokenId][to]) {
                self.everOwnedTokens[to].push(tokenId);
            }
        } else if (self.mode == HistoryMode.COMPRESSED) {
            // Hₙ = keccak256(Hₙ₋₁, to, blockNum, timestamp)
            self.historyHash[tokenId] = keccak256(
                abi.encodePacked(self.historyHash[tokenId], to, blockNum, timestamp)
            );
        }
        // All modes set the flag
        self.hasOwnedToken[tokenId][to] = true;
    }

    // ──────────────────────────────────────────────
    //  Sybil Guard
    // ──────────────────────────────────────────────

    /// @notice Returns true if `tokenId` already changed ownership at `currentBlock`.
    /// @dev Uses `lastTransferBlock` mapping — works in all history modes.
    function isSameBlockTransfer(
        HistoryStorage storage self,
        uint256 tokenId,
        uint256 currentBlock
    ) internal view returns (bool) {
        return self.lastTransferBlock[tokenId] == currentBlock;
    }

    /// @notice Returns the block number of the last recorded transfer for `tokenId`.
    /// @dev Returns 0 if no transfers recorded. Used by the cooldown guard.
    function getLastTransferBlock(
        HistoryStorage storage self,
        uint256 tokenId
    ) internal view returns (uint256) {
        return self.lastTransferBlock[tokenId];
    }

    // ──────────────────────────────────────────────
    //  Existence & Identity
    // ──────────────────────────────────────────────

    /// @notice Returns true if `tokenId` was ever minted (survives burn).
    /// @dev Uses Layer 1 originalCreator — non-zero means token existed.
    function exists(HistoryStorage storage self, uint256 tokenId) internal view returns (bool) {
        return self.originalCreator[tokenId] != address(0);
    }

    /// @notice O(1) check: has `account` ever owned `tokenId`?
    function hasEverOwned(
        HistoryStorage storage self,
        uint256 tokenId,
        address account
    ) internal view returns (bool) {
        return self.hasOwnedToken[tokenId][account];
    }

    // ──────────────────────────────────────────────
    //  Historical Query — O(log n) Binary Search
    // ──────────────────────────────────────────────

    /// @notice Returns the owner of `tokenId` at any arbitrary `blockNumber`.
    /// @dev Binary search over chronological _ownershipBlocks[]. Finds the last
    ///      entry at-or-before `blockNumber`.
    ///      Returns address(0) if token was not yet minted at `blockNumber`.
    ///      NOTE: Only functional in FULL history mode. In FLAG_ONLY and COMPRESSED modes,
    ///      always returns address(0) because no ownership arrays are stored.
    ///
    ///      EXAMPLE:
    ///        Block 100: Mint → Alice    → getOwnerAtBlock(1, 100) = Alice
    ///        Block 150: (nothing)        → getOwnerAtBlock(1, 150) = Alice  ✓
    ///        Block 200: Transfer → Bob   → getOwnerAtBlock(1, 200) = Bob
    ///        Block 250: (nothing)        → getOwnerAtBlock(1, 250) = Bob    ✓
    function getOwnerAtBlock(
        HistoryStorage storage self,
        uint256 tokenId,
        uint256 blockNumber
    ) internal view returns (address) {
        uint256[] storage blocks = self.ownershipBlocks[tokenId];
        uint256 len = blocks.length;
        if (len == 0) return address(0);
        if (blockNumber < blocks[0]) return address(0);

        uint256 low = 0;
        uint256 high = len - 1;
        while (low < high) {
            uint256 mid = low + (high - low + 1) / 2;
            if (blocks[mid] <= blockNumber) {
                low = mid;
            } else {
                high = mid - 1;
            }
        }
        return self.ownershipHistory[tokenId][low];
    }

    // ──────────────────────────────────────────────
    //  Token History Pagination
    // ──────────────────────────────────────────────

    /// @notice Returns the total number of entries in `tokenId`'s ownership history.
    function getHistoryLength(
        HistoryStorage storage self,
        uint256 tokenId
    ) internal view returns (uint256) {
        return self.ownershipHistory[tokenId].length;
    }

    /// @notice Returns a paginated slice of ownership history.
    /// @dev Returns empty arrays if `start >= length`.
    function getHistorySlice(
        HistoryStorage storage self,
        uint256 tokenId,
        uint256 start,
        uint256 count
    ) internal view returns (address[] memory owners, uint256[] memory timestamps) {
        uint256 len = self.ownershipHistory[tokenId].length;
        if (start >= len) return (new address[](0), new uint256[](0));
        uint256 end = start + count;
        if (end > len) end = len;
        uint256 sliceLen = end - start;
        owners = new address[](sliceLen);
        timestamps = new uint256[](sliceLen);
        for (uint256 i = 0; i < sliceLen; i++) {
            owners[i] = self.ownershipHistory[tokenId][start + i];
            timestamps[i] = self.ownershipTimestamps[tokenId][start + i];
        }
    }

    // ──────────────────────────────────────────────
    //  Per-Address Pagination
    // ──────────────────────────────────────────────

    /// @notice Returns the number of distinct tokens `account` has ever owned.
    function getEverOwnedTokensLength(
        HistoryStorage storage self,
        address account
    ) internal view returns (uint256) {
        return self.everOwnedTokens[account].length;
    }

    /// @notice Returns a paginated slice of tokens `account` has ever owned.
    function getEverOwnedTokensSlice(
        HistoryStorage storage self,
        address account,
        uint256 start,
        uint256 count
    ) internal view returns (uint256[] memory tokenIds) {
        uint256 len = self.everOwnedTokens[account].length;
        if (start >= len) return new uint256[](0);
        uint256 end = start + count;
        if (end > len) end = len;
        uint256 sliceLen = end - start;
        tokenIds = new uint256[](sliceLen);
        for (uint256 i = 0; i < sliceLen; i++) {
            tokenIds[i] = self.everOwnedTokens[account][start + i];
        }
    }

    /// @notice Returns the number of tokens `creator` originally minted.
    function getCreatedTokensLength(
        HistoryStorage storage self,
        address creator
    ) internal view returns (uint256) {
        return self.createdTokens[creator].length;
    }

    /// @notice Returns a paginated slice of tokens `creator` originally minted.
    function getCreatedTokensSlice(
        HistoryStorage storage self,
        address creator,
        uint256 start,
        uint256 count
    ) internal view returns (uint256[] memory tokenIds) {
        uint256 len = self.createdTokens[creator].length;
        if (start >= len) return new uint256[](0);
        uint256 end = start + count;
        if (end > len) end = len;
        uint256 sliceLen = end - start;
        tokenIds = new uint256[](sliceLen);
        for (uint256 i = 0; i < sliceLen; i++) {
            tokenIds[i] = self.createdTokens[creator][start + i];
        }
    }

    // ──────────────────────────────────────────────
    //  History Mode Queries
    // ──────────────────────────────────────────────

    /// @notice Returns the current history mode.
    function getMode(
        HistoryStorage storage self
    ) internal view returns (HistoryMode) {
        return self.mode;
    }

    /// @notice Returns the COMPRESSED-mode hash chain commitment for `tokenId`.
    /// @dev Only meaningful in COMPRESSED mode. Returns bytes32(0) in other modes.
    ///      The hash is computed as: Hₙ = keccak256(Hₙ₋₁ ‖ owner ‖ blockNum ‖ timestamp)
    ///      Full history can be verified off-chain by replaying events and recomputing.
    function getHistoryHash(
        HistoryStorage storage self,
        uint256 tokenId
    ) internal view returns (bytes32) {
        return self.historyHash[tokenId];
    }
}
