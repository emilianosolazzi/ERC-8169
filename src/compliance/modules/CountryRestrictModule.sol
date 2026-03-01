// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IComplianceModule} from "../IComplianceModule.sol";
import {IIdentityRegistry} from "../IIdentityRegistry.sol";

/// @title CountryRestrictModule — Block transfers to/from restricted jurisdictions
/// @notice Maintains a blocklist of ISO 3166-1 numeric country codes. Transfers where
///         either party's registered country is on the blocklist are rejected.
/// @dev    Jurisdiction data comes from the shared IdentityRegistry.
///         The blocklist is owner-updatable — countries can be added or removed
///         as regulatory requirements change, without redeploying.
///
///         Common country codes:
///           840 = US, 826 = GB, 276 = DE, 392 = JP, 156 = CN,
///           410 = KR, 643 = RU, 408 = KP, 364 = IR, 760 = SY
contract CountryRestrictModule is IComplianceModule {
    IIdentityRegistry public immutable identityRegistry;
    address public owner;

    /// @dev country code => true if blocked
    mapping(uint16 => bool) public blockedCountries;

    error NotOwner();
    error ZeroAddress();

    event CountryBlocked(uint16 indexed country);
    event CountryUnblocked(uint16 indexed country);

    constructor(address _identityRegistry, uint16[] memory _initialBlocked) {
        if (_identityRegistry == address(0)) revert ZeroAddress();
        identityRegistry = IIdentityRegistry(_identityRegistry);
        owner = msg.sender;

        for (uint256 i; i < _initialBlocked.length; ++i) {
            blockedCountries[_initialBlocked[i]] = true;
            emit CountryBlocked(_initialBlocked[i]);
        }
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    // ──────────── IComplianceModule ────────────

    function moduleName() external pure override returns (string memory) {
        return "Country Restriction";
    }

    function canTransfer(address from, address to, uint256 /* tokenId */)
        external
        view
        override
        returns (bool)
    {
        // Mint: check receiver only
        if (from == address(0)) {
            return !_isCountryBlocked(to);
        }
        // Burn: check sender only
        if (to == address(0)) {
            return !_isCountryBlocked(from);
        }
        // Transfer: both
        return !_isCountryBlocked(from) && !_isCountryBlocked(to);
    }

    function transferRestrictionMessage(address from, address to, uint256 /* tokenId */)
        external
        view
        override
        returns (string memory)
    {
        bool senderBlocked = from != address(0) && _isCountryBlocked(from);
        bool receiverBlocked = to != address(0) && _isCountryBlocked(to);

        if (senderBlocked && receiverBlocked) return "Sender and receiver in restricted jurisdictions";
        if (senderBlocked) return "Sender in restricted jurisdiction";
        if (receiverBlocked) return "Receiver in restricted jurisdiction";
        return "";
    }

    // ──────────── Admin ────────────

    function blockCountry(uint16 country) external onlyOwner {
        blockedCountries[country] = true;
        emit CountryBlocked(country);
    }

    function unblockCountry(uint16 country) external onlyOwner {
        blockedCountries[country] = false;
        emit CountryUnblocked(country);
    }

    function batchBlockCountries(uint16[] calldata countries) external onlyOwner {
        for (uint256 i; i < countries.length; ++i) {
            blockedCountries[countries[i]] = true;
            emit CountryBlocked(countries[i]);
        }
    }

    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ZeroAddress();
        owner = newOwner;
    }

    // ──────────── Internal ────────────

    function _isCountryBlocked(address wallet) internal view returns (bool) {
        // If wallet has no identity registered, the KYC module will catch it —
        // country check silently passes for unregistered wallets.
        try identityRegistry.getCountry(wallet) returns (uint16 country) {
            return blockedCountries[country];
        } catch {
            return false;
        }
    }
}
