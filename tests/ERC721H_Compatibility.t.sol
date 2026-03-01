// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "forge-std/Test.sol";
import "../src/ERC-721H.sol";
import {ERC721HStorageLib} from "../src/ERC721HStorageLib.sol";

interface IERC721ReceiverLike {
    function onERC721Received(address, address, uint256, bytes calldata) external returns (bytes4);
}

contract GoodReceiver is IERC721ReceiverLike {
    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }
}

contract BadReceiver is IERC721ReceiverLike {
    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return 0xdeadbeef;
    }
}

contract ERC721H_CompatibilityTest is Test {
    ERC721H internal nft;

    address internal owner = makeAddr("owner");
    address internal seller = makeAddr("seller");
    address internal marketOperator = makeAddr("marketOperator");
    address internal buyer = makeAddr("buyer");

    function setUp() public {
        vm.prank(owner);
        nft = new ERC721H("Compat", "CMP", ERC721HStorageLib.HistoryMode.FULL);

        vm.prank(owner);
        nft.mint(seller);
    }

    function test_Compatibility_OpenSeaStyle_SetApprovalForAll_TransferByOperator() public {
        vm.prank(seller);
        nft.setApprovalForAll(marketOperator, true);

        vm.roll(block.number + 10);
        vm.prank(marketOperator);
        nft.transferFrom(seller, buyer, 1);

        assertEq(nft.ownerOf(1), buyer);
        assertEq(nft.getTransferCount(1), 1);
    }

    function test_Compatibility_safeTransferFrom_toERC721Receiver() public {
        GoodReceiver receiver = new GoodReceiver();

        vm.roll(block.number + 1);
        vm.prank(seller);
        nft.safeTransferFrom(seller, address(receiver), 1);

        assertEq(nft.ownerOf(1), address(receiver));
    }

    function test_Compatibility_safeTransferFrom_badReceiver_reverts() public {
        BadReceiver receiver = new BadReceiver();

        vm.roll(block.number + 1);
        vm.prank(seller);
        vm.expectRevert(ERC721H.InvalidRecipient.selector);
        nft.safeTransferFrom(seller, address(receiver), 1);
    }

    function test_Compatibility_CooldownBlocksMarketplaceTransfer() public {
        vm.prank(owner);
        nft.setTransferCooldown(10);

        vm.prank(seller);
        nft.setApprovalForAll(marketOperator, true);

        vm.roll(block.number + 1);
        vm.prank(marketOperator);
        vm.expectRevert(ERC721H.TransferCooldownActive.selector);
        nft.transferFrom(seller, buyer, 1);
    }

    function test_Compatibility_CooldownAllowsMarketplaceAfterWait() public {
        vm.prank(owner);
        nft.setTransferCooldown(10);

        vm.prank(seller);
        nft.setApprovalForAll(marketOperator, true);

        vm.roll(block.number + 10);
        vm.prank(marketOperator);
        nft.transferFrom(seller, buyer, 1);

        assertEq(nft.ownerOf(1), buyer);
    }
}
