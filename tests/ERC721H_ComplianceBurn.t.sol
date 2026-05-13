// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "forge-std/Test.sol";
import {ERC721HStorageLib} from "../src/ERC721HStorageLib.sol";
import {ERC721HCompliant} from "../src/compliance/ERC721HCompliant.sol";
import {IComplianceModule} from "../src/compliance/IComplianceModule.sol";
import {IdentityRegistry} from "../src/compliance/IdentityRegistry.sol";
import {KYCModule} from "../src/compliance/modules/KYCModule.sol";
import {CountryRestrictModule} from "../src/compliance/modules/CountryRestrictModule.sol";
import {LockUpModule} from "../src/compliance/modules/LockUpModule.sol";

/// @title ERC721H_ComplianceBurnTest
/// @notice Regression tests for the burn-path fix in compliance modules.
///
/// Before the fix, a holder whose KYC was revoked, whose jurisdiction was
/// blocked, or whose token was under an active lock-up could not burn (or be
/// burned). The token became permanently locked in the wallet with no
/// issuer recovery path — directly contradicting the LockUpModule NatSpec
/// ("Burns are always allowed") and the ERC-3643 design ERC721HCompliant
/// claims to be inspired by.
///
/// The fix short-circuits `canTransfer` (and its restriction-message twin) on
/// `to == address(0)` in each module so that burn always succeeds regardless
/// of compliance status.
contract ERC721H_ComplianceBurnTest is Test {
    ERC721HCompliant public token;
    IdentityRegistry public registry;
    KYCModule public kycModule;
    CountryRestrictModule public countryModule;
    LockUpModule public lockUpModule;

    address public alice = makeAddr("alice");

    uint16 constant US = 840;
    uint16 constant KP = 408; // restricted

    function setUp() public {
        registry = new IdentityRegistry();
        registry.registerIdentity(alice, US, 2);

        uint16[] memory blocked = new uint16[](1);
        blocked[0] = KP;

        kycModule = new KYCModule(address(registry), 1);
        countryModule = new CountryRestrictModule(address(registry), blocked);
        lockUpModule = new LockUpModule();

        token = new ERC721HCompliant(
            "BurnRegressionNFT", "BRN", ERC721HStorageLib.HistoryMode.FULL
        );

        token.addComplianceModule(IComplianceModule(address(kycModule)));
        token.addComplianceModule(IComplianceModule(address(countryModule)));
        token.addComplianceModule(IComplianceModule(address(lockUpModule)));

        lockUpModule.setTokenContract(address(token));
    }

    // ───────────────────────────────────────────────────────────────
    //  KYC revocation must not prevent burn
    // ───────────────────────────────────────────────────────────────
    function test_BurnAfterKYCRevocation() public {
        uint256 tokenId = token.mint(alice);
        assertEq(token.ownerOf(tokenId), alice);

        // Issuer revokes Alice's KYC (re-verification expired, fraud, etc.)
        registry.revokeIdentity(alice);
        assertFalse(registry.isVerified(alice));

        // Pre-flight check via the read-only helper.
        assertTrue(
            token.isTransferCompliant(alice, address(0), tokenId),
            "burn must be allowed after KYC revocation"
        );

        // Actual burn must succeed.
        vm.prank(alice);
        token.burn(tokenId);

        // Layer 3 cleared; Layer 1/2 preserved (provenance survives burn).
        vm.expectRevert();
        token.ownerOf(tokenId);
        assertEq(token.originalCreator(tokenId), alice);
        assertTrue(token.hasEverOwned(tokenId, alice));
    }

    // ───────────────────────────────────────────────────────────────
    //  Sanctioned/restricted jurisdiction must not prevent burn
    // ───────────────────────────────────────────────────────────────
    function test_BurnFromRestrictedJurisdiction() public {
        uint256 tokenId = token.mint(alice);

        // Alice's country changes to a blocked jurisdiction (sanctions added,
        // travel, regime change). She'd be locked out of transfer — but she
        // must still be able to burn.
        registry.updateCountry(alice, KP);

        assertTrue(
            token.isTransferCompliant(alice, address(0), tokenId),
            "burn must be allowed from restricted jurisdiction"
        );

        vm.prank(alice);
        token.burn(tokenId);

        assertEq(token.originalCreator(tokenId), alice);
    }

    // ───────────────────────────────────────────────────────────────
    //  Active lock-up must not prevent burn
    //  (matches LockUpModule.sol NatSpec L18: "Burns are always allowed")
    // ───────────────────────────────────────────────────────────────
    function test_BurnDuringActiveLockUp() public {
        uint256 tokenId = token.mint(alice);

        // Issuer sets per-token lockup 1 year out.
        lockUpModule.setTokenLockUp(tokenId, block.timestamp + 365 days);

        assertTrue(
            token.isTransferCompliant(alice, address(0), tokenId),
            "burn must be allowed during active lock-up"
        );

        vm.prank(alice);
        token.burn(tokenId);

        assertEq(token.originalCreator(tokenId), alice);
    }

    // ───────────────────────────────────────────────────────────────
    //  Global lock-up must not prevent burn
    // ───────────────────────────────────────────────────────────────
    function test_BurnDuringGlobalLockUp() public {
        uint256 tokenId = token.mint(alice);

        lockUpModule.setGlobalLockUp(block.timestamp + 30 days);

        assertTrue(
            token.isTransferCompliant(alice, address(0), tokenId),
            "burn must be allowed during global lock-up"
        );

        vm.prank(alice);
        token.burn(tokenId);

        assertEq(token.originalCreator(tokenId), alice);
    }

    // ───────────────────────────────────────────────────────────────
    //  Transfers from non-compliant senders must STILL be rejected
    //  (negative case — make sure the fix didn't open a transfer hole)
    // ───────────────────────────────────────────────────────────────
    function test_TransferFromNonCompliantStillBlocked() public {
        uint256 tokenId = token.mint(alice);

        // Add bob as a valid recipient.
        address bob = makeAddr("bob");
        registry.registerIdentity(bob, US, 2);

        // Now revoke alice and confirm she can't transfer.
        registry.revokeIdentity(alice);

        vm.prank(alice);
        vm.expectRevert(); // ComplianceCheckFailed via KYCModule
        token.transferFrom(alice, bob, tokenId);
    }
}
