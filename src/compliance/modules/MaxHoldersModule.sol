// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IComplianceModule} from "../IComplianceModule.sol";

/// @title MaxHoldersModule — Cap the total number of unique token holders
/// @notice Enforces a maximum investor/holder count for regulatory caps (e.g., Reg D
///         Rule 506(b) limits to 35 non-accredited investors, or SEC exemptions
///         that cap shareholder counts).
/// @dev    The module maintains its own holder count via `onMint`/`onBurn`/`onTransfer`
///         callbacks that the compliant token contract must invoke from its hooks.
///         This is necessary because `canTransfer` is `view` and cannot modify state.
///
///         Current holder count is tracked via a balance-based approach:
///         the token contract reports balance changes, and the module increments/
///         decrements the unique holder counter based on balance transitions (0→1, 1→0).
contract MaxHoldersModule is IComplianceModule {
    uint256 public maxHolders;
    uint256 public currentHolders;
    address public owner;
    address public tokenContract;

    /// @dev wallet => number of tokens held (reported by token contract)
    mapping(address => uint256) public holderBalance;

    error NotOwner();
    error NotTokenContract();
    error ZeroAddress();
    error InvalidMaxHolders();

    event MaxHoldersUpdated(uint256 oldMax, uint256 newMax);
    event TokenContractSet(address indexed tokenContract);

    constructor(uint256 _maxHolders) {
        if (_maxHolders == 0) revert InvalidMaxHolders();
        maxHolders = _maxHolders;
        owner = msg.sender;
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    modifier onlyToken() {
        if (msg.sender != tokenContract) revert NotTokenContract();
        _;
    }

    // ──────────── IComplianceModule ────────────

    function moduleName() external pure override returns (string memory) {
        return "Max Holders Cap";
    }

    function canTransfer(address /* from */, address to, uint256 /* tokenId */)
        external
        view
        override
        returns (bool)
    {
        // Burns always allowed (reduces holders)
        if (to == address(0)) return true;

        // If receiver already holds tokens, holder count won't increase
        if (holderBalance[to] > 0) return true;

        // New holder — check cap
        return currentHolders < maxHolders;
    }

    function transferRestrictionMessage(address /* from */, address to, uint256 /* tokenId */)
        external
        view
        override
        returns (string memory)
    {
        if (to == address(0)) return "";
        if (holderBalance[to] > 0) return "";
        if (currentHolders < maxHolders) return "";
        return "Maximum holder cap reached";
    }

    // ──────────── State Callbacks (called by token contract) ────────────

    /// @notice Called by the token contract after a successful transfer/mint/burn.
    /// @dev Must be called from `_afterTokenTransfer` to update holder tracking.
    function onTransferCompleted(address from, address to) external onlyToken {
        // Handle sender balance decrease
        if (from != address(0) && holderBalance[from] > 0) {
            holderBalance[from] -= 1;
            if (holderBalance[from] == 0) {
                currentHolders -= 1;
            }
        }

        // Handle receiver balance increase
        if (to != address(0)) {
            if (holderBalance[to] == 0) {
                currentHolders += 1;
            }
            holderBalance[to] += 1;
        }
    }

    // ──────────── Admin ────────────

    /// @notice Set the token contract address that is allowed to call state callbacks.
    function setTokenContract(address _tokenContract) external onlyOwner {
        if (_tokenContract == address(0)) revert ZeroAddress();
        tokenContract = _tokenContract;
        emit TokenContractSet(_tokenContract);
    }

    function setMaxHolders(uint256 _maxHolders) external onlyOwner {
        if (_maxHolders == 0) revert InvalidMaxHolders();
        uint256 old = maxHolders;
        maxHolders = _maxHolders;
        emit MaxHoldersUpdated(old, _maxHolders);
    }

    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ZeroAddress();
        owner = newOwner;
    }
}
