// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {ERC721H} from "../src/ERC-721H.sol";
import {ERC721HStorageLib} from "../src/ERC721HStorageLib.sol";

contract ERC721H_RandomChains is Test {
    ERC721H internal nft;
    address internal constant OWNER = address(0xAAAA);

    function setUp() public {
        vm.prank(OWNER);
        nft = new ERC721H("Historical NFT", "HNFT", ERC721HStorageLib.HistoryMode.FULL);
    }

    function testFuzz_RandomizedOwnershipChainsAcrossTokens(uint8 tokenCount, uint256 seed) public {
        uint8 n = uint8(bound(tokenCount, 2, 25));

        address[] memory actors = new address[](8);
        actors[0] = address(0x1001);
        actors[1] = address(0x1002);
        actors[2] = address(0x1003);
        actors[3] = address(0x1004);
        actors[4] = address(0x1005);
        actors[5] = address(0x1006);
        actors[6] = address(0x1007);
        actors[7] = address(0x1008);

        uint256[] memory tokenIds = new uint256[](n);
        address[] memory initialOwners = new address[](n);
        address[] memory nextOwners = new address[](n);
        uint256 totalDistinctAssignments = 0;

        for (uint256 i = 0; i < n; i++) {
            seed = uint256(keccak256(abi.encode(seed, i, "mint")));
            uint256 fromIdx = seed % actors.length;
            address from = actors[fromIdx];
            initialOwners[i] = from;

            vm.roll(block.number + 1);
            vm.prank(OWNER);
            tokenIds[i] = nft.mint(from);
        }

        vm.roll(block.number + 1);
        for (uint256 i = 0; i < n; i++) {
            seed = uint256(keccak256(abi.encode(seed, i, "xfer")));
            uint256 toIdx = seed % actors.length;
            address to = actors[toIdx];
            if (to == initialOwners[i]) {
                toIdx = (toIdx + 1) % actors.length;
                to = actors[toIdx];
            }
            nextOwners[i] = to;

            vm.prank(initialOwners[i]);
            nft.transferFrom(initialOwners[i], to, tokenIds[i]);

            if (to != initialOwners[i]) {
                totalDistinctAssignments += 1;
            }

            assertEq(nft.ownerOf(tokenIds[i]), to);
            assertEq(nft.getTransferCount(tokenIds[i]), 1);
            assertEq(nft.getHistoryLength(tokenIds[i]), 2);
            assertTrue(nft.hasEverOwned(tokenIds[i], initialOwners[i]));
            assertTrue(nft.hasEverOwned(tokenIds[i], to));
        }

        assertEq(nft.totalMinted(), n);
        assertEq(nft.totalSupply(), n);
        assertGe(totalDistinctAssignments, 1);

        for (uint256 i = 0; i < n; i++) {
            assertEq(nft.ownerOf(tokenIds[i]), nextOwners[i]);
        }
    }
}
