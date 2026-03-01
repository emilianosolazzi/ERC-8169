// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IERC721HCore} from "./IERC721HCore.sol";
import {IERC721HAnalytics} from "./IERC721HAnalytics.sol";

/// @title IERC721H (Legacy Aggregate)
/// @notice Backward-compatible aggregate interface that combines core + optional analytics.
/// @dev New integrations should prefer IERC721HCore (required) and IERC721HAnalytics (optional).
interface IERC721H is IERC721HCore, IERC721HAnalytics {}
