// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/// @title IERC721HAnalytics — Optional analytics/policy extension
/// @notice Convenience APIs that are useful in apps but not required by core provenance semantics.
/// @dev Functions in this interface MAY have higher gas costs or O(n) complexity.
///      Implementations signal support via supportsInterface(type(IERC721HAnalytics).interfaceId).
///      This interface contains only view/pure functions — no events are defined here.
interface IERC721HAnalytics {
    /// @notice Returns true if `account` is the original creator of `tokenId`. O(1).
    function isOriginalOwner(uint256 tokenId, address account) external view returns (bool);

    /// @notice Returns true if `account` is the current owner of `tokenId`. O(1).
    function isCurrentOwner(uint256 tokenId, address account) external view returns (bool);

    /// @notice Returns the full ownership history arrays. O(n) where n = transfer count.
    /// @dev May be expensive for tokens with long histories. Prefer getHistorySlice() for on-chain use.
    function getOwnershipHistory(uint256 tokenId)
        external
        view
        returns (address[] memory owners, uint256[] memory timestamps);

    /// @notice Returns the number of transfers for `tokenId`. O(1).
    function getTransferCount(uint256 tokenId) external view returns (uint256);

    /// @notice Returns all token IDs ever owned by `account`. O(n) — use pagination for large sets.
    /// @dev Gas cost grows linearly with the number of tokens owned. Prefer getEverOwnedTokensSlice().
    function getEverOwnedTokens(address account) external view returns (uint256[] memory);

    /// @notice Returns all token IDs originally created by `creator`. O(n) — use pagination for large sets.
    /// @dev Gas cost grows linearly with the number of tokens created. Prefer getCreatedTokensSlice().
    function getOriginallyCreatedTokens(address creator) external view returns (uint256[] memory);

    /// @notice Returns true if `account` minted any token before `blockThreshold`. O(n).
    function isEarlyAdopter(address account, uint256 blockThreshold) external view returns (bool);

    /// @notice Returns a comprehensive provenance report. O(n) where n = transfer count.
    /// @dev Aggregates multiple storage reads; intended for off-chain or view-only use.
    function getProvenanceReport(uint256 tokenId)
        external
        view
        returns (
            address creator,
            uint256 creationBlock,
            address currentOwnerAddress,
            uint256 totalTransfers,
            address[] memory allOwners,
            uint256[] memory transferTimestamps
        );

    /// @notice Returns the current total supply (minted minus burned). O(1).
    function totalSupply() external view returns (uint256);

    /// @notice Returns the total number of tokens ever minted. O(1).
    function totalMinted() external view returns (uint256);

    /// @notice Returns the number of tokens ever owned by `account`. O(1).
    function getEverOwnedTokensLength(address account) external view returns (uint256);

    /// @notice Returns a paginated slice of tokens ever owned by `account`. O(count).
    function getEverOwnedTokensSlice(address account, uint256 start, uint256 count)
        external
        view
        returns (uint256[] memory tokenIds);

    /// @notice Returns the number of tokens originally created by `creator`. O(1).
    function getCreatedTokensLength(address creator) external view returns (uint256);

    /// @notice Returns a paginated slice of tokens created by `creator`. O(count).
    function getCreatedTokensSlice(address creator, uint256 start, uint256 count)
        external
        view
        returns (uint256[] memory tokenIds);

    /// @notice DEPRECATED. Always returns address(0). Kept for ABI backward compatibility.
    /// @dev This function is `pure` and performs no storage reads. Timestamp-based ownership
    ///      queries were removed in favor of block-based queries (getOwnerAtBlock in Core).
    function getOwnerAtTimestamp(uint256 tokenId, uint256 timestamp) external pure returns (address);

    /// @notice Returns the current transfer cooldown window in blocks. O(1).
    function transferCooldownBlocks() external view returns (uint256);
}
