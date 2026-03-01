// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/// @title IERC721HCore — Minimal historical ownership extension core
/// @notice ERC-review-friendly core primitives for provenance state.
interface IERC721HCore {
    event OwnershipHistoryRecorded(
        uint256 indexed tokenId,
        address indexed newOwner,
        uint256 timestamp
    );

    event OriginalCreatorRecorded(
        uint256 indexed tokenId,
        address indexed creator
    );

    event HistoricalTokenBurned(uint256 indexed tokenId);

    function originalCreator(uint256 tokenId) external view returns (address);

    function mintBlock(uint256 tokenId) external view returns (uint256);

    function hasEverOwned(uint256 tokenId, address account) external view returns (bool);

    function getOwnerAtBlock(uint256 tokenId, uint256 blockNumber) external view returns (address);

    function getHistoryLength(uint256 tokenId) external view returns (uint256);

    function getHistorySlice(uint256 tokenId, uint256 start, uint256 count)
        external
        view
        returns (address[] memory owners, uint256[] memory timestamps);

    function burn(uint256 tokenId) external;
}
