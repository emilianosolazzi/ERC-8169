// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "forge-std/Test.sol";
import "../src/ERC-721HFactory.sol";
import {ERC721HStorageLib} from "../src/ERC721HStorageLib.sol";
import {ERC721H} from "../src/ERC-721H.sol";

/**
 * @title ERC721H_Factory
 * @notice Full test suite for ERC721HFactory (CREATE2 deployer) and
 *         ERC721HCollection (production wrapper).
 *
 *  Covered:
 *    Factory:
 *      - deployCollection: ownership transferred to deployer, registry updated
 *      - predictAddress: matches deployed address
 *      - Deployer-mixed salt: two deployers with same salt get different addresses
 *      - Registry: isCollection, getDeployerCollections, totalDeployed
 *      - History mode pass-through to deployed collection
 *
 *    ERC721HCollection:
 *      - Single mint (supply-capped override)
 *      - batchMint: owner-only, provenance recorded per token
 *      - batchMintTo: airdrop, one token per recipient
 *      - publicMint: payment required, per-wallet limit, supply cap
 *      - Admin: setBaseURI, setMintPrice, setMaxPerWallet, togglePublicMint, withdraw
 *      - Batch views: batchTokenSummary, batchOwnerAtBlock, batchHasEverOwned,
 *                     batchOriginalCreator, batchTransferCount
 *      - maxSupply=0 means unlimited
 *      - tokenURI: baseURI + tokenId
 */
