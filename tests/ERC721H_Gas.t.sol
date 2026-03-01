// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "forge-std/Test.sol";
import "../src/ERC-721H.sol";
import {ERC721HStorageLib} from "../src/ERC721HStorageLib.sol";

contract ERC721H_GasTest is Test {
    ERC721H public nft;
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address charlie = makeAddr("charlie");

    function setUp() public {
        nft = new ERC721H("GasTest", "GAS", ERC721HStorageLib.HistoryMode.FULL);
    }

    /// @notice Baseline mint benchmark.
    function test_Gas_Mint() public {
        uint256 gasBefore = gasleft();
        nft.mint(alice);
        uint256 gasUsed = gasBefore - gasleft();
        console.log("Mint gas used (benchmark):", gasUsed);
    }

    /// @notice Cold transfer benchmark (fresh token state path).
    function test_Gas_Transfer_Cold() public {
        nft.mint(alice);
        vm.roll(block.number + 1);

        uint256 gasBefore = gasleft();
        vm.prank(alice);
        nft.transferFrom(alice, bob, 1);
        uint256 gasUsed = gasBefore - gasleft();
        console.log("Transfer gas used (cold path):", gasUsed);
    }

    /// @notice Warm transfer surrogate benchmark.
    /// @dev Warms common read slots in the same call context before transfer.
    function test_Gas_Transfer_WarmSurrogate() public {
        nft.mint(alice);
        vm.roll(block.number + 1);

        nft.ownerOf(1);
        nft.balanceOf(alice);
        nft.getHistoryLength(1);

        uint256 gasBefore = gasleft();
        vm.prank(alice);
        nft.transferFrom(alice, bob, 1);
        uint256 gasUsed = gasBefore - gasleft();
        console.log("Transfer gas used (warm surrogate path):", gasUsed);
    }

    /// @notice Re-transfer same owner path benchmark (dedup path).
    /// @dev Intra-TX Sybil guard prevents multiple same-token transfers in one test call,
    ///      so this benchmark uses a proxy signal: recipient already owns another token.
    ///      This exercises a warm owner-accounting path used by repeat ownership workflows.
    function test_Gas_ReTransferSameOwner_Path() public {
        nft.mint(alice);    // tokenId 1
        nft.mint(bob);      // tokenId 2, bob already appears as owner in collection state

        vm.roll(block.number + 1);
        vm.prank(alice);
        nft.transferFrom(alice, bob, 1);

        vm.roll(block.number + 1);
        uint256 gasBefore = gasleft();
        vm.prank(bob);
        nft.transferFrom(bob, charlie, 2);
        uint256 gasUsed = gasBefore - gasleft();
        console.log("Re-transfer same-owner path gas used:", gasUsed);
    }

    /// @notice Cooldown-hit benchmark (expected revert path cost surface).
    function test_Gas_CooldownHit() public {
        nft.mint(alice);
        nft.setTransferCooldown(10);

        vm.roll(block.number + 1);
        uint256 gasBefore = gasleft();
        vm.prank(alice);
        vm.expectRevert(ERC721H.TransferCooldownActive.selector);
        nft.transferFrom(alice, bob, 1);
        uint256 gasUsed = gasBefore - gasleft();
        console.log("Cooldown-hit revert gas used:", gasUsed);
    }

    function test_Gas_Transfer_Cold_vs_WarmSurrogate_Delta() public {
        nft.mint(alice);
        nft.mint(alice);

        vm.roll(block.number + 1);
        uint256 coldBefore = gasleft();
        vm.prank(alice);
        nft.transferFrom(alice, bob, 1);
        uint256 coldUsed = coldBefore - gasleft();

        vm.roll(block.number + 1);
        nft.ownerOf(2);
        nft.balanceOf(alice);
        nft.getHistoryLength(2);

        uint256 warmBefore = gasleft();
        vm.prank(alice);
        nft.transferFrom(alice, bob, 2);
        uint256 warmUsed = warmBefore - gasleft();

        console.log("Cold transfer gas:", coldUsed);
        console.log("Warm surrogate transfer gas:", warmUsed);
    }

    function test_Gas_SafeTransferFrom() public {
        nft.mint(alice);
        vm.roll(block.number + 1);

        uint256 gasBefore = gasleft();
        vm.prank(alice);
        nft.safeTransferFrom(alice, bob, 1);
        uint256 gasUsed = gasBefore - gasleft();
        console.log("SafeTransferFrom gas used:", gasUsed);
    }

    function test_Gas_Burn() public {
        nft.mint(alice);
        
        uint256 gasBefore = gasleft();
        vm.prank(alice);
        nft.burn(1);
        uint256 gasUsed = gasBefore - gasleft();
        console.log("Burn gas used:", gasUsed);
    }

    function test_Gas_Approve() public {
        nft.mint(alice);
        
        uint256 gasBefore = gasleft();
        vm.prank(alice);
        nft.approve(bob, 1);
        uint256 gasUsed = gasBefore - gasleft();
        console.log("Approve gas used:", gasUsed);
    }

    function test_Gas_SetApprovalForAll() public {
        uint256 gasBefore = gasleft();
        vm.prank(alice);
        nft.setApprovalForAll(bob, true);
        uint256 gasUsed = gasBefore - gasleft();
        console.log("SetApprovalForAll gas used:", gasUsed);
    }
}
