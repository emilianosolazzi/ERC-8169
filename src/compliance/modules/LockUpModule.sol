// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IComplianceModule} from "../IComplianceModule.sol";

/// @title LockUpModule — Time-based transfer restrictions
/// @notice Enforces per-token or global lock-up periods during which tokens cannot
///         be transferred. Common in securities issuance:
///           - Reg S: 40-day distribution compliance period
///           - Reg D: 6-12 month holding period
///           - SAFE/Convertible notes: post-conversion lock-up
///
/// @dev    Two lock-up mechanisms:
///         1. Global lock-up: all tokens locked until a contract-wide timestamp.
///         2. Per-token lock-up: individual tokens locked until their specific timestamp.
///
///         Per-token locks are set by the token contract (via `setTokenLockUp`) when
///         minting or distributing tokens. Global lock is set by the module owner.
///
///         Lock-ups are checked via `block.timestamp` comparison at transfer time.
///         Mints are always allowed (lock starts after mint). Burns are always allowed.
contract LockUpModule is IComplianceModule {
    address public owner;
    address public tokenContract;

    /// @notice Global lock-up timestamp — no tokens transferable before this time.
    uint256 public globalLockUntil;

    /// @dev tokenId => lock-up expiry timestamp (0 = no per-token lock)
    mapping(uint256 => uint256) public tokenLockUntil;

    error NotOwner();
    error NotTokenContract();
    error ZeroAddress();

    event GlobalLockUpdated(uint256 lockUntil);
    event TokenLockUpdated(uint256 indexed tokenId, uint256 lockUntil);
    event TokenContractSet(address indexed tokenContract);

    constructor() {
        owner = msg.sender;
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    modifier onlyTokenOrOwner() {
        if (msg.sender != tokenContract && msg.sender != owner) revert NotTokenContract();
        _;
    }

    // ──────────── IComplianceModule ────────────

    function moduleName() external pure override returns (string memory) {
        return "Lock-Up Period";
    }

    function canTransfer(address from, address /* to */, uint256 tokenId)
        external
        view
        override
        returns (bool)
    {
        // Mints always allowed (lock starts after mint)
        if (from == address(0)) return true;

        // Global lock check
        if (block.timestamp < globalLockUntil) return false;

        // Per-token lock check
        if (block.timestamp < tokenLockUntil[tokenId]) return false;

        return true;
    }

    function transferRestrictionMessage(address from, address /* to */, uint256 tokenId)
        external
        view
        override
        returns (string memory)
    {
        if (from == address(0)) return "";

        if (block.timestamp < globalLockUntil) {
            return "Global lock-up period active";
        }

        if (block.timestamp < tokenLockUntil[tokenId]) {
            return "Token-specific lock-up period active";
        }

        return "";
    }

    // ──────────── Admin ────────────

    /// @notice Set a global lock-up timestamp. Set to 0 to disable.
    function setGlobalLockUp(uint256 lockUntil) external onlyOwner {
        globalLockUntil = lockUntil;
        emit GlobalLockUpdated(lockUntil);
    }

    /// @notice Set per-token lock-up. Called by the token contract at mint time,
    ///         or by the owner for manual adjustments.
    function setTokenLockUp(uint256 tokenId, uint256 lockUntil) external onlyTokenOrOwner {
        tokenLockUntil[tokenId] = lockUntil;
        emit TokenLockUpdated(tokenId, lockUntil);
    }

    /// @notice Batch set lock-ups for multiple tokens.
    function batchSetTokenLockUp(uint256[] calldata tokenIds, uint256 lockUntil) external onlyTokenOrOwner {
        for (uint256 i; i < tokenIds.length; ++i) {
            tokenLockUntil[tokenIds[i]] = lockUntil;
            emit TokenLockUpdated(tokenIds[i], lockUntil);
        }
    }

    function setTokenContract(address _tokenContract) external onlyOwner {
        if (_tokenContract == address(0)) revert ZeroAddress();
        tokenContract = _tokenContract;
        emit TokenContractSet(_tokenContract);
    }

    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ZeroAddress();
        owner = newOwner;
    }
}