contract ERC721H_FactoryTest is Test {
    ERC721HFactory public factory;

    address internal deployer = address(0xDEAD);
    address internal user1    = address(0x1111);
    address internal user2    = address(0x2222);
    address internal user3    = address(0x3333);

    bytes32 constant SALT = keccak256("test-salt-v1");

    function setUp() public {
        factory = new ERC721HFactory();
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  Helper
    // ─────────────────────────────────────────────────────────────────────────

    function _deploy(
        string memory name,
        string memory symbol,
        uint256 maxSupply,
        string memory baseURI,
        bytes32 salt,
        ERC721HStorageLib.HistoryMode mode
    ) internal returns (ERC721HCollection) {
        vm.prank(deployer);
        address addr = factory.deployCollection(name, symbol, maxSupply, baseURI, salt, mode);
        return ERC721HCollection(addr);
    }

    function _defaultCollection() internal returns (ERC721HCollection) {
        return _deploy("Test Collection", "TEST", 1000, "https://api.example.com/",
            SALT, ERC721HStorageLib.HistoryMode.FULL);
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  Factory: deployment
    // ─────────────────────────────────────────────────────────────────────────

    function test_Factory_deployCollection_returnsNonZeroAddress() public {
        ERC721HCollection col = _defaultCollection();
        assertNotEq(address(col), address(0));
    }

    function test_Factory_deployCollection_ownerIsDeployer() public {
        ERC721HCollection col = _defaultCollection();
        assertEq(col.owner(), deployer, "ownership transferred to deployer, not factory");
    }

    function test_Factory_deployCollection_factoryIsNotOwner() public {
        ERC721HCollection col = _defaultCollection();
        assertNotEq(col.owner(), address(factory));
    }

    function test_Factory_deployCollection_registryUpdated() public {
        ERC721HCollection col = _defaultCollection();
        assertTrue(factory.isCollection(address(col)));
    }

    function test_Factory_deployCollection_totalDeployedIncrements() public {
        assertEq(factory.totalDeployed(), 0);
        _defaultCollection();
        assertEq(factory.totalDeployed(), 1);
        _deploy("B", "B", 0, "", keccak256("salt2"), ERC721HStorageLib.HistoryMode.FLAG_ONLY);
        assertEq(factory.totalDeployed(), 2);
    }

    function test_Factory_deployCollection_emitsEvent() public {
        vm.prank(deployer);
        vm.expectEmit(false, true, false, false); // index on deployer
        emit ERC721HFactory.CollectionDeployed(
            address(0), deployer, "Test Collection", "TEST", 1000, SALT,
            ERC721HStorageLib.HistoryMode.FULL
        );
        factory.deployCollection("Test Collection", "TEST", 1000, "https://api.example.com/",
            SALT, ERC721HStorageLib.HistoryMode.FULL);
    }

    function test_Factory_getDeployerCollections() public {
        ERC721HCollection c1 = _deploy("A", "A", 10, "", SALT, ERC721HStorageLib.HistoryMode.FULL);
        ERC721HCollection c2 = _deploy("B", "B", 10, "", keccak256("s2"), ERC721HStorageLib.HistoryMode.FULL);

        address[] memory cols = factory.getDeployerCollections(deployer);
        assertEq(cols.length, 2);
        assertEq(cols[0], address(c1));
        assertEq(cols[1], address(c2));
    }

    function test_Factory_getCollections_pagination() public {
        _deploy("A", "A", 0, "", keccak256("s1"), ERC721HStorageLib.HistoryMode.FULL);
        _deploy("B", "B", 0, "", keccak256("s2"), ERC721HStorageLib.HistoryMode.FULL);
        _deploy("C", "C", 0, "", keccak256("s3"), ERC721HStorageLib.HistoryMode.FULL);

        address[] memory page = factory.getCollections(1, 2);
        assertEq(page.length, 2, "pagination works");
    }

    function test_Factory_unknownAddress_notCollection() public view {
        assertFalse(factory.isCollection(address(0xBEEF)));
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  Factory: predictAddress
    // ─────────────────────────────────────────────────────────────────────────

    function test_Factory_predictAddress_matchesDeployed() public {
        address predicted = factory.predictAddress(
            "Test Collection", "TEST", 1000, "https://api.example.com/",
            SALT, deployer, ERC721HStorageLib.HistoryMode.FULL
        );

        ERC721HCollection col = _defaultCollection();
        assertEq(predicted, address(col), "predicted == deployed");
    }

    function test_Factory_predictAddress_differentDeployer_differentAddress() public {
        address addr2 = address(0xBEEF);
        address p1 = factory.predictAddress("N", "N", 0, "", SALT, deployer,
            ERC721HStorageLib.HistoryMode.FULL);
        address p2 = factory.predictAddress("N", "N", 0, "", SALT, addr2,
            ERC721HStorageLib.HistoryMode.FULL);
        assertNotEq(p1, p2, "deployer mixed into salt -- addresses differ");
    }

    function test_Factory_predictAddress_differentSalt_differentAddress() public {
        address p1 = factory.predictAddress("N", "N", 0, "", keccak256("a"), deployer,
            ERC721HStorageLib.HistoryMode.FULL);
        address p2 = factory.predictAddress("N", "N", 0, "", keccak256("b"), deployer,
            ERC721HStorageLib.HistoryMode.FULL);
        assertNotEq(p1, p2);
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  Factory: history mode pass-through
    // ─────────────────────────────────────────────────────────────────────────

    function test_Factory_historyMode_full() public {
        ERC721HCollection col = _deploy("F", "F", 0, "", SALT, ERC721HStorageLib.HistoryMode.FULL);
        assertEq(uint8(col.historyMode()), uint8(ERC721HStorageLib.HistoryMode.FULL));
    }

    function test_Factory_historyMode_flagOnly() public {
        ERC721HCollection col = _deploy("G", "G", 0, "", SALT, ERC721HStorageLib.HistoryMode.FLAG_ONLY);
        assertEq(uint8(col.historyMode()), uint8(ERC721HStorageLib.HistoryMode.FLAG_ONLY));
    }

    function test_Factory_historyMode_compressed() public {
        ERC721HCollection col = _deploy("C", "C", 0, "", SALT, ERC721HStorageLib.HistoryMode.COMPRESSED);
        assertEq(uint8(col.historyMode()), uint8(ERC721HStorageLib.HistoryMode.COMPRESSED));
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  ERC721HCollection: single mint (supply-capped)
    // ─────────────────────────────────────────────────────────────────────────

    function test_Collection_singleMint() public {
        ERC721HCollection col = _defaultCollection();
        vm.prank(deployer);
        uint256 tokenId = col.mint(user1);

        assertEq(col.ownerOf(tokenId), user1);
        assertEq(col.originalCreator(tokenId), user1);
        assertEq(col.totalMinted(), 1);
        assertEq(col.totalSupply(), 1);
    }

    function test_Collection_mint_onlyOwner_Reverts() public {
        ERC721HCollection col = _defaultCollection();
        vm.prank(user1);
        vm.expectRevert(ERC721H.NotAuthorized.selector);
        col.mint(user1);
    }

    function test_Collection_maxSupply_Reverts() public {
        ERC721HCollection col = _deploy("S", "S", 2, "", SALT, ERC721HStorageLib.HistoryMode.FULL);
        vm.startPrank(deployer);
        col.mint(user1);
        col.mint(user2);
        vm.expectRevert(ERC721HCollection.MaxSupplyExceeded.selector);
        col.mint(user3);
        vm.stopPrank();
    }

    function test_Collection_maxSupplyZero_isUnlimited() public {
        ERC721HCollection col = _deploy("U", "U", 0, "", SALT, ERC721HStorageLib.HistoryMode.FULL);
        assertEq(col.MAX_SUPPLY(), type(uint256).max);
        vm.startPrank(deployer);
        for (uint256 i = 0; i < 10; i++) col.mint(user1);
        vm.stopPrank();
        assertEq(col.totalMinted(), 10);
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  ERC721HCollection: batchMint
    // ─────────────────────────────────────────────────────────────────────────

    function test_Collection_batchMint_basicBehaviour() public {
        ERC721HCollection col = _defaultCollection();
        vm.prank(deployer);
        uint256[] memory ids = col.batchMint(user1, 5);

        assertEq(ids.length, 5);
        assertEq(col.totalMinted(), 5);
        assertEq(col.totalSupply(), 5);
        for (uint256 i = 0; i < 5; i++) {
            assertEq(col.ownerOf(ids[i]), user1);
            assertEq(col.originalCreator(ids[i]), user1);
        }
    }

    function test_Collection_batchMint_provenancePerToken() public {
        ERC721HCollection col = _defaultCollection();
        vm.prank(deployer);
        uint256[] memory ids = col.batchMint(user1, 3);

        // Each token has independent Layer 1 origin
        for (uint256 i = 0; i < 3; i++) {
            assertEq(col.originalCreator(ids[i]), user1);
        }
        // History is independent per token
        (address[] memory h0,) = col.getOwnershipHistory(ids[0]);
        (address[] memory h1,) = col.getOwnershipHistory(ids[1]);
        assertEq(h0.length, 1);
        assertEq(h1.length, 1);
    }

    function test_Collection_batchMint_onlyOwner_Reverts() public {
        ERC721HCollection col = _defaultCollection();
        vm.prank(user1);
        vm.expectRevert(ERC721H.NotAuthorized.selector);
        col.batchMint(user1, 3);
    }

    function test_Collection_batchMint_zeroQuantity_Reverts() public {
        ERC721HCollection col = _defaultCollection();
        vm.prank(deployer);
        vm.expectRevert(ERC721HCollection.QuantityZero.selector);
        col.batchMint(user1, 0);
    }

    function test_Collection_batchMint_exceedsSupply_Reverts() public {
        ERC721HCollection col = _deploy("S", "S", 3, "", SALT, ERC721HStorageLib.HistoryMode.FULL);
        vm.prank(deployer);
        vm.expectRevert(ERC721HCollection.MaxSupplyExceeded.selector);
        col.batchMint(user1, 4);
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  ERC721HCollection: batchMintTo
    // ─────────────────────────────────────────────────────────────────────────

    function test_Collection_batchMintTo_airdrop() public {
        ERC721HCollection col = _defaultCollection();
        address[] memory recipients = new address[](3);
        recipients[0] = user1;
        recipients[1] = user2;
        recipients[2] = user3;

        vm.prank(deployer);
        uint256[] memory ids = col.batchMintTo(recipients);

        assertEq(ids.length, 3);
        assertEq(col.ownerOf(ids[0]), user1);
        assertEq(col.ownerOf(ids[1]), user2);
        assertEq(col.ownerOf(ids[2]), user3);
        assertEq(col.originalCreator(ids[0]), user1);
        assertEq(col.originalCreator(ids[1]), user2);
        assertEq(col.originalCreator(ids[2]), user3);
    }

    function test_Collection_batchMintTo_emptyArray_Reverts() public {
        ERC721HCollection col = _defaultCollection();
        vm.prank(deployer);
        vm.expectRevert(ERC721HCollection.QuantityZero.selector);
        col.batchMintTo(new address[](0));
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  ERC721HCollection: publicMint
    // ─────────────────────────────────────────────────────────────────────────

    function test_Collection_publicMint_basic() public {
        ERC721HCollection col = _defaultCollection();
        vm.startPrank(deployer);
        col.setMintPrice(0.01 ether);
        col.togglePublicMint();
        vm.stopPrank();

        vm.deal(user1, 1 ether);
        vm.prank(user1);
        uint256[] memory ids = col.publicMint{value: 0.01 ether}(1);

        assertEq(ids.length, 1);
        assertEq(col.ownerOf(ids[0]), user1);
        assertEq(col.publicMintCount(user1), 1);
    }

    function test_Collection_publicMint_disabled_Reverts() public {
        ERC721HCollection col = _defaultCollection();
        vm.deal(user1, 1 ether);
        vm.prank(user1);
        vm.expectRevert(ERC721HCollection.PublicMintDisabled.selector);
        col.publicMint{value: 0.01 ether}(1);
    }

    function test_Collection_publicMint_insufficientPayment_Reverts() public {
        ERC721HCollection col = _defaultCollection();
        vm.startPrank(deployer);
        col.setMintPrice(0.1 ether);
        col.togglePublicMint();
        vm.stopPrank();

        vm.deal(user1, 1 ether);
        vm.prank(user1);
        vm.expectRevert(ERC721HCollection.InsufficientPayment.selector);
        col.publicMint{value: 0.01 ether}(1);
    }

    function test_Collection_publicMint_maxPerWallet_Reverts() public {
        ERC721HCollection col = _defaultCollection();
        vm.startPrank(deployer);
        col.setMintPrice(0);
        col.setMaxPerWallet(2);
        col.togglePublicMint();
        vm.stopPrank();

        vm.prank(user1);
        col.publicMint(2); // at limit

        vm.prank(user1);
        vm.expectRevert(ERC721HCollection.MaxPerWalletExceeded.selector);
        col.publicMint(1);
    }

    function test_Collection_publicMint_multipleUsers_separateLimits() public {
        ERC721HCollection col = _defaultCollection();
        vm.startPrank(deployer);
        col.setMintPrice(0);
        col.setMaxPerWallet(1);
        col.togglePublicMint();
        vm.stopPrank();

        vm.prank(user1);
        col.publicMint(1);
        vm.prank(user2);
        col.publicMint(1); // different wallet — passes

        assertEq(col.totalMinted(), 2);
    }

    function test_Collection_publicMint_exceedsSupply_Reverts() public {
        ERC721HCollection col = _deploy("S", "S", 1, "", SALT, ERC721HStorageLib.HistoryMode.FULL);
        vm.startPrank(deployer);
        col.setMintPrice(0);
        col.togglePublicMint();
        vm.stopPrank();

        vm.prank(user1);
        col.publicMint(1);

        vm.prank(user2);
        vm.expectRevert(ERC721HCollection.MaxSupplyExceeded.selector);
        col.publicMint(1);
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  ERC721HCollection: admin controls
    // ─────────────────────────────────────────────────────────────────────────

    function test_Collection_setBaseURI() public {
        ERC721HCollection col = _defaultCollection();
        vm.prank(deployer);
        uint256 tokenId = col.mint(user1);

        vm.prank(deployer);
        col.setBaseURI("https://new.example.com/");
        assertEq(col.tokenURI(tokenId), string.concat("https://new.example.com/", vm.toString(tokenId)));
    }

    function test_Collection_tokenURI_concatenatesId() public {
        ERC721HCollection col = _deploy("X", "X", 0, "https://meta.io/", SALT,
            ERC721HStorageLib.HistoryMode.FULL);
        vm.prank(deployer);
        uint256 tokenId = col.mint(user1);
        assertEq(col.tokenURI(tokenId), string.concat("https://meta.io/", vm.toString(tokenId)));
    }

    function test_Collection_tokenURI_emptyBaseReturnsEmpty() public {
        ERC721HCollection col = _deploy("X", "X", 0, "", SALT, ERC721HStorageLib.HistoryMode.FULL);
        vm.prank(deployer);
        uint256 tokenId = col.mint(user1);
        assertEq(col.tokenURI(tokenId), "");
    }

    function test_Collection_togglePublicMint() public {
        ERC721HCollection col = _defaultCollection();
        assertFalse(col.publicMintEnabled());
        vm.prank(deployer);
        col.togglePublicMint();
        assertTrue(col.publicMintEnabled());
        vm.prank(deployer);
        col.togglePublicMint();
        assertFalse(col.publicMintEnabled());
    }

    function test_Collection_withdraw() public {
        ERC721HCollection col = _defaultCollection();
        vm.startPrank(deployer);
        col.setMintPrice(1 ether);
        col.togglePublicMint();
        vm.stopPrank();

        vm.deal(user1, 2 ether);
        vm.prank(user1);
        col.publicMint{value: 1 ether}(1);

        uint256 ownerBalBefore = deployer.balance;
        vm.prank(deployer);
        col.withdraw();
        assertEq(deployer.balance, ownerBalBefore + 1 ether);
    }

    function test_Collection_withdraw_emptyBalance_Reverts() public {
        ERC721HCollection col = _defaultCollection();
        vm.prank(deployer);
        vm.expectRevert(ERC721HCollection.WithdrawFailed.selector);
        col.withdraw();
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  ERC721HCollection: batch views
    // ─────────────────────────────────────────────────────────────────────────

    function test_Collection_batchTokenSummary() public {
        ERC721HCollection col = _defaultCollection();
        vm.startPrank(deployer);
        uint256 t1 = col.mint(user1);
        vm.roll(block.number + 1);
        uint256 t2 = col.mint(user2);
        vm.stopPrank();

        uint256[] memory ids = new uint256[](2);
        ids[0] = t1; ids[1] = t2;
        ERC721HCollection.TokenSummary[] memory summaries = col.batchTokenSummary(ids);

        assertEq(summaries.length, 2);
        assertEq(summaries[0].creator, user1);
        assertEq(summaries[0].currentOwner, user1);
        assertEq(summaries[1].creator, user2);
        assertEq(summaries[1].currentOwner, user2);
    }

    function test_Collection_batchOwnerAtBlock() public {
        ERC721HCollection col = _defaultCollection();
        vm.prank(deployer);
        uint256 t1 = col.mint(user1);
        uint256 mintBlock = block.number;

        vm.roll(block.number + 1);
        vm.prank(deployer);
        uint256 t2 = col.mint(user2);

        uint256[] memory ids = new uint256[](2);
        ids[0] = t1; ids[1] = t2;

        address[] memory owners = col.batchOwnerAtBlock(ids, mintBlock);
        assertEq(owners[0], user1, "t1 owner at mintBlock");
        assertEq(owners[1], address(0), "t2 not yet minted at mintBlock");
    }

    function test_Collection_batchHasEverOwned() public {
        ERC721HCollection col = _defaultCollection();
        vm.prank(deployer);
        uint256 t1 = col.mint(user1);
        vm.roll(block.number + 1);
        vm.prank(deployer);
        uint256 t2 = col.mint(user2);

        uint256[] memory ids = new uint256[](2);
        ids[0] = t1; ids[1] = t2;

        bool[] memory r1 = col.batchHasEverOwned(ids, user1);
        assertEq(r1[0], true,  "user1 owns t1");
        assertEq(r1[1], false, "user1 never owned t2");

        bool[] memory r2 = col.batchHasEverOwned(ids, user2);
        assertEq(r2[0], false, "user2 never owned t1");
        assertEq(r2[1], true,  "user2 owns t2");
    }

    function test_Collection_batchOriginalCreator() public {
        ERC721HCollection col = _defaultCollection();
        vm.startPrank(deployer);
        uint256 t1 = col.mint(user1);
        uint256 t2 = col.mint(user2);
        vm.stopPrank();

        uint256[] memory ids = new uint256[](2);
        ids[0] = t1; ids[1] = t2;

        address[] memory creators = col.batchOriginalCreator(ids);
        assertEq(creators[0], user1);
        assertEq(creators[1], user2);
    }

    function test_Collection_batchTransferCount() public {
        ERC721HCollection col = _defaultCollection();
        vm.startPrank(deployer);
        uint256 t1 = col.mint(user1);
        uint256 t2 = col.mint(user2);
        vm.stopPrank();

        vm.roll(block.number + 1);
        vm.prank(user1);
        col.transferFrom(user1, user3, t1);

        uint256[] memory ids = new uint256[](2);
        ids[0] = t1; ids[1] = t2;

        uint256[] memory counts = col.batchTransferCount(ids);
        assertEq(counts[0], 1, "t1 transferred once");
        assertEq(counts[1], 0, "t2 never transferred");
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  ERC721HCollection: history modes via factory
    // ─────────────────────────────────────────────────────────────────────────

    function test_Collection_flagOnly_hasEverOwned_works() public {
        ERC721HCollection col = _deploy("F", "F", 0, "", SALT, ERC721HStorageLib.HistoryMode.FLAG_ONLY);
        vm.prank(deployer);
        uint256 tokenId = col.mint(user1);

        assertTrue(col.hasEverOwned(tokenId, user1));
        assertFalse(col.hasEverOwned(tokenId, user2));

        uint256[] memory ids = new uint256[](1);
        ids[0] = tokenId;
        bool[] memory res = col.batchHasEverOwned(ids, user1);
        assertTrue(res[0]);
    }

    function test_Collection_compressed_hashChain_via_factory() public {
        ERC721HCollection col = _deploy("C", "C", 0, "", SALT, ERC721HStorageLib.HistoryMode.COMPRESSED);
        vm.prank(deployer);
        uint256 tokenId = col.mint(user1);

        bytes32 h0 = col.getHistoryHash(tokenId);
        assertNotEq(h0, bytes32(0));

        vm.roll(block.number + 1);
        vm.prank(user1);
        col.transferFrom(user1, user2, tokenId);

        assertNotEq(col.getHistoryHash(tokenId), h0, "hash advances on transfer");
    }
}
