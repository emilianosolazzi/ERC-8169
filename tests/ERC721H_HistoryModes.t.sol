// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "forge-std/Test.sol";
import "../src/ERC-721H.sol";
import {ERC721HStorageLib} from "../src/ERC721HStorageLib.sol";

/**
 * @title ERC721H_HistoryModes
 * @notice Tests for FLAG_ONLY and COMPRESSED history modes, including:
 *         - historyMode() view function
 *         - getHistoryHash() correctness (COMPRESSED hash chain)
 *         - hasEverOwned() works in all modes
 *         - Array-based queries return empty / address(0) in non-FULL modes
 *         - Layer 1 (originalCreator, mintBlock) always recorded
 *         - Sybil guards still function in non-FULL modes
 *         - getTransferCount() returns 0 in FLAG_ONLY / COMPRESSED (no arrays)
 *         - getOwnerAtBlock() returns address(0) in FLAG_ONLY / COMPRESSED
 */
contract ERC721H_HistoryModesTest is Test {
    address internal owner  = address(0xAAAA);
    address internal user1  = address(0x1111);
    address internal user2  = address(0x2222);
    address internal user3  = address(0x3333);

    // ─────────────────────────────────────────────────────────────────────────
    //  FLAG_ONLY MODE
    // ─────────────────────────────────────────────────────────────────────────

    function _flagOnlyNFT() internal returns (ERC721H) {
        vm.prank(owner);
        return new ERC721H("FlagOnly NFT", "FLG", ERC721HStorageLib.HistoryMode.FLAG_ONLY);
    }

    function test_FlagOnly_historyModeReturnsCorrect() public {
        ERC721H nft = _flagOnlyNFT();
        assertEq(uint8(nft.historyMode()), uint8(ERC721HStorageLib.HistoryMode.FLAG_ONLY));
    }

    function test_FlagOnly_hasEverOwned_AfterMint() public {
        ERC721H nft = _flagOnlyNFT();
        vm.prank(owner);
        uint256 tokenId = nft.mint(user1);

        assertTrue(nft.hasEverOwned(tokenId, user1));
        assertFalse(nft.hasEverOwned(tokenId, user2));
    }

    function test_FlagOnly_hasEverOwned_AfterTransfer() public {
        ERC721H nft = _flagOnlyNFT();
        vm.prank(owner);
        uint256 tokenId = nft.mint(user1);

        vm.roll(block.number + 1);
        vm.prank(user1);
        nft.transferFrom(user1, user2, tokenId);

        assertTrue(nft.hasEverOwned(tokenId, user1), "original holder preserved");
        assertTrue(nft.hasEverOwned(tokenId, user2), "new holder recorded");
        assertFalse(nft.hasEverOwned(tokenId, user3), "non-holder false");
    }

    function test_FlagOnly_ownershipHistoryArrayEmpty() public {
        ERC721H nft = _flagOnlyNFT();
        vm.prank(owner);
        uint256 tokenId = nft.mint(user1);

        (address[] memory owners, uint256[] memory times) = nft.getOwnershipHistory(tokenId);
        assertEq(owners.length, 0, "no array in FLAG_ONLY");
        assertEq(times.length, 0);
    }

    function test_FlagOnly_everOwnedTokensArrayEmpty() public {
        ERC721H nft = _flagOnlyNFT();
        vm.prank(owner);
        nft.mint(user1);

        uint256[] memory tokens = nft.getEverOwnedTokens(user1);
        assertEq(tokens.length, 0, "everOwnedTokens not populated in FLAG_ONLY");
    }

    function test_FlagOnly_layer1AlwaysRecorded() public {
        ERC721H nft = _flagOnlyNFT();
        vm.prank(owner);
        uint256 tokenId = nft.mint(user1);

        assertEq(nft.originalCreator(tokenId), user1, "Layer 1 creator intact");
        assertEq(nft.mintBlock(tokenId), block.number, "Layer 1 mintBlock intact");
        assertTrue(nft.isOriginalOwner(tokenId, user1));
    }

    function test_FlagOnly_layer1PreservedAfterTransfer() public {
        ERC721H nft = _flagOnlyNFT();
        vm.prank(owner);
        uint256 tokenId = nft.mint(user1);

        vm.roll(block.number + 1);
        vm.prank(user1);
        nft.transferFrom(user1, user2, tokenId);

        assertEq(nft.originalCreator(tokenId), user1, "creator unchanged after transfer");
        assertTrue(nft.isOriginalOwner(tokenId, user1));
    }

    function test_FlagOnly_sybilGuard_sameBlock_reverts() public {
        ERC721H nft = _flagOnlyNFT();
        vm.prank(owner);
        uint256 tokenId = nft.mint(user1);

        // Same block as mint → inter-TX sybil should block
        vm.prank(user1);
        vm.expectRevert(ERC721H.OwnerAlreadyRecordedForBlock.selector);
        nft.transferFrom(user1, user2, tokenId);
    }

    function test_FlagOnly_sybilGuard_nextBlock_passes() public {
        ERC721H nft = _flagOnlyNFT();
        vm.prank(owner);
        uint256 tokenId = nft.mint(user1);

        vm.roll(block.number + 1);
        vm.prank(user1);
        nft.transferFrom(user1, user2, tokenId);
        assertEq(nft.ownerOf(tokenId), user2);
    }

    function test_FlagOnly_getTransferCount_returnsZero() public {
        // FLAG_ONLY stores no arrays — transfer count cannot be computed on-chain.
        // The function returns 0 rather than panicking (underflow guard in CoreLib).
        ERC721H nft = _flagOnlyNFT();
        vm.prank(owner);
        uint256 tokenId = nft.mint(user1);

        // After mint: 0 transfers
        assertEq(nft.getTransferCount(tokenId), 0);

        // After a real transfer: still 0 — arrays not stored
        vm.roll(block.number + 1);
        vm.prank(user1);
        nft.transferFrom(user1, user2, tokenId);
        assertEq(nft.getTransferCount(tokenId), 0, "mode limitation: arrays not stored");
    }

    function test_FlagOnly_getOwnerAtBlock_returnsZeroAddress() public {
        // No ownershipBlocks array in FLAG_ONLY — binary search always returns address(0)
        ERC721H nft = _flagOnlyNFT();
        vm.prank(owner);
        uint256 tokenId = nft.mint(user1);

        assertEq(nft.getOwnerAtBlock(tokenId, block.number), address(0),
            "FLAG_ONLY: no array to search");
    }

    function test_FlagOnly_historyHashAlwaysZero() public {
        // historyHash is never written in FLAG_ONLY mode
        ERC721H nft = _flagOnlyNFT();
        vm.prank(owner);
        uint256 tokenId = nft.mint(user1);

        assertEq(nft.getHistoryHash(tokenId), bytes32(0), "no hash chain in FLAG_ONLY");
    }

    function test_FlagOnly_burnPreservesLayer1() public {
        ERC721H nft = _flagOnlyNFT();
        vm.prank(owner);
        uint256 tokenId = nft.mint(user1);

        vm.prank(user1);
        nft.burn(tokenId);

        assertEq(nft.originalCreator(tokenId), user1, "Layer 1 survives burn");
        assertTrue(nft.hasEverOwned(tokenId, user1), "flag survives burn");
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  COMPRESSED MODE
    // ─────────────────────────────────────────────────────────────────────────

    function _compressedNFT() internal returns (ERC721H) {
        vm.prank(owner);
        return new ERC721H("Compressed NFT", "CMP", ERC721HStorageLib.HistoryMode.COMPRESSED);
    }

    function test_Compressed_historyModeReturnsCorrect() public {
        ERC721H nft = _compressedNFT();
        assertEq(uint8(nft.historyMode()), uint8(ERC721HStorageLib.HistoryMode.COMPRESSED));
    }

    function test_Compressed_hasEverOwned_AfterMint() public {
        ERC721H nft = _compressedNFT();
        vm.prank(owner);
        uint256 tokenId = nft.mint(user1);

        assertTrue(nft.hasEverOwned(tokenId, user1));
        assertFalse(nft.hasEverOwned(tokenId, user2));
    }

    function test_Compressed_hasEverOwned_AfterTransfer() public {
        ERC721H nft = _compressedNFT();
        vm.prank(owner);
        uint256 tokenId = nft.mint(user1);

        vm.roll(block.number + 1);
        vm.prank(user1);
        nft.transferFrom(user1, user2, tokenId);

        assertTrue(nft.hasEverOwned(tokenId, user1));
        assertTrue(nft.hasEverOwned(tokenId, user2));
        assertFalse(nft.hasEverOwned(tokenId, user3));
    }

    function test_Compressed_historyHashNonZeroAfterMint() public {
        ERC721H nft = _compressedNFT();
        vm.prank(owner);
        uint256 tokenId = nft.mint(user1);

        bytes32 h = nft.getHistoryHash(tokenId);
        assertNotEq(h, bytes32(0), "hash chain initialized at mint");
    }

    function test_Compressed_historyHashMatchesKeccak256AtMint() public {
        ERC721H nft = _compressedNFT();
        vm.roll(1000);
        vm.warp(1_700_000_000);

        vm.prank(owner);
        uint256 tokenId = nft.mint(user1);

        // H₀ = keccak256(abi.encodePacked(bytes32(0), to, blockNum, timestamp))
        bytes32 expected = keccak256(
            abi.encodePacked(bytes32(0), user1, uint256(1000), uint256(1_700_000_000))
        );
        assertEq(nft.getHistoryHash(tokenId), expected, "H0 matches spec");
    }

    function test_Compressed_historyHashChangesOnTransfer() public {
        ERC721H nft = _compressedNFT();
        vm.prank(owner);
        uint256 tokenId = nft.mint(user1);

        bytes32 h0 = nft.getHistoryHash(tokenId);

        vm.roll(block.number + 1);
        vm.prank(user1);
        nft.transferFrom(user1, user2, tokenId);

        bytes32 h1 = nft.getHistoryHash(tokenId);
        assertNotEq(h1, h0, "hash chain advances on transfer");
        assertNotEq(h1, bytes32(0));
    }

    function test_Compressed_historyHashChainIsCorrect() public {
        // Verify the hash chain spec for H₀ (mint) and H₁ (one transfer).
        // H₂+ would require a second transfer in the same test function which
        // triggers the intra-TX sybil guard. H₁ is sufficient to validate the chain.
        ERC721H nft = _compressedNFT();
        vm.roll(500);
        vm.warp(1_700_000_000);

        vm.prank(owner);
        uint256 tokenId = nft.mint(user1);

        bytes32 h0 = keccak256(
            abi.encodePacked(bytes32(0), user1, uint256(500), uint256(1_700_000_000))
        );
        assertEq(nft.getHistoryHash(tokenId), h0, "H0 matches chain spec");

        vm.roll(501);
        vm.warp(1_700_000_001);
        vm.prank(user1);
        nft.transferFrom(user1, user2, tokenId);

        // H₁ = keccak256(H₀, newOwner, block, timestamp)
        bytes32 h1 = keccak256(
            abi.encodePacked(h0, user2, uint256(501), uint256(1_700_000_001))
        );
        assertEq(nft.getHistoryHash(tokenId), h1, "H1 follows chain spec");
    }

    function test_Compressed_differentTokensHaveDifferentHashes() public {
        ERC721H nft = _compressedNFT();
        vm.startPrank(owner);
        uint256 t1 = nft.mint(user1);
        uint256 t2 = nft.mint(user2);
        vm.stopPrank();

        assertNotEq(nft.getHistoryHash(t1), nft.getHistoryHash(t2),
            "different recipients -> different H0");
    }

    function test_Compressed_layer1AlwaysRecorded() public {
        ERC721H nft = _compressedNFT();
        vm.prank(owner);
        uint256 tokenId = nft.mint(user1);

        assertEq(nft.originalCreator(tokenId), user1);
        assertEq(nft.mintBlock(tokenId), block.number);
    }

    function test_Compressed_ownershipHistoryArrayEmpty() public {
        ERC721H nft = _compressedNFT();
        vm.prank(owner);
        uint256 tokenId = nft.mint(user1);

        (address[] memory owners,) = nft.getOwnershipHistory(tokenId);
        assertEq(owners.length, 0, "no arrays in COMPRESSED mode");
    }

    function test_Compressed_getOwnerAtBlock_returnsZeroAddress() public {
        ERC721H nft = _compressedNFT();
        vm.prank(owner);
        uint256 tokenId = nft.mint(user1);

        assertEq(nft.getOwnerAtBlock(tokenId, block.number), address(0),
            "COMPRESSED: arrays not stored, binary search returns 0");
    }

    function test_Compressed_sybilGuard_sameBlock_reverts() public {
        ERC721H nft = _compressedNFT();
        vm.prank(owner);
        uint256 tokenId = nft.mint(user1);

        vm.prank(user1);
        vm.expectRevert(ERC721H.OwnerAlreadyRecordedForBlock.selector);
        nft.transferFrom(user1, user2, tokenId);
    }

    function test_Compressed_burnPreservesHashAndLayer1() public {
        ERC721H nft = _compressedNFT();
        vm.prank(owner);
        uint256 tokenId = nft.mint(user1);

        bytes32 hashBeforeBurn = nft.getHistoryHash(tokenId);
        vm.prank(user1);
        nft.burn(tokenId);

        assertEq(nft.getHistoryHash(tokenId), hashBeforeBurn, "hash unchanged by burn");
        assertEq(nft.originalCreator(tokenId), user1, "Layer 1 survives burn");
        assertTrue(nft.hasEverOwned(tokenId, user1), "flag survives burn");
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  FULL MODE — getHistoryHash sanity
    // ─────────────────────────────────────────────────────────────────────────

    function test_Full_historyHashAlwaysZero() public {
        // Hash chain is only computed in COMPRESSED mode.
        // In FULL mode the mapping is never written → always bytes32(0).
        vm.prank(owner);
        ERC721H nft = new ERC721H("Full NFT", "FUL", ERC721HStorageLib.HistoryMode.FULL);

        vm.prank(owner);
        uint256 tokenId = nft.mint(user1);

        assertEq(nft.getHistoryHash(tokenId), bytes32(0),
            "FULL mode does not compute hash chain");
    }

    function test_Full_historyModeReturnsCorrect() public {
        vm.prank(owner);
        ERC721H nft = new ERC721H("Full NFT", "FUL", ERC721HStorageLib.HistoryMode.FULL);
        assertEq(uint8(nft.historyMode()), uint8(ERC721HStorageLib.HistoryMode.FULL));
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  CROSS-MODE: supportsInterface unaffected by mode
    // ─────────────────────────────────────────────────────────────────────────

    function test_AllModes_supportsInterfaceERC721() public {
        vm.startPrank(owner);
        ERC721H full  = new ERC721H("F", "F", ERC721HStorageLib.HistoryMode.FULL);
        ERC721H flag  = new ERC721H("G", "G", ERC721HStorageLib.HistoryMode.FLAG_ONLY);
        ERC721H comp  = new ERC721H("C", "C", ERC721HStorageLib.HistoryMode.COMPRESSED);
        vm.stopPrank();

        bytes4 erc721 = 0x80ac58cd;
        assertTrue(full.supportsInterface(erc721));
        assertTrue(flag.supportsInterface(erc721));
        assertTrue(comp.supportsInterface(erc721));
    }
}
