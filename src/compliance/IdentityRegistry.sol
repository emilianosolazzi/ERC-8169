// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IIdentityRegistry} from "./IIdentityRegistry.sol";

/// @title IdentityRegistry — Reference KYC/AML identity registry
/// @notice Stores per-wallet verification status, country, and KYC level.
///         Agents (authorized by admin) manage identity lifecycle.
///         Deployed once, shared across multiple compliant token contracts.
/// @dev Country codes follow ISO 3166-1 numeric (e.g., 840 = US, 826 = GB, 276 = DE).
///      KYC levels: 0 = none/revoked, 1 = basic, 2 = enhanced, 3 = institutional.
contract IdentityRegistry is IIdentityRegistry {
    // ──────────── Storage ────────────

    struct Identity {
        uint16 country;    // ISO 3166-1 numeric
        uint8  kycLevel;   // 0 = none, 1 = basic, 2 = enhanced, 3 = institutional
        bool   active;     // false = revoked or never registered
    }

    address public admin;
    mapping(address => Identity) private _identities;
    mapping(address => bool) private _agents;

    // ──────────── Modifiers ────────────

    modifier onlyAdmin() {
        if (msg.sender != admin) revert NotAgent();
        _;
    }

    modifier onlyAgent() {
        if (!_agents[msg.sender] && msg.sender != admin) revert NotAgent();
        _;
    }

    // ──────────── Constructor ────────────

    constructor() {
        admin = msg.sender;
        _agents[msg.sender] = true;
        emit AgentAdded(msg.sender);
    }

    // ──────────── Views ────────────

    function isVerified(address wallet) external view override returns (bool) {
        return _identities[wallet].active && _identities[wallet].kycLevel > 0;
    }

    function getCountry(address wallet) external view override returns (uint16) {
        if (!_identities[wallet].active) revert IdentityNotFound();
        return _identities[wallet].country;
    }

    function getKYCLevel(address wallet) external view override returns (uint8) {
        if (!_identities[wallet].active) revert IdentityNotFound();
        return _identities[wallet].kycLevel;
    }

    function isAgent(address account) external view override returns (bool) {
        return _agents[account];
    }

    // ──────────── Agent Operations ────────────

    function registerIdentity(address wallet, uint16 country, uint8 kycLevel) external override onlyAgent {
        if (wallet == address(0)) revert ZeroAddress();
        if (_identities[wallet].active) revert IdentityAlreadyRegistered();

        _identities[wallet] = Identity({
            country: country,
            kycLevel: kycLevel,
            active: true
        });

        emit IdentityRegistered(wallet, country, kycLevel);
    }

    function updateCountry(address wallet, uint16 country) external override onlyAgent {
        if (!_identities[wallet].active) revert IdentityNotFound();
        _identities[wallet].country = country;
        emit IdentityUpdated(wallet, country, _identities[wallet].kycLevel);
    }

    function updateKYCLevel(address wallet, uint8 kycLevel) external override onlyAgent {
        if (!_identities[wallet].active) revert IdentityNotFound();
        _identities[wallet].kycLevel = kycLevel;
        emit IdentityUpdated(wallet, _identities[wallet].country, kycLevel);
    }

    function revokeIdentity(address wallet) external override onlyAgent {
        if (!_identities[wallet].active) revert IdentityNotFound();
        _identities[wallet].active = false;
        _identities[wallet].kycLevel = 0;
        emit IdentityRevoked(wallet);
    }

    // ──────────── Admin Operations ────────────

    function addAgent(address account) external override onlyAdmin {
        if (account == address(0)) revert ZeroAddress();
        _agents[account] = true;
        emit AgentAdded(account);
    }

    function removeAgent(address account) external override onlyAdmin {
        _agents[account] = false;
        emit AgentRemoved(account);
    }

    /// @notice Transfer admin role to a new address.
    function transferAdmin(address newAdmin) external onlyAdmin {
        if (newAdmin == address(0)) revert ZeroAddress();
        admin = newAdmin;
    }
}
