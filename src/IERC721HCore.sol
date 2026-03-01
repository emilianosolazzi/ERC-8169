// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/// @title IERC721HCore — Minimal historical ownership extension core
/// @notice ERC-review-friendly core primitives for provenance state.
/// @dev All view functions in this interface MUST execute in O(1) or O(log n) time.
///      Events are defined here; the optional Analytics extension contains only view/pure functions.
interface IERC721HCore {
    /// @notice Emitted when a new owner is appended to a token's ownership history.
    event OwnershipHistoryRecorded(
        uint256 indexed tokenId,
        address indexed newOwner,
        uint256 timestamp
    );

    /// @notice Emitted when a token's original creator is recorded at mint time.
    event OriginalCreatorRecorded(
        uint256 indexed tokenId,
        address indexed creator
    );

    /// @notice Emitted when a historical token is burned (history is preserved).
    event HistoricalTokenBurned(uint256 indexed tokenId);

    /// @notice Returns the original minter/creator of `tokenId`. O(1).
    function originalCreator(uint256 tokenId) external view returns (address);

    /// @notice Returns the block number at which `tokenId` was minted. O(1).
    function mintBlock(uint256 tokenId) external view returns (uint256);

    /// @notice Returns true if `account` has ever owned `tokenId`. MUST be O(1).
    /// @dev Implementations SHOULD use a nested mapping(uint256 => mapping(address => bool)).
    function hasEverOwned(uint256 tokenId, address account) external view returns (bool);

    /// @notice Returns the owner of `tokenId` at `blockNumber`. O(log n) via binary search.
    /// @dev Returns address(0) if not yet minted at `blockNumber`.
    function getOwnerAtBlock(uint256 tokenId, uint256 blockNumber) external view returns (address);

    /// @notice Returns the number of ownership entries for `tokenId`. O(1).
    function getHistoryLength(uint256 tokenId) external view returns (uint256);

    /// @notice Returns a paginated slice of the ownership history. O(count).
    function getHistorySlice(uint256 tokenId, uint256 start, uint256 count)
        external
        view
        returns (address[] memory owners, uint256[] memory timestamps);

    /// @notice Burns `tokenId`. History layers (1 & 2) are preserved after burn.
    function burn(uint256 tokenId) external;
}
