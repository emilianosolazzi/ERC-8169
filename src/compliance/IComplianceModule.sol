// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/// @title IComplianceModule — Pluggable regulatory compliance check
/// @notice Each module implements a single compliance rule (KYC, country, lock-up, etc.).
///         Modules are stateless with respect to the token contract — they query external
///         registries or their own storage to decide whether a transfer is allowed.
/// @dev Inspired by ERC-3643 (T-REX) compliance architecture, adapted for ERC-721H.
///      Modules MUST be idempotent and SHOULD NOT modify state during `canTransfer` calls.
interface IComplianceModule {
    /// @notice Human-readable name of this compliance module.
    function moduleName() external view returns (string memory);

    /// @notice Returns true if the transfer is allowed under this module's rules.
    /// @param from   Sender (address(0) for mint).
    /// @param to     Receiver (address(0) for burn).
    /// @param tokenId The token being transferred.
    /// @return allowed True if the transfer passes this module's compliance check.
    function canTransfer(address from, address to, uint256 tokenId) external view returns (bool allowed);

    /// @notice Returns a human-readable reason why the transfer would fail.
    /// @dev    Returns empty string if `canTransfer` would return true.
    function transferRestrictionMessage(address from, address to, uint256 tokenId)
        external
        view
        returns (string memory);
}
