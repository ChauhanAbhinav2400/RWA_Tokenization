// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

import {ComplianceRegistry} from "../src/ComplianceRegistry.sol";
import {TreasuryToken} from "../src/TreasuryToken.sol";
import {NAVOracle} from "../src/NAVOracle.sol";
import {SubscriptionManager} from "../src/SubscriptionManager.sol";
import {MockUSDC} from "../src/mocks/MockUSDC.sol";

contract SubscriptionManagerTest is Test {
    ComplianceRegistry registry;
    TreasuryToken token;
    NAVOracle oracle;
    SubscriptionManager manager;
    MockUSDC usdc;

    address admin = makeAddr("admin");
    address kycOfficer = makeAddr("kycOfficer");
    address navPublisher = makeAddr("navPublisher");
    address settlementAgent = makeAddr("settlementAgent");
    address fundTreasury = makeAddr("fundTreasury");
    address rahul = makeAddr("rahul");

    function setUp() public {
        registry = new ComplianceRegistry(admin);
        token = new TreasuryToken(admin, address(registry));
        oracle = new NAVOracle(admin);
        usdc = new MockUSDC();

        manager = new SubscriptionManager(
            admin,
            address(usdc),
            address(token),
            address(registry),
            address(oracle),
            fundTreasury
        );

        vm.startPrank(admin);
        registry.grantRole(registry.KYC_ROLE(), kycOfficer);
        token.grantRole(token.MINTER_ROLE(), address(manager));
        oracle.grantRole(oracle.NAV_UPDATER_ROLE(), navPublisher);
        manager.grantRole(manager.SETTLEMENT_ROLE(), settlementAgent);
        vm.stopPrank();

        vm.prank(kycOfficer);
        registry.verifyInvestor(rahul);

        vm.prank(navPublisher);
        oracle.updateNAV(1.25e18);

        usdc.mint(rahul, 1_000e6);

        vm.prank(rahul);
        usdc.approve(address(manager), 1_000e6);
    }

    function test_SubscriptionMintsCorrectShares() public {
        vm.prank(rahul);
        uint256 id = manager.requestSubscription(1_000e6);

        assertEq(usdc.balanceOf(address(manager)), 1_000e6);
        assertEq(token.balanceOf(rahul), 0);

        vm.prank(settlementAgent);
        manager.confirmSubscription(id);

        assertEq(token.balanceOf(rahul), 800e18);
        assertEq(usdc.balanceOf(fundTreasury), 1_000e6);
        assertEq(usdc.balanceOf(address(manager)), 0);
    }

    function test_CancelReturnsUSDC() public {
        vm.prank(rahul);
        uint256 id = manager.requestSubscription(1_000e6);

        vm.prank(rahul);
        manager.cancelSubscription(id);

        assertEq(usdc.balanceOf(rahul), 1_000e6);
        assertEq(token.balanceOf(rahul), 0);
    }

    function test_CannotConfirmTwice() public {
        vm.prank(rahul);
        uint256 id = manager.requestSubscription(1_000e6);

        vm.prank(settlementAgent);
        manager.confirmSubscription(id);

        vm.prank(settlementAgent);
        vm.expectRevert(SubscriptionManager.InvalidStatus.selector);
        manager.confirmSubscription(id);
    }

    function test_StaleNAVBlocksConfirmation() public {
        vm.prank(rahul);
        uint256 id = manager.requestSubscription(1_000e6);

        vm.warp(block.timestamp + 3 days);

        vm.prank(settlementAgent);
        vm.expectRevert(NAVOracle.StaleNAV.selector);
        manager.confirmSubscription(id);
    }
}
