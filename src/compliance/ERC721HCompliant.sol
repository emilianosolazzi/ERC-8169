// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ERC721H} from "../ERC-721H.sol";
import {ERC721HStorageLib} from "../ERC721HStorageLib.sol";
import {ComplianceLib} from "./ComplianceLib.sol";
import {IComplianceModule} from "./IComplianceModule.sol";
import {MaxHoldersModule} from "./modules/MaxHoldersModule.sol";

/// @title ERC721HCompliant — ERC-721H with ERC-3643-Inspired Regulatory Compliance
/// @author ERC-8169 Contributors
///
/// @notice Reference implementation showing how to integrate the modular compliance
///         framework with ERC-721H. This contract enforces KYC, jurisdiction, lock-up,
///         and holder-cap restrictions via pluggable compliance modules.
///
/// @dev Architecture:
///
///      ┌────────────────────────────────────────────────────────────────┐
///      │                    ERC721HCompliant                           │
///      │                                                                │
///      │  ┌──────────────────┐    ┌──────────────────────────────────┐ │
///      │  │   ERC-721H Base  │    │   ComplianceLib.ComplianceState  │ │
///      │  │  (3-layer owner) │    │   ┌─ KYCModule                  │ │
///      │  │                  │    │   ├─ CountryRestrictModule       │ │
///      │  │  _beforeTransfer─┼───►│   ├─ MaxHoldersModule           │ │
///      │  │  _afterTransfer──┼───►│   └─ LockUpModule               │ │
///      │  └──────────────────┘    └──────────────────────────────────┘ │
///      └────────────────────────────────────────────────────────────────┘
///
///  Hook Integration:
///    1. `_beforeTokenTransfer`  → ComplianceLib.enforceTransfer()
///       Reverts with ComplianceCheckFailed if ANY module rejects the transfer.
///
///    2. `_afterTokenTransfer`   → MaxHoldersModule.onTransferCompleted()
///       Updates holder tracking state for the MaxHolders cap module.
///
///  Module Management:
///    - Only the contract owner can add/remove compliance modules.
///    - Modules are external contracts — they can be upgraded by deploying new
///      module contracts and swapping them (add new → remove old).
///    - Maximum 10 modules per ComplianceLib.MAX_MODULES.
///
///  Deployment Checklist:
///    1. Deploy IdentityRegistry → register agents → register investor identities
///    2. Deploy compliance modules (KYC, Country, LockUp, MaxHolders)
///    3. Deploy ERC721HCompliant
///    4. Call addComplianceModule() for each module
///    5. Call MaxHoldersModule.setTokenContract(address(this))
///    6. Call LockUpModule.setTokenContract(address(this)) if using lock-ups
///    7. Mint tokens to verified investors
///
///  Gas Considerations:
///    - Each compliance module adds ~2,600-5,000 gas per transfer (external STATICCALL)
///    - 4 modules ≈ 10,000-20,000 gas overhead per transfer
///    - Module ordering matters: put cheapest/most-likely-to-fail checks first
contract ERC721HCompliant is ERC721H {
    using ComplianceLib for ComplianceLib.ComplianceState;

    // ──────────── Storage ────────────

    ComplianceLib.ComplianceState private _compliance;

    /// @dev Address of MaxHoldersModule (if installed) for _afterTokenTransfer callback.
    ///      Set to address(0) if not using holder cap tracking.
    MaxHoldersModule public maxHoldersModule;

    // ──────────── Errors ────────────

    error ComplianceModuleRequired();

    // ──────────── Events ────────────

    event MaxHoldersModuleSet(address indexed module);

    // ──────────── Constructor ────────────

    /// @param name_   Token collection name
    /// @param symbol_ Token symbol
    /// @param mode_   History mode: FULL(0), FLAG_ONLY(1), COMPRESSED(2)
    constructor(
        string memory name_,
        string memory symbol_,
        ERC721HStorageLib.HistoryMode mode_
    ) ERC721H(name_, symbol_, mode_) {}

    // ──────────── Compliance Module Management ────────────

    /// @notice Add a compliance module. Only owner.
    /// @dev Modules are checked in insertion order. Put cheap checks first.
    function addComplianceModule(IComplianceModule module) external onlyOwner {
        _compliance.addModule(module);
    }

    /// @notice Remove a compliance module. Only owner.
    function removeComplianceModule(IComplianceModule module) external onlyOwner {
        _compliance.removeModule(module);
    }

    /// @notice Set the MaxHoldersModule reference for _afterTokenTransfer callbacks.
    /// @dev Set to address(0) to disable holder tracking.
    function setMaxHoldersModule(MaxHoldersModule _module) external onlyOwner {
        maxHoldersModule = _module;
        emit MaxHoldersModuleSet(address(_module));
    }

    // ──────────── View Helpers ────────────

    /// @notice Check whether a transfer would pass all compliance checks.
    /// @dev Useful for front-end pre-flight validation before attempting a transfer.
    function isTransferCompliant(address from, address to, uint256 tokenId)
        external
        view
        returns (bool)
    {
        return _compliance.isTransferAllowed(from, to, tokenId);
    }

    /// @notice Returns the number of active compliance modules.
    function complianceModuleCount() external view returns (uint256) {
        return _compliance.moduleCount();
    }

    /// @notice Returns the compliance module at the given index.
    function complianceModuleAt(uint256 index) external view returns (IComplianceModule) {
        return _compliance.moduleAt(index);
    }

    // ──────────── Hook Overrides ────────────

    /// @notice Enforce compliance before any token transfer.
    /// @dev Runs all registered modules via ComplianceLib. Reverts with
    ///      ComplianceCheckFailed(moduleIndex, moduleName, reason) on failure.
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal virtual override {
        super._beforeTokenTransfer(from, to, tokenId);
        _compliance.enforceTransfer(from, to, tokenId);
    }

    /// @notice Update holder tracking after successful transfers.
    /// @dev Only calls MaxHoldersModule if it's been configured.
    function _afterTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal virtual override {
        super._afterTokenTransfer(from, to, tokenId);

        // Update holder count tracking for MaxHolders cap
        if (address(maxHoldersModule) != address(0)) {
            maxHoldersModule.onTransferCompleted(from, to);
        }
    }
}
