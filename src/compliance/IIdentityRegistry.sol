// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/// @title IIdentityRegistry — On-chain KYC/AML identity attestation registry
/// @notice Stores verification status and jurisdiction metadata for wallet addresses.
///         Designed to be deployed once and shared across multiple token contracts.
/// @dev Modeled after ERC-3643 Identity Registry, simplified for ERC-721H integration.
///      The registry is the single source of truth for KYC state — compliance modules
///      query it rather than storing identity data themselves.
///
///      Identity lifecycle:
///        1. Agent calls `registerIdentity(wallet, country, kycLevel)`
///        2. Agent can later update: `updateCountry()`, `updateKYCLevel()`
///        3. Agent or admin can revoke: `revokeIdentity(wallet)`
///        4. Compliance modules call `isVerified()` / `getCountry()` during transfer checks
interface IIdentityRegistry {
    // ──────────── Events ────────────

    event IdentityRegistered(address indexed wallet, uint16 indexed country, uint8 kycLevel);
    event IdentityRevoked(address indexed wallet);
    event IdentityUpdated(address indexed wallet, uint16 indexed country, uint8 kycLevel);
    event AgentAdded(address indexed agent);
    event AgentRemoved(address indexed agent);

    // ──────────── Errors ────────────

    error NotAgent();
    error IdentityNotFound();
    error IdentityAlreadyRegistered();
    error ZeroAddress();

    // ──────────── Views ────────────

    /// @notice Returns true if `wallet` has a valid (non-revoked) KYC identity on record.
    function isVerified(address wallet) external view returns (bool);

    /// @notice Returns the ISO 3166-1 numeric country code for `wallet`.
    /// @dev Reverts if identity not registered.
    function getCountry(address wallet) external view returns (uint16);

    /// @notice Returns the KYC verification level (0 = none, 1 = basic, 2 = enhanced, 3 = institutional).
    function getKYCLevel(address wallet) external view returns (uint8);

    // ──────────── Mutations (agent-only) ────────────

    /// @notice Register a new identity for `wallet`.
    function registerIdentity(address wallet, uint16 country, uint8 kycLevel) external;

    /// @notice Update the country code for an existing identity.
    function updateCountry(address wallet, uint16 country) external;

    /// @notice Update the KYC level for an existing identity.
    function updateKYCLevel(address wallet, uint8 kycLevel) external;

    /// @notice Revoke identity — wallet will fail all KYC checks.
    function revokeIdentity(address wallet) external;

    // ──────────── Agent management (admin-only) ────────────

    /// @notice Grant agent role to `account` (can register/update/revoke identities).
    function addAgent(address account) external;

    /// @notice Revoke agent role from `account`.
    function removeAgent(address account) external;

    /// @notice Returns true if `account` is an authorized agent.
    function isAgent(address account) external view returns (bool);
}
