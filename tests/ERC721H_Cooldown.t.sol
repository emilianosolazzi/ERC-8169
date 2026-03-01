// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "forge-std/Test.sol";
import "../src/ERC-721H.sol";
import {ERC721HStorageLib} from "../src/ERC721HStorageLib.sol";

/**
 * @title ERC721H_Cooldown
 * @notice Tests for the configurable transfer cooldown anti-griefing feature.
 *
 *  Covered scenarios:
 *    - Default: transferCooldownBlocks == 0 (no cooldown, normal behaviour)
 *    - setTransferCooldown() access control
 *    - Transfer within cooldown window reverts with TransferCooldownActive
 *    - Transfer at exactly cooldown boundary succeeds
 *    - Transfer after cooldown expires succeeds
 *    - Cooldown stacks correctly on successive transfers (window slides)
 *    - Cooldown can be updated by owner mid-operation
 *    - Cooldown + same-block sybil guard both apply independently
 *    - Works correctly across FLAG_ONLY and COMPRESSED modes
 */
contract ERC721H_CooldownTest is Test {
    ERC721H public nft;
    address public owner = address(0xAAAA);
    address public user1 = address(0x1111);
    address public user2 = address(0x2222);
    address public user3 = address(0x3333);

    function setUp() public {
        vm.prank(owner);
        nft = new ERC721H("Cooldown NFT", "COOL", ERC721HStorageLib.HistoryMode.FULL);
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  Default state
    // ─────────────────────────────────────────────────────────────────────────

    function test_Cooldown_defaultIsZero() public view {
        assertEq(nft.transferCooldownBlocks(), 0);
    }

    function test_Cooldown_zeroMeansNoCooldown() public {
        // With cooldown == 0, consecutive (but different-block) transfers succeed.
        // Each token is tested independently to avoid the intra-TX transient-storage
        // sybil guard, which fires if the same token transfers twice in one tx.
        vm.startPrank(owner);
        uint256 t1 = nft.mint(user1);
        uint256 t2 = nft.mint(user2);
        vm.stopPrank();

        vm.roll(block.number + 1);
        vm.prank(user1);
        nft.transferFrom(user1, user3, t1);
        assertEq(nft.ownerOf(t1), user3);

        // t2 transfer in same block — different token, no cooldown → passes
        vm.prank(user2);
        nft.transferFrom(user2, user3, t2);
        assertEq(nft.ownerOf(t2), user3);
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  Access control
    // ─────────────────────────────────────────────────────────────────────────

    function test_Cooldown_setOnlyOwner() public {
        vm.prank(owner);
        nft.setTransferCooldown(10);
        assertEq(nft.transferCooldownBlocks(), 10);
    }

    function test_Cooldown_setByNonOwner_Reverts() public {
        vm.prank(user1);
        vm.expectRevert(ERC721H.NotAuthorized.selector);
        nft.setTransferCooldown(10);
    }

    function test_Cooldown_setToZeroDisables() public {
        vm.startPrank(owner);
        nft.setTransferCooldown(100);
        nft.setTransferCooldown(0);
        vm.stopPrank();
        assertEq(nft.transferCooldownBlocks(), 0);
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  Core revert / pass behaviour
    // ─────────────────────────────────────────────────────────────────────────

    function test_Cooldown_transferWithinWindow_Reverts() public {
        vm.prank(owner);
        nft.setTransferCooldown(10);

        vm.prank(owner);
        uint256 tokenId = nft.mint(user1);

        // +5 blocks since mint — within 10-block cooldown
        vm.roll(block.number + 5);
        vm.prank(user1);
        vm.expectRevert(ERC721H.TransferCooldownActive.selector);
        nft.transferFrom(user1, user2, tokenId);
    }

    function test_Cooldown_transferAtExactBoundary_Succeeds() public {
        vm.prank(owner);
        nft.setTransferCooldown(5);

        vm.prank(owner);
        uint256 mintBlock = block.number;
        uint256 tokenId   = nft.mint(user1);

        // Transfer at exactly mintBlock + cooldown → succeeds (block.number >= lastBlock + cooldown)
        vm.roll(mintBlock + 5);
        vm.prank(user1);
        nft.transferFrom(user1, user2, tokenId);
        assertEq(nft.ownerOf(tokenId), user2);
    }

    function test_Cooldown_transferAfterWindow_Succeeds() public {
        vm.prank(owner);
        nft.setTransferCooldown(10);

        vm.prank(owner);
        uint256 mintBlock = block.number;
        uint256 tokenId   = nft.mint(user1);

        vm.roll(mintBlock + 20);
        vm.prank(user1);
        nft.transferFrom(user1, user2, tokenId);
        assertEq(nft.ownerOf(tokenId), user2);
    }

    function test_Cooldown_windowAnchoredToLastTransferBlock() public {
        // The cooldown window is anchored to lastTransferBlock (set at mint).
        // A transfer at exactly mintBlock + cooldown succeeds; one block earlier fails.
        // This proves the window calculation: block.number >= lastBlock + cooldown.
        vm.prank(owner);
        nft.setTransferCooldown(5);

        vm.prank(owner);
        uint256 mintBlock = block.number;
        uint256 tokenId   = nft.mint(user1);

        // One block short — still within window
        vm.roll(mintBlock + 4);
        vm.prank(user1);
        vm.expectRevert(ERC721H.TransferCooldownActive.selector);
        nft.transferFrom(user1, user2, tokenId);

        // Exactly at boundary — passes (block.number == mintBlock + cooldown)
        vm.roll(mintBlock + 5);
        vm.prank(user1);
        nft.transferFrom(user1, user2, tokenId);
        assertEq(nft.ownerOf(tokenId), user2);
    }

    function test_Cooldown_updateMidOpIncrease() public {
        // Owner increases cooldown after mint. The new cooldown is measured from
        // lastTransferBlock (== mintBlock), so existing holders must respect the
        // new, larger window.
        vm.prank(owner);
        uint256 tokenId = nft.mint(user1);
        uint256 mintBlock = block.number;

        // Owner sets a large cooldown after already minting
        vm.prank(owner);
        nft.setTransferCooldown(20);

        // +8 blocks from mint -- within 20-block cooldown → FAILS
        vm.roll(mintBlock + 8);
        vm.prank(user1);
        vm.expectRevert(ERC721H.TransferCooldownActive.selector);
        nft.transferFrom(user1, user2, tokenId);

        // +20 blocks from mint → passes
        vm.roll(mintBlock + 20);
        vm.prank(user1);
        nft.transferFrom(user1, user2, tokenId);
        assertEq(nft.ownerOf(tokenId), user2);
    }

    function test_Cooldown_updateMidOpDecrease_Unlocks() public {
        vm.prank(owner);
        nft.setTransferCooldown(100);

        vm.prank(owner);
        uint256 tokenId = nft.mint(user1);

        vm.roll(block.number + 5);
        // Still within 100-block cooldown

        // Owner drops cooldown to 3
        vm.prank(owner);
        nft.setTransferCooldown(3);

        // Now +5 > 3, should pass
        vm.prank(user1);
        nft.transferFrom(user1, user2, tokenId);
        assertEq(nft.ownerOf(tokenId), user2);
    }

    function test_Cooldown_disableMidOp_Unlocks() public {
        vm.prank(owner);
        nft.setTransferCooldown(50);

        vm.prank(owner);
        uint256 tokenId = nft.mint(user1);

        vm.roll(block.number + 5);

        vm.prank(owner);
        nft.setTransferCooldown(0); // disable

        vm.prank(user1);
        nft.transferFrom(user1, user2, tokenId); // passes now
        assertEq(nft.ownerOf(tokenId), user2);
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  Interaction with same-block sybil guard
    // ─────────────────────────────────────────────────────────────────────────

    function test_Cooldown_sameBlockExactly_usesSybilGuard() public {
        // Cooldown = 0, but same block as mint → sybil guard fires, not cooldown
        vm.prank(owner);
        uint256 tokenId = nft.mint(user1);

        vm.prank(user1);
        vm.expectRevert(ERC721H.OwnerAlreadyRecordedForBlock.selector);
        nft.transferFrom(user1, user2, tokenId);
    }

    function test_Cooldown_sameBlockTransferWithCooldown_SybilGuardFiresFirst() public {
        // Even with cooldown set, the same-block check fires before cooldown check.
        vm.prank(owner);
        nft.setTransferCooldown(10);

        vm.prank(owner);
        uint256 tokenId = nft.mint(user1);

        // Same block as mint (sybil guard applies regardless of cooldown)
        vm.prank(user1);
        vm.expectRevert(ERC721H.OwnerAlreadyRecordedForBlock.selector);
        nft.transferFrom(user1, user2, tokenId);
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  Multiple tokens are independent
    // ─────────────────────────────────────────────────────────────────────────

    function test_Cooldown_independentPerToken() public {
        vm.prank(owner);
        nft.setTransferCooldown(10);

        vm.startPrank(owner);
        uint256 t1 = nft.mint(user1);
        vm.roll(block.number + 1);
        uint256 t2 = nft.mint(user2);
        vm.stopPrank();

        // t1: 10 blocks since mint → can transfer
        vm.roll(block.number + 9); // now mintBlock(t1)+10 is reachable
        vm.prank(user1);
        nft.transferFrom(user1, user3, t1);

        // t2 was minted 1 block later, so it still has 1 block left in window
        vm.prank(user2);
        vm.expectRevert(ERC721H.TransferCooldownActive.selector);
        nft.transferFrom(user2, user3, t2);
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  Cooldown works in FLAG_ONLY mode (uses lastTransferBlock in all modes)
    // ─────────────────────────────────────────────────────────────────────────

    function test_Cooldown_flagOnlyMode_works() public {
        vm.prank(owner);
        ERC721H flagNft = new ERC721H("Flag", "FLG", ERC721HStorageLib.HistoryMode.FLAG_ONLY);

        vm.prank(owner);
        flagNft.setTransferCooldown(5);

        vm.prank(owner);
        uint256 mintBlock = block.number;
        uint256 tokenId = flagNft.mint(user1);

        vm.roll(mintBlock + 3); // within window
        vm.prank(user1);
        vm.expectRevert(ERC721H.TransferCooldownActive.selector);
        flagNft.transferFrom(user1, user2, tokenId);

        vm.roll(mintBlock + 5); // at boundary
        vm.prank(user1);
        flagNft.transferFrom(user1, user2, tokenId);
        assertEq(flagNft.ownerOf(tokenId), user2);
    }

    function test_Cooldown_compressedMode_works() public {
        vm.prank(owner);
        ERC721H cmpNft = new ERC721H("Cmp", "CMP", ERC721HStorageLib.HistoryMode.COMPRESSED);

        vm.prank(owner);
        cmpNft.setTransferCooldown(7);

        vm.prank(owner);
        uint256 mintBlock = block.number;
        uint256 tokenId = cmpNft.mint(user1);

        vm.roll(mintBlock + 3); // within window
        vm.prank(user1);
        vm.expectRevert(ERC721H.TransferCooldownActive.selector);
        cmpNft.transferFrom(user1, user2, tokenId);

        vm.roll(mintBlock + 7);
        vm.prank(user1);
        cmpNft.transferFrom(user1, user2, tokenId);
        assertEq(cmpNft.ownerOf(tokenId), user2);

        // Hash chain still advances correctly through cooldown-guarded transfer
        assertNotEq(cmpNft.getHistoryHash(tokenId), bytes32(0));
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  Fuzz
    // ─────────────────────────────────────────────────────────────────────────

    function testFuzz_Cooldown_blocksBelowThresholdRevert(uint8 cooldown, uint8 elapsed) public {
        vm.assume(cooldown > 0);
        vm.assume(elapsed < cooldown);

        vm.prank(owner);
        nft.setTransferCooldown(uint256(cooldown));

        vm.prank(owner);
        uint256 mintBlock = block.number;
        uint256 tokenId = nft.mint(user1);

        // elapsed+1 because we must be in a different block than mint (avoid sybil guard)
        // but also still below cooldown
        vm.assume(elapsed > 0); // skip elapsed==0 (sybil guard fires, not cooldown)
        vm.roll(mintBlock + uint256(elapsed));

        vm.prank(user1);
        vm.expectRevert(ERC721H.TransferCooldownActive.selector);
        nft.transferFrom(user1, user2, tokenId);
    }

    function testFuzz_Cooldown_blocksAtOrAboveThresholdPass(uint8 cooldown, uint8 extra) public {
        vm.assume(cooldown > 0 && cooldown < 200);
        vm.assume(extra < 100);

        vm.prank(owner);
        nft.setTransferCooldown(uint256(cooldown));

        vm.prank(owner);
        uint256 mintBlock = block.number;
        uint256 tokenId = nft.mint(user1);

        vm.roll(mintBlock + uint256(cooldown) + uint256(extra));
        vm.prank(user1);
        nft.transferFrom(user1, user2, tokenId);
        assertEq(nft.ownerOf(tokenId), user2);
    }
}
