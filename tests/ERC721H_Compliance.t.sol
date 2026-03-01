// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "forge-std/Test.sol";
import {ERC721HStorageLib} from "../src/ERC721HStorageLib.sol";
import {ERC721HCompliant} from "../src/compliance/ERC721HCompliant.sol";
import {ComplianceLib} from "../src/compliance/ComplianceLib.sol";
import {IComplianceModule} from "../src/compliance/IComplianceModule.sol";
import {IdentityRegistry} from "../src/compliance/IdentityRegistry.sol";
import {KYCModule} from "../src/compliance/modules/KYCModule.sol";
import {CountryRestrictModule} from "../src/compliance/modules/CountryRestrictModule.sol";
import {MaxHoldersModule} from "../src/compliance/modules/MaxHoldersModule.sol";
import {LockUpModule} from "../src/compliance/modules/LockUpModule.sol";

/// @title ERC721H Compliance Module Test Suite
/// @notice Tests the ERC-3643-inspired modular compliance framework integrated with ERC-721H.
contract ERC721H_ComplianceTest is Test {

    // ── Contracts ──
    ERC721HCompliant public token;
    IdentityRegistry public registry;
    KYCModule public kycModule;
    CountryRestrictModule public countryModule;
    MaxHoldersModule public maxHoldersModule;
    LockUpModule public lockUpModule;

    // ── Actors ──
    address public deployer;
    address public alice   = makeAddr("alice");
    address public bob     = makeAddr("bob");
    address public charlie = makeAddr("charlie");
    address public dave    = makeAddr("dave");
    address public eve     = makeAddr("eve");

    // ── Constants ──
    uint16 constant US = 840;
    uint16 constant GB = 826;
    uint16 constant KP = 408; // North Korea (restricted)
    uint16 constant IR = 364; // Iran (restricted)
    uint16 constant DE = 276;

    function setUp() public {
        deployer = address(this);

        // 1. Deploy identity registry
        registry = new IdentityRegistry();

        // 2. Register identities (deployer is admin + agent by default)
        registry.registerIdentity(alice,   US, 2); // US, enhanced KYC
        registry.registerIdentity(bob,     GB, 2); // UK, enhanced KYC
        registry.registerIdentity(charlie, DE, 1); // Germany, basic KYC
        registry.registerIdentity(dave,    KP, 2); // North Korea, enhanced KYC

        // 3. Deploy compliance modules
        uint16[] memory blocked = new uint16[](2);
        blocked[0] = KP;
        blocked[1] = IR;

        kycModule      = new KYCModule(address(registry), 1); // Require KYC level >= 1
        countryModule  = new CountryRestrictModule(address(registry), blocked);
        maxHoldersModule = new MaxHoldersModule(3); // Cap at 3 unique holders
        lockUpModule   = new LockUpModule();

        // 4. Deploy compliant token (FULL history mode)
        token = new ERC721HCompliant("ComplianceNFT", "CNFT", ERC721HStorageLib.HistoryMode.FULL);

        // 5. Wire modules to token
        token.addComplianceModule(IComplianceModule(address(kycModule)));
        token.addComplianceModule(IComplianceModule(address(countryModule)));
        token.addComplianceModule(IComplianceModule(address(maxHoldersModule)));
        token.addComplianceModule(IComplianceModule(address(lockUpModule)));

        // 6. Set token contract on stateful modules
        maxHoldersModule.setTokenContract(address(token));
        lockUpModule.setTokenContract(address(token));
        token.setMaxHoldersModule(maxHoldersModule);
    }

    // ════════════════════════════════════════════════════════════════
    //  IDENTITY REGISTRY TESTS
    // ════════════════════════════════════════════════════════════════

    function test_RegistryVerifiedStatus() public view {
        assertTrue(registry.isVerified(alice));
        assertTrue(registry.isVerified(bob));
        assertTrue(registry.isVerified(charlie));
        assertFalse(registry.isVerified(eve)); // Never registered
    }

    function test_RegistryCountryCodes() public view {
        assertEq(registry.getCountry(alice), US);
        assertEq(registry.getCountry(bob), GB);
        assertEq(registry.getCountry(dave), KP);
    }

    function test_RegistryKYCLevels() public view {
        assertEq(registry.getKYCLevel(alice), 2);
        assertEq(registry.getKYCLevel(charlie), 1);
    }

    function test_RegistryRevokeIdentity() public {
        registry.revokeIdentity(alice);
        assertFalse(registry.isVerified(alice));
    }

    function test_RegistryUpdateCountry() public {
        registry.updateCountry(alice, GB);
        assertEq(registry.getCountry(alice), GB);
    }

    function test_RegistryUpdateKYCLevel() public {
        registry.updateKYCLevel(charlie, 3);
        assertEq(registry.getKYCLevel(charlie), 3);
    }

    function test_RegistryRevertDuplicateRegister() public {
        vm.expectRevert(abi.encodeWithSignature("IdentityAlreadyRegistered()"));
        registry.registerIdentity(alice, US, 1);
    }

    function test_RegistryRevertNonAgent() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature("NotAgent()"));
        registry.registerIdentity(eve, US, 1);
    }

    function test_RegistryAgentManagement() public {
        registry.addAgent(alice);
        assertTrue(registry.isAgent(alice));
        registry.removeAgent(alice);
        assertFalse(registry.isAgent(alice));
    }

    // ════════════════════════════════════════════════════════════════
    //  KYC MODULE TESTS
    // ════════════════════════════════════════════════════════════════

    function test_KYCModuleName() public view {
        assertEq(kycModule.moduleName(), "KYC Verification");
    }

    function test_KYCAllowsVerifiedParties() public view {
        assertTrue(kycModule.canTransfer(alice, bob, 1));
    }

    function test_KYCBlocksUnverifiedReceiver() public view {
        assertFalse(kycModule.canTransfer(alice, eve, 1));
    }

    function test_KYCBlocksUnverifiedSender() public view {
        assertFalse(kycModule.canTransfer(eve, alice, 1));
    }

    function test_KYCAllowsMintToVerified() public view {
        assertTrue(kycModule.canTransfer(address(0), alice, 1));
    }

    function test_KYCBlocksMintToUnverified() public view {
        assertFalse(kycModule.canTransfer(address(0), eve, 1));
    }

    function test_KYCAllowsBurnFromVerified() public view {
        assertTrue(kycModule.canTransfer(alice, address(0), 1));
    }

    function test_KYCMinimumLevelEnforced() public {
        // Charlie has KYC level 1, set minimum to 2
        kycModule.setMinimumKYCLevel(2);
        assertFalse(kycModule.canTransfer(charlie, alice, 1));
        // Alice still passes (level 2)
        assertTrue(kycModule.canTransfer(alice, bob, 1));
        // Reset
        kycModule.setMinimumKYCLevel(1);
    }

    function test_KYCRestrictionMessages() public view {
        string memory msg1 = kycModule.transferRestrictionMessage(alice, eve, 1);
        assertEq(msg1, "Receiver lacks required KYC verification");

        string memory msg2 = kycModule.transferRestrictionMessage(eve, alice, 1);
        assertEq(msg2, "Sender lacks required KYC verification");

        string memory msg3 = kycModule.transferRestrictionMessage(alice, bob, 1);
        assertEq(msg3, "");
    }

    function test_KYCBlocksRevokedIdentity() public {
        registry.revokeIdentity(bob);
        assertFalse(kycModule.canTransfer(alice, bob, 1));
    }

    // ════════════════════════════════════════════════════════════════
    //  COUNTRY RESTRICTION MODULE TESTS
    // ════════════════════════════════════════════════════════════════

    function test_CountryModuleName() public view {
        assertEq(countryModule.moduleName(), "Country Restriction");
    }

    function test_CountryAllowsNonRestricted() public view {
        assertTrue(countryModule.canTransfer(alice, bob, 1)); // US → GB — both OK
    }

    function test_CountryBlocksRestrictedSender() public view {
        assertFalse(countryModule.canTransfer(dave, alice, 1)); // KP → US — blocked
    }

    function test_CountryBlocksRestrictedReceiver() public view {
        assertFalse(countryModule.canTransfer(alice, dave, 1)); // US → KP — blocked
    }

    function test_CountryBlockMintToRestricted() public view {
        assertFalse(countryModule.canTransfer(address(0), dave, 1));
    }

    function test_CountryAllowMintToNonRestricted() public view {
        assertTrue(countryModule.canTransfer(address(0), alice, 1));
    }

    function test_CountryDynamicBlockUnblock() public {
        // Block US
        countryModule.blockCountry(US);
        assertFalse(countryModule.canTransfer(alice, bob, 1));

        // Unblock US
        countryModule.unblockCountry(US);
        assertTrue(countryModule.canTransfer(alice, bob, 1));
    }

    function test_CountryBatchBlock() public {
        uint16[] memory countries = new uint16[](2);
        countries[0] = US;
        countries[1] = GB;
        countryModule.batchBlockCountries(countries);
        assertFalse(countryModule.canTransfer(alice, bob, 1));
    }

    function test_CountryRestrictionMessages() public view {
        string memory msg1 = countryModule.transferRestrictionMessage(dave, alice, 1);
        assertEq(msg1, "Sender in restricted jurisdiction");

        string memory msg2 = countryModule.transferRestrictionMessage(alice, dave, 1);
        assertEq(msg2, "Receiver in restricted jurisdiction");
    }

    // ════════════════════════════════════════════════════════════════
    //  MAX HOLDERS MODULE TESTS
    // ════════════════════════════════════════════════════════════════

    function test_MaxHoldersModuleName() public view {
        assertEq(maxHoldersModule.moduleName(), "Max Holders Cap");
    }

    function test_MaxHoldersAllowsUnderCap() public view {
        // 0 holders, cap = 3 → new holder allowed
        assertTrue(maxHoldersModule.canTransfer(address(0), alice, 1));
    }

    function test_MaxHoldersBlocksOverCap() public {
        // Fill to cap via token mints (callbacks update holder tracking)
        token.mint(alice);
        token.mint(bob);
        token.mint(charlie);

        // 3 holders = cap. Eve would be 4th → blocked
        assertFalse(maxHoldersModule.canTransfer(alice, eve, 1));
    }

    function test_MaxHoldersAllowsExistingHolder() public {
        token.mint(alice);
        token.mint(bob);
        token.mint(charlie);

        // Bob already holds — no new holder added → allowed
        assertTrue(maxHoldersModule.canTransfer(alice, bob, 1));
    }

    function test_MaxHoldersAllowsBurn() public view {
        assertTrue(maxHoldersModule.canTransfer(alice, address(0), 1));
    }

    function test_MaxHoldersTrackingAfterBurn() public {
        uint256 t1 = token.mint(alice);
        token.mint(bob);
        token.mint(charlie);

        // 3 holders at cap. Burn alice's token → 2 holders
        vm.prank(alice);
        token.burn(t1);

        // Now eve would be 3rd → should be allowed
        assertTrue(maxHoldersModule.canTransfer(bob, eve, 1));
    }

    function test_MaxHoldersSetMaxHolders() public {
        uint256 oldMax = maxHoldersModule.maxHolders();
        maxHoldersModule.setMaxHolders(5);
        assertEq(maxHoldersModule.maxHolders(), 5);
        maxHoldersModule.setMaxHolders(oldMax);
    }

    // ════════════════════════════════════════════════════════════════
    //  LOCK-UP MODULE TESTS
    // ════════════════════════════════════════════════════════════════

    function test_LockUpModuleName() public view {
        assertEq(lockUpModule.moduleName(), "Lock-Up Period");
    }

    function test_LockUpAllowsMint() public view {
        assertTrue(lockUpModule.canTransfer(address(0), alice, 1));
    }

    function test_LockUpGlobalBlock() public {
        // Set global lock 1 hour in the future
        lockUpModule.setGlobalLockUp(block.timestamp + 3600);
        assertFalse(lockUpModule.canTransfer(alice, bob, 1));

        // Warp past the lock
        vm.warp(block.timestamp + 3601);
        assertTrue(lockUpModule.canTransfer(alice, bob, 1));
    }

    function test_LockUpPerToken() public {
        uint256 lockUntil = block.timestamp + 86400; // 1 day
        lockUpModule.setTokenLockUp(1, lockUntil);

        assertFalse(lockUpModule.canTransfer(alice, bob, 1)); // Token 1 locked
        assertTrue(lockUpModule.canTransfer(alice, bob, 2));  // Token 2 not locked

        vm.warp(lockUntil + 1);
        assertTrue(lockUpModule.canTransfer(alice, bob, 1)); // Expired
    }

    function test_LockUpBatchSet() public {
        uint256[] memory ids = new uint256[](3);
        ids[0] = 1;
        ids[1] = 2;
        ids[2] = 3;
        uint256 lockUntil = block.timestamp + 3600;
        lockUpModule.batchSetTokenLockUp(ids, lockUntil);

        assertFalse(lockUpModule.canTransfer(alice, bob, 1));
        assertFalse(lockUpModule.canTransfer(alice, bob, 2));
        assertFalse(lockUpModule.canTransfer(alice, bob, 3));
        assertTrue(lockUpModule.canTransfer(alice, bob, 4));  // Not in batch
    }

    function test_LockUpDisableGlobal() public {
        lockUpModule.setGlobalLockUp(block.timestamp + 3600);
        assertFalse(lockUpModule.canTransfer(alice, bob, 1));

        lockUpModule.setGlobalLockUp(0); // Disable
        assertTrue(lockUpModule.canTransfer(alice, bob, 1));
    }

    function test_LockUpRestrictionMessages() public {
        lockUpModule.setGlobalLockUp(block.timestamp + 3600);
        assertEq(lockUpModule.transferRestrictionMessage(alice, bob, 1), "Global lock-up period active");

        lockUpModule.setGlobalLockUp(0);
        lockUpModule.setTokenLockUp(1, block.timestamp + 3600);
        assertEq(lockUpModule.transferRestrictionMessage(alice, bob, 1), "Token-specific lock-up period active");

        lockUpModule.setTokenLockUp(1, 0);
        assertEq(lockUpModule.transferRestrictionMessage(alice, bob, 1), "");
    }

    function test_LockUpMintAlwaysAllowed() public view {
        assertEq(lockUpModule.transferRestrictionMessage(address(0), alice, 1), "");
    }

    // ════════════════════════════════════════════════════════════════
    //  COMPLIANCE LIB TESTS (via ERC721HCompliant)
    // ════════════════════════════════════════════════════════════════

    function test_ComplianceModuleCount() public view {
        assertEq(token.complianceModuleCount(), 4);
    }

    function test_ComplianceModuleOrdering() public view {
        assertEq(address(token.complianceModuleAt(0)), address(kycModule));
        assertEq(address(token.complianceModuleAt(1)), address(countryModule));
        assertEq(address(token.complianceModuleAt(2)), address(maxHoldersModule));
        assertEq(address(token.complianceModuleAt(3)), address(lockUpModule));
    }

    function test_ComplianceAddRemoveModule() public {
        LockUpModule newModule = new LockUpModule();
        
        // Remove lock-up
        token.removeComplianceModule(IComplianceModule(address(lockUpModule)));
        assertEq(token.complianceModuleCount(), 3);

        // Add new lock-up
        token.addComplianceModule(IComplianceModule(address(newModule)));
        assertEq(token.complianceModuleCount(), 4);
    }

    function test_ComplianceRevertDuplicateModule() public {
        vm.expectRevert(
            abi.encodeWithSelector(ComplianceLib.ModuleAlreadyRegistered.selector, address(kycModule))
        );
        token.addComplianceModule(IComplianceModule(address(kycModule)));
    }

    function test_ComplianceRevertRemoveUnregistered() public {
        LockUpModule fake = new LockUpModule();
        vm.expectRevert(
            abi.encodeWithSelector(ComplianceLib.ModuleNotRegistered.selector, address(fake))
        );
        token.removeComplianceModule(IComplianceModule(address(fake)));
    }

    function test_ComplianceOnlyOwnerCanAddModule() public {
        LockUpModule newModule = new LockUpModule();
        vm.prank(alice);
        vm.expectRevert(); // NotAuthorized
        token.addComplianceModule(IComplianceModule(address(newModule)));
    }

    // ════════════════════════════════════════════════════════════════
    //  END-TO-END INTEGRATION TESTS
    // ════════════════════════════════════════════════════════════════

    function test_E2E_MintToVerifiedInvestor() public {
        uint256 tokenId = token.mint(alice);
        assertEq(token.ownerOf(tokenId), alice);
        assertEq(token.totalSupply(), 1);
    }

    function test_E2E_MintToUnverifiedReverts() public {
        // Eve has no KYC — mint should fail at KYCModule
        vm.expectRevert();
        token.mint(eve);
    }

    function test_E2E_MintToRestrictedCountryReverts() public {
        // Dave is KP (blocked) — mint should fail at CountryRestrictModule
        vm.expectRevert();
        token.mint(dave);
    }

    function test_E2E_TransferBetweenVerifiedInvestors() public {
        uint256 tokenId = token.mint(alice);

        // Advance block to avoid same-block sybil guard
        vm.roll(block.number + 1);

        vm.prank(alice);
        token.transferFrom(alice, bob, tokenId);
        assertEq(token.ownerOf(tokenId), bob);
    }

    function test_E2E_TransferToUnverifiedReverts() public {
        uint256 tokenId = token.mint(alice);

        vm.prank(alice);
        vm.expectRevert();
        token.transferFrom(alice, eve, tokenId);
    }

    function test_E2E_TransferDuringLockUpReverts() public {
        uint256 tokenId = token.mint(alice);
        lockUpModule.setTokenLockUp(tokenId, block.timestamp + 86400);

        vm.prank(alice);
        vm.expectRevert();
        token.transferFrom(alice, bob, tokenId);
    }

    function test_E2E_TransferAfterLockUpExpires() public {
        uint256 tokenId = token.mint(alice);
        lockUpModule.setTokenLockUp(tokenId, block.timestamp + 86400);

        // Warp past lock-up
        vm.warp(block.timestamp + 86401);
        vm.roll(block.number + 1);

        vm.prank(alice);
        token.transferFrom(alice, bob, tokenId);
        assertEq(token.ownerOf(tokenId), bob);
    }

    function test_E2E_MaxHoldersCapEnforced() public {
        // Register eve with KYC so only MaxHolders blocks her
        registry.registerIdentity(eve, DE, 2);

        token.mint(alice);
        token.mint(bob);
        token.mint(charlie);

        // 3 holders = cap. Mint to eve should fail
        vm.expectRevert();
        token.mint(eve);
    }

    function test_E2E_MaxHoldersAllowsAfterBurn() public {
        registry.registerIdentity(eve, DE, 2);

        uint256 t1 = token.mint(alice);
        token.mint(bob);
        token.mint(charlie);

        // Burn one of alice's tokens
        vm.prank(alice);
        token.burn(t1);

        // Now alice has 0 balance → 2 holders → eve mint should work
        token.mint(eve);
        assertEq(token.totalSupply(), 3);
    }

    function test_E2E_GlobalLockBlocksAllTransfers() public {
        uint256 tokenId = token.mint(alice);
        lockUpModule.setGlobalLockUp(block.timestamp + 3600);

        vm.prank(alice);
        vm.expectRevert();
        token.transferFrom(alice, bob, tokenId);

        // Warp past
        vm.warp(block.timestamp + 3601);
        vm.roll(block.number + 1);

        vm.prank(alice);
        token.transferFrom(alice, bob, tokenId);
        assertEq(token.ownerOf(tokenId), bob);
    }

    function test_E2E_PreflightCheck() public {
        token.mint(alice);

        // Check pre-flight for valid transfer
        assertTrue(token.isTransferCompliant(alice, bob, 1));

        // Check pre-flight for invalid (unverified receiver)
        assertFalse(token.isTransferCompliant(alice, eve, 1));
    }

    function test_E2E_RevokeKYCBlocksTransfer() public {
        uint256 tokenId = token.mint(alice);

        // Revoke bob's KYC
        registry.revokeIdentity(bob);

        vm.prank(alice);
        vm.expectRevert();
        token.transferFrom(alice, bob, tokenId);
    }

    function test_E2E_ProvenancePreservedWithCompliance() public {
        // Mint to alice
        uint256 tokenId = token.mint(alice);

        // Advance block to avoid same-block sybil guard
        vm.roll(block.number + 1);

        // Transfer to bob
        vm.prank(alice);
        token.transferFrom(alice, bob, tokenId);

        // Verify ERC-721H provenance is maintained
        assertEq(token.originalCreator(tokenId), alice);
        assertTrue(token.hasEverOwned(tokenId, alice));
        assertTrue(token.hasEverOwned(tokenId, bob));
        assertEq(token.ownerOf(tokenId), bob);
    }

    function test_E2E_BurnAllowedForVerified() public {
        uint256 tokenId = token.mint(alice);

        vm.prank(alice);
        token.burn(tokenId);
        assertEq(token.totalSupply(), 0);
    }

    function test_E2E_ModuleSwapAtRuntime() public {
        // Remove KYC module
        token.removeComplianceModule(IComplianceModule(address(kycModule)));

        // Now unverified eve can receive (only country + maxHolders + lockUp remain)
        // But eve has no identity in registry → country module does try/catch → defers
        // Let's register eve with non-restricted country for clean test
        registry.registerIdentity(eve, DE, 0); // KYC level 0, but no KYC module active

        token.mint(eve); // Should succeed — no KYC module to block
        assertEq(token.ownerOf(1), eve);

        // Re-add KYC module
        token.addComplianceModule(IComplianceModule(address(kycModule)));

        // Now eve can't receive because KYC level 0 < minimum 1
        vm.expectRevert();
        token.mint(eve);
    }

    // ════════════════════════════════════════════════════════════════
    //  ACCESS CONTROL TESTS
    // ════════════════════════════════════════════════════════════════

    function test_ACL_KYCModuleOwnerOnly() public {
        vm.prank(alice);
        vm.expectRevert();
        kycModule.setMinimumKYCLevel(3);
    }

    function test_ACL_CountryModuleOwnerOnly() public {
        vm.prank(alice);
        vm.expectRevert();
        countryModule.blockCountry(US);
    }

    function test_ACL_MaxHoldersOwnerOnly() public {
        vm.prank(alice);
        vm.expectRevert();
        maxHoldersModule.setMaxHolders(10);
    }

    function test_ACL_LockUpOwnerOnly() public {
        vm.prank(alice);
        vm.expectRevert();
        lockUpModule.setGlobalLockUp(block.timestamp + 3600);
    }

    function test_ACL_MaxHoldersOnlyTokenCallback() public {
        vm.prank(alice);
        vm.expectRevert();
        maxHoldersModule.onTransferCompleted(alice, bob);
    }

    function test_ACL_LockUpOnlyTokenOrOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        lockUpModule.setTokenLockUp(1, block.timestamp + 3600);
    }

    function test_ACL_RegistryOnlyAdmin() public {
        vm.prank(alice);
        vm.expectRevert();
        registry.addAgent(eve);
    }

    // ════════════════════════════════════════════════════════════════
    //  EDGE CASES
    // ════════════════════════════════════════════════════════════════

    function test_Edge_TransferToSelfReverts() public {
        uint256 tokenId = token.mint(alice);
        vm.roll(block.number + 1);
        vm.prank(alice);
        vm.expectRevert(); // ERC-721H disallows self-transfer
        token.transferFrom(alice, alice, tokenId);
    }

    function test_Edge_MultipleTokensSameHolder() public {
        token.mint(alice);
        token.mint(alice);
        token.mint(alice);

        assertEq(token.balanceOf(alice), 3);
        assertEq(maxHoldersModule.currentHolders(), 1); // Still 1 unique holder
    }

    function test_Edge_ZeroModulesAllowAll() public {
        // Deploy token with no modules
        ERC721HCompliant bare = new ERC721HCompliant("Bare", "BARE", ERC721HStorageLib.HistoryMode.FULL);

        // Even unregistered wallets can receive
        bare.mint(eve);
        assertEq(bare.ownerOf(1), eve);
    }

    function test_Edge_ModuleCapEnforced() public {
        // Deploy fresh token, add 10 dummy modules
        ERC721HCompliant fresh = new ERC721HCompliant("Cap", "CAP", ERC721HStorageLib.HistoryMode.FULL);

        for (uint256 i; i < 10; ++i) {
            LockUpModule dummy = new LockUpModule();
            fresh.addComplianceModule(IComplianceModule(address(dummy)));
        }

        // 11th should revert
        LockUpModule oneMore = new LockUpModule();
        vm.expectRevert(ComplianceLib.TooManyModules.selector);
        fresh.addComplianceModule(IComplianceModule(address(oneMore)));
    }
}
