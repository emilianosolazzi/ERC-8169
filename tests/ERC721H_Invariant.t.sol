// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {ERC721H} from "../src/ERC-721H.sol";
import {ERC721HStorageLib} from "../src/ERC721HStorageLib.sol";

contract ERC721HHandler is Test {
    ERC721H public immutable nft;

    uint256 public mints;
    uint256 public burns;

    address[] internal _actors;
    uint256[] internal _allTokenIds;
    uint256[] internal _activeTokenIds;

    mapping(uint256 => uint256) internal _activeIndexPlusOne;
    mapping(uint256 => address) public trackedOwner;
    mapping(uint256 => address) public trackedCreator;

    constructor() {
        nft = new ERC721H("Invariant NFT", "INVAR", ERC721HStorageLib.HistoryMode.FULL);
        _actors.push(address(0xA11CE));
        _actors.push(address(0xB0B));
        _actors.push(address(0xC0DE));
        _actors.push(address(0xD00D));
        _actors.push(address(0xE11A));
        _actors.push(address(0xF00D));
        _actors.push(address(0xABCD));
        _actors.push(address(0x1234));
    }

    function mintRandom(uint256 actorSeed) external {
        address to = _actor(actorSeed);
        uint256 tokenId = nft.mint(to);

        _allTokenIds.push(tokenId);
        _activeTokenIds.push(tokenId);
        _activeIndexPlusOne[tokenId] = _activeTokenIds.length;

        trackedOwner[tokenId] = to;
        trackedCreator[tokenId] = to;
        mints += 1;
    }

    function transferRandom(uint256 tokenSeed, uint256 actorSeed) external {
        if (_activeTokenIds.length == 0) return;

        uint256 tokenId = _activeTokenIds[tokenSeed % _activeTokenIds.length];
        address from = trackedOwner[tokenId];
        address to = _actor(actorSeed);
        if (to == from) return;

        vm.roll(block.number + 1);
        vm.prank(from);
        nft.transferFrom(from, to, tokenId);

        trackedOwner[tokenId] = to;
    }

    function approveAndTransferRandom(uint256 tokenSeed, uint256 opSeed, uint256 recipientSeed) external {
        if (_activeTokenIds.length == 0) return;

        uint256 tokenId = _activeTokenIds[tokenSeed % _activeTokenIds.length];
        address from = trackedOwner[tokenId];
        address operator = _actor(opSeed);
        address recipient = _actor(recipientSeed + 17);

        if (operator == from || recipient == from || recipient == operator) return;

        vm.roll(block.number + 1);
        vm.prank(from);
        nft.approve(operator, tokenId);

        vm.prank(operator);
        nft.transferFrom(from, recipient, tokenId);

        trackedOwner[tokenId] = recipient;
    }

    function burnRandom(uint256 tokenSeed) external {
        if (_activeTokenIds.length == 0) return;

        uint256 tokenId = _activeTokenIds[tokenSeed % _activeTokenIds.length];
        address tokenOwner = trackedOwner[tokenId];

        vm.roll(block.number + 1);
        vm.prank(tokenOwner);
        nft.burn(tokenId);

        trackedOwner[tokenId] = address(0);
        burns += 1;
        _removeActive(tokenId);
    }

    function allTokenIdsLength() external view returns (uint256) {
        return _allTokenIds.length;
    }

    function allTokenIdAt(uint256 index) external view returns (uint256) {
        return _allTokenIds[index];
    }

    function activeTokenIdsLength() external view returns (uint256) {
        return _activeTokenIds.length;
    }

    function _actor(uint256 seed) internal view returns (address) {
        return _actors[seed % _actors.length];
    }

    function _removeActive(uint256 tokenId) internal {
        uint256 idxPlusOne = _activeIndexPlusOne[tokenId];
        if (idxPlusOne == 0) return;

        uint256 idx = idxPlusOne - 1;
        uint256 lastIdx = _activeTokenIds.length - 1;

        if (idx != lastIdx) {
            uint256 lastTokenId = _activeTokenIds[lastIdx];
            _activeTokenIds[idx] = lastTokenId;
            _activeIndexPlusOne[lastTokenId] = idx + 1;
        }

        _activeTokenIds.pop();
        delete _activeIndexPlusOne[tokenId];
    }
}

contract ERC721H_Invariant is StdInvariant, Test {
    ERC721HHandler internal handler;
    ERC721H internal nft;

    function setUp() public {
        handler = new ERC721HHandler();
        nft = handler.nft();

        bytes4[] memory selectors = new bytes4[](4);
        selectors[0] = ERC721HHandler.mintRandom.selector;
        selectors[1] = ERC721HHandler.transferRandom.selector;
        selectors[2] = ERC721HHandler.approveAndTransferRandom.selector;
        selectors[3] = ERC721HHandler.burnRandom.selector;

        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    function invariant_supplyAccounting() public view {
        assertEq(nft.totalMinted(), handler.mints());
        assertEq(nft.totalSupply() + handler.burns(), handler.mints());
        assertLe(nft.totalSupply(), nft.totalMinted());
        assertEq(nft.totalSupply(), handler.activeTokenIdsLength());
    }

    function invariant_layer1AndLayer2Consistency() public {
        uint256 count = handler.allTokenIdsLength();

        for (uint256 i = 0; i < count; i++) {
            uint256 tokenId = handler.allTokenIdAt(i);
            address creator = handler.trackedCreator(tokenId);
            address currentTrackedOwner = handler.trackedOwner(tokenId);

            assertEq(nft.originalCreator(tokenId), creator);
            assertTrue(nft.mintBlock(tokenId) > 0);

            uint256 historyLength = nft.getHistoryLength(tokenId);
            assertEq(historyLength, nft.getTransferCount(tokenId) + 1);

            if (currentTrackedOwner == address(0)) {
                vm.expectRevert(ERC721H.TokenDoesNotExist.selector);
                nft.ownerOf(tokenId);
            } else {
                assertEq(nft.ownerOf(tokenId), currentTrackedOwner);
                assertTrue(nft.hasEverOwned(tokenId, currentTrackedOwner));
            }
        }
    }
}
