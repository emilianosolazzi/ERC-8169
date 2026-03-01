// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/// @title IERC721HAnalytics — Optional analytics/policy extension
/// @notice Convenience APIs that are useful in apps but not required by core provenance semantics.
interface IERC721HAnalytics {
    function isOriginalOwner(uint256 tokenId, address account) external view returns (bool);

    function isCurrentOwner(uint256 tokenId, address account) external view returns (bool);

    function getOwnershipHistory(uint256 tokenId)
        external
        view
        returns (address[] memory owners, uint256[] memory timestamps);

    function getTransferCount(uint256 tokenId) external view returns (uint256);

    function getEverOwnedTokens(address account) external view returns (uint256[] memory);

    function getOriginallyCreatedTokens(address creator) external view returns (uint256[] memory);

    function isEarlyAdopter(address account, uint256 blockThreshold) external view returns (bool);

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

    function totalSupply() external view returns (uint256);

    function totalMinted() external view returns (uint256);

    function getEverOwnedTokensLength(address account) external view returns (uint256);

    function getEverOwnedTokensSlice(address account, uint256 start, uint256 count)
        external
        view
        returns (uint256[] memory tokenIds);

    function getCreatedTokensLength(address creator) external view returns (uint256);

    function getCreatedTokensSlice(address creator, uint256 start, uint256 count)
        external
        view
        returns (uint256[] memory tokenIds);

    function getOwnerAtTimestamp(uint256 tokenId, uint256 timestamp) external pure returns (address);

    function transferCooldownBlocks() external view returns (uint256);
}
