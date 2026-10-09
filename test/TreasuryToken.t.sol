// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ComplianceRegistry} from "../src/ComplianceRegistry.sol";
import {TreasuryToken} from "../src/TreasuryToken.sol";

contract TreasuryTokenTest is Test {
    ComplianceRegistry registry;
    TreasuryToken token;

    address admin = makeAddr("admin");
    address kycOfficer = makeAddr("kycOfficer");
    address freezer = makeAddr("freezer");
    address issuer = makeAddr("issuer");
    address rahul = makeAddr("rahul");
    address priya = makeAddr("priya");
    address attacker = makeAddr("attacker");

    function setUp() public {
        registry = new ComplianceRegistry(admin);
        token = new TreasuryToken(admin, address(registry));

        vm.startPrank(admin);
        registry.grantRole(registry.KYC_ROLE(), kycOfficer);
        registry.grantRole(registry.FREEZER_ROLE(), freezer);
        token.grantRole(token.ISSUER_ROLE(), issuer);
        vm.stopPrank();

        vm.startPrank(kycOfficer);
        registry.verifyInvestor(rahul);
        registry.verifyInvestor(priya);
        vm.stopPrank();
    }

    function test_IssuerCanMintToVerifiedInvestor() public {
        vm.prank(issuer);
        token.mint(rahul, 1000e18);

        assertEq(token.balanceOf(rahul), 1000e18);
    }

    function test_CannotMintToUnverifiedInvestor() public {
        vm.prank(issuer);
        vm.expectRevert(
            abi.encodeWithSelector(
                TreasuryToken.InvestorNotEligible.selector,
                attacker
            )
        );

        token.mint(attacker, 1000e18);
    }

    function test_VerifiedInvestorsCanTransfer() public {
        vm.prank(issuer);
        token.mint(rahul, 1000e18);

        vm.prank(rahul);
        token.transfer(priya, 200e18);

        assertEq(token.balanceOf(rahul), 800e18);
        assertEq(token.balanceOf(priya), 200e18);
    }

    function test_FrozenInvestorCannotTransfer() public {
        vm.prank(issuer);
        token.mint(rahul, 1000e18);

        vm.prank(freezer);
        registry.freezeInvestor(rahul);

        vm.prank(rahul);
        vm.expectRevert(
            abi.encodeWithSelector(
                TreasuryToken.InvestorNotEligible.selector,
                rahul
            )
        );

        token.transfer(priya, 100e18);
    }

    function test_UnverifiedRecipientCannotReceive() public {
        vm.prank(issuer);
        token.mint(rahul, 1000e18);

        vm.prank(rahul);
        vm.expectRevert(
            abi.encodeWithSelector(
                TreasuryToken.InvestorNotEligible.selector,
                attacker
            )
        );

        token.transfer(attacker, 100e18);
    }

    function test_UnauthorizedCannotMint() public {
        vm.prank(attacker);
        vm.expectRevert();

        token.mint(rahul, 1000e18);
    }

    function test_TransferFromCannotBypassCompliance() public {
        vm.prank(issuer);
        token.mint(rahul, 1000e18);

        vm.prank(rahul);
        token.approve(attacker, 500e18);

        vm.prank(attacker);
        vm.expectRevert(
            abi.encodeWithSelector(
                TreasuryToken.InvestorNotEligible.selector,
                attacker
            )
        );

        token.transferFrom(rahul, attacker, 100e18);
    }
}
