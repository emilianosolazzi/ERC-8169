// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IComplianceModule} from "../IComplianceModule.sol";
import {IIdentityRegistry} from "../IIdentityRegistry.sol";

/// @title KYCModule — Requires verified KYC for sender and receiver
/// @notice Enforces that both parties in a transfer have active KYC verification
///         in the linked IdentityRegistry. Optionally requires a minimum KYC level.
/// @dev    - Mints (from == address(0)): only the receiver is checked.
///         - Burns (to == address(0)): only the sender is checked.
///         - Transfers: both parties must be verified.
///
///         The minimum KYC level can be updated by the module owner to tighten or
///         relax requirements without redeploying or swapping the module.
contract KYCModule is IComplianceModule {
    IIdentityRegistry public immutable identityRegistry;
    address public owner;
    uint8 public minimumKYCLevel;

    error NotOwner();
    error ZeroAddress();

    event MinimumKYCLevelUpdated(uint8 oldLevel, uint8 newLevel);

    constructor(address _identityRegistry, uint8 _minimumKYCLevel) {
        if (_identityRegistry == address(0)) revert ZeroAddress();
        identityRegistry = IIdentityRegistry(_identityRegistry);
        minimumKYCLevel = _minimumKYCLevel;
        owner = msg.sender;
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    // ──────────── IComplianceModule ────────────

    function moduleName() external pure override returns (string memory) {
        return "KYC Verification";
    }

    function canTransfer(address from, address to, uint256 /* tokenId */)
        external
        view
        override
        returns (bool)
    {
        // Mint: check receiver only
        if (from == address(0)) {
            return _isCompliant(to);
        }
        // Burn: check sender only
        if (to == address(0)) {
            return _isCompliant(from);
        }
        // Transfer: check both
        return _isCompliant(from) && _isCompliant(to);
    }

    function transferRestrictionMessage(address from, address to, uint256 /* tokenId */)
        external
        view
        override
        returns (string memory)
    {
        bool senderOk = from == address(0) || _isCompliant(from);
        bool receiverOk = to == address(0) || _isCompliant(to);

        if (!senderOk && !receiverOk) return "Sender and receiver lack required KYC";
        if (!senderOk) return "Sender lacks required KYC verification";
        if (!receiverOk) return "Receiver lacks required KYC verification";
        return "";
    }

    // ──────────── Admin ────────────

    function setMinimumKYCLevel(uint8 newLevel) external onlyOwner {
        uint8 oldLevel = minimumKYCLevel;
        minimumKYCLevel = newLevel;
        emit MinimumKYCLevelUpdated(oldLevel, newLevel);
    }

    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ZeroAddress();
        owner = newOwner;
    }

    // ──────────── Internal ────────────

    function _isCompliant(address wallet) internal view returns (bool) {
        if (!identityRegistry.isVerified(wallet)) return false;
        if (minimumKYCLevel == 0) return true;
        return identityRegistry.getKYCLevel(wallet) >= minimumKYCLevel;
    }
}
