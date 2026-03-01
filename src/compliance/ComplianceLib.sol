// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IComplianceModule} from "./IComplianceModule.sol";

/// @title ComplianceLib — Modular compliance orchestration for ERC-721H
/// @notice Manages an ordered list of compliance modules and runs transfer checks
///         against all of them. Designed to be used as storage inside a compliant
///         token contract — the token calls `enforceTransfer()` from its
///         `_beforeTokenTransfer` hook.
///
/// @dev Architecture (ERC-3643-inspired, adapted for ERC-721H):
///
///      ┌──────────────────────────────────────────────┐
///      │  ERC721HCompliant (token contract)           │
///      │    _beforeTokenTransfer(from, to, tokenId)   │
///      │      └─ ComplianceLib.enforceTransfer(...)   │
///      │            ├─ Module[0].canTransfer(...)      │
///      │            ├─ Module[1].canTransfer(...)      │
///      │            └─ Module[N].canTransfer(...)      │
///      └──────────────────────────────────────────────┘
///
///      Modules are external contracts implementing IComplianceModule.
///      They can be added, removed, or replaced without redeploying the token.
///      This is the "upgradable" dimension — compliance rules evolve by
///      swapping modules, not by proxy upgrades.
library ComplianceLib {
    // ──────────── Errors ────────────

    /// @notice Thrown when a compliance module rejects a transfer.
    /// @param moduleIndex  Index of the failing module in the modules array.
    /// @param moduleName   Human-readable name of the failing module.
    /// @param reason       Why the transfer was rejected.
    error ComplianceCheckFailed(uint256 moduleIndex, string moduleName, string reason);

    /// @notice Thrown when trying to add a module that is already registered.
    error ModuleAlreadyRegistered(address module);

    /// @notice Thrown when trying to remove a module that is not registered.
    error ModuleNotRegistered(address module);

    /// @notice Thrown when the module cap would be exceeded.
    error TooManyModules();

    // ──────────── Events ────────────

    event ComplianceModuleAdded(address indexed module, string name);
    event ComplianceModuleRemoved(address indexed module, string name);

    // ──────────── Storage ────────────

    /// @dev Maximum modules per token to bound gas cost of transfer checks.
    uint256 internal constant MAX_MODULES = 10;

    struct ComplianceState {
        IComplianceModule[] modules;
        mapping(address => bool) registered;
    }

    // ──────────── Module Management ────────────

    /// @notice Add a compliance module. Reverts if already registered or cap reached.
    function addModule(ComplianceState storage self, IComplianceModule module) internal {
        if (self.registered[address(module)]) revert ModuleAlreadyRegistered(address(module));
        if (self.modules.length >= MAX_MODULES) revert TooManyModules();

        self.modules.push(module);
        self.registered[address(module)] = true;

        emit ComplianceModuleAdded(address(module), module.moduleName());
    }

    /// @notice Remove a compliance module. Swap-and-pop for gas efficiency.
    function removeModule(ComplianceState storage self, IComplianceModule module) internal {
        if (!self.registered[address(module)]) revert ModuleNotRegistered(address(module));

        uint256 len = self.modules.length;
        for (uint256 i; i < len; ++i) {
            if (address(self.modules[i]) == address(module)) {
                // Swap with last, then pop
                self.modules[i] = self.modules[len - 1];
                self.modules.pop();
                break;
            }
        }
        self.registered[address(module)] = false;

        emit ComplianceModuleRemoved(address(module), module.moduleName());
    }

    // ──────────── Transfer Enforcement ────────────

    /// @notice Check all modules and revert on the first failure.
    /// @dev Called from `_beforeTokenTransfer`. Gas cost is O(modules.length).
    function enforceTransfer(
        ComplianceState storage self,
        address from,
        address to,
        uint256 tokenId
    ) internal view {
        uint256 len = self.modules.length;
        for (uint256 i; i < len; ++i) {
            IComplianceModule mod = self.modules[i];
            if (!mod.canTransfer(from, to, tokenId)) {
                revert ComplianceCheckFailed(
                    i,
                    mod.moduleName(),
                    mod.transferRestrictionMessage(from, to, tokenId)
                );
            }
        }
    }

    // ──────────── Views ────────────

    /// @notice Check whether a transfer would pass all compliance modules without reverting.
    function isTransferAllowed(
        ComplianceState storage self,
        address from,
        address to,
        uint256 tokenId
    ) internal view returns (bool) {
        uint256 len = self.modules.length;
        for (uint256 i; i < len; ++i) {
            if (!self.modules[i].canTransfer(from, to, tokenId)) {
                return false;
            }
        }
        return true;
    }

    /// @notice Returns the number of registered modules.
    function moduleCount(ComplianceState storage self) internal view returns (uint256) {
        return self.modules.length;
    }

    /// @notice Returns the module at the given index.
    function moduleAt(ComplianceState storage self, uint256 index) internal view returns (IComplianceModule) {
        return self.modules[index];
    }
}
