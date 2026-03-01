// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "forge-std/Test.sol";
import "../src/ERC-721H.sol";
import {ERC721HStorageLib} from "../src/ERC721HStorageLib.sol";

contract ERC721H_RollupForksTest is Test {
    function _smokeBehaviorOnFork() internal {
        ERC721H nft = new ERC721H("Fork", "FRK", ERC721HStorageLib.HistoryMode.FULL);
        address alice = address(0xA11CE);
        address bob = address(0xB0B);

        nft.mint(alice);
        vm.roll(block.number + 1);

        vm.prank(alice);
        nft.transferFrom(alice, bob, 1);

        assertEq(nft.ownerOf(1), bob);
        assertEq(nft.getTransferCount(1), 1);
    }

    function test_Rollup_Anvil_LocalSmoke() public {
        // Local Anvil / no-fork environment smoke test.
        _smokeBehaviorOnFork();
    }

    function test_Rollup_OptimismFork_Smoke() public {
        string memory rpc = vm.envOr("OPTIMISM_RPC_URL", string(""));
        if (bytes(rpc).length == 0) {
            emit log("Skipping Optimism fork test: OPTIMISM_RPC_URL not set");
            return;
        }

        vm.createSelectFork(rpc);
        assertEq(block.chainid, 10, "Not on Optimism chainId 10");
        _smokeBehaviorOnFork();
    }

    function test_Rollup_ArbitrumFork_Smoke() public {
        string memory rpc = vm.envOr("ARBITRUM_RPC_URL", string(""));
        if (bytes(rpc).length == 0) {
            emit log("Skipping Arbitrum fork test: ARBITRUM_RPC_URL not set");
            return;
        }

        vm.createSelectFork(rpc);
        assertEq(block.chainid, 42161, "Not on Arbitrum chainId 42161");
        _smokeBehaviorOnFork();
    }
}
