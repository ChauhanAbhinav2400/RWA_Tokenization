// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ComplianceRegistry} from "../src/ComplianceRegistry.sol";

contract ComplianceRegistryTest is Test {
    ComplianceRegistry registry;

    address admin = makeAddr("admin");
    address kycOfficer = makeAddr("kycOfficer");
    address freezer = makeAddr("freezer");
    address rahul = makeAddr("rahul");
    address attacker = makeAddr("attacker");

    function setUp() public {
        vm.prank(admin);
        registry = new ComplianceRegistry(admin);

        vm.startPrank(admin);
        registry.grantRole(registry.KYC_ROLE(), kycOfficer);
        registry.grantRole(registry.FREEZER_ROLE(), freezer);
        vm.stopPrank();
    }

    function test_KYCOfficerCanVerifyInvestor() public {
        vm.prank(kycOfficer);
        registry.verifyInvestor(rahul);

        assertTrue(registry.isVerified(rahul));
        assertTrue(registry.canHold(rahul));
    }

    function test_UnverifiedInvestorCannotHold() public view {
        assertFalse(registry.canHold(rahul));
    }

    function test_FrozenInvestorCannotHold() public {
        vm.prank(kycOfficer);
        registry.verifyInvestor(rahul);

        vm.prank(freezer);
        registry.freezeInvestor(rahul);

        assertTrue(registry.isVerified(rahul));
        assertFalse(registry.canHold(rahul));
    }

    function test_UnauthorizedCannotVerify() public {
        vm.prank(attacker);
        vm.expectRevert();

        registry.verifyInvestor(rahul);
    }

    function test_RevokedInvestorCannotHold() public {
        vm.prank(kycOfficer);
        registry.verifyInvestor(rahul);

        vm.prank(kycOfficer);
        registry.revokeInvestor(rahul);

        assertFalse(registry.canHold(rahul));
    }
}
