// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

import {ComplianceRegistry} from "../src/ComplianceRegistry.sol";
import {TreasuryToken} from "../src/TreasuryToken.sol";
import {NAVOracle} from "../src/NAVOracle.sol";
import {SubscriptionManager} from "../src/SubscriptionManager.sol";
import {RedemptionManager} from "../src/RedemptionManager.sol";
import {MockUSDC} from "../src/mocks/MockUSDC.sol";

contract IntegrationTest is Test {
    ComplianceRegistry registry;
    TreasuryToken token;
    NAVOracle oracle;
    SubscriptionManager subscriptions;
    RedemptionManager redemptions;
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

        subscriptions = new SubscriptionManager(
            admin,
            address(usdc),
            address(token),
            address(registry),
            address(oracle),
            fundTreasury
        );

        redemptions = new RedemptionManager(
            admin,
            address(usdc),
            address(token),
            address(registry),
            address(oracle)
        );

        vm.startPrank(admin);

        registry.grantRole(registry.KYC_ROLE(), kycOfficer);

        oracle.grantRole(oracle.NAV_UPDATER_ROLE(), navPublisher);

        subscriptions.grantRole(
            subscriptions.SETTLEMENT_ROLE(),
            settlementAgent
        );

        redemptions.grantRole(redemptions.SETTLEMENT_ROLE(), settlementAgent);

        token.grantRole(token.MINTER_ROLE(), address(subscriptions));

        token.grantRole(token.BURNER_ROLE(), address(redemptions));

        vm.stopPrank();

        vm.startPrank(kycOfficer);
        registry.verifyInvestor(rahul);

        // Redemption manager must be eligible
        // because it temporarily holds ATF.
        registry.verifyInvestor(address(redemptions));
        vm.stopPrank();

        // Mock initial investor capital.
        usdc.mint(rahul, 1_000e6);

        // Mock settlement liquidity.
        // This represents off-chain fund money
        // made available for redemption.
        usdc.mint(settlementAgent, 1_040e6);

        vm.prank(rahul);
        usdc.approve(address(subscriptions), 1_000e6);

        vm.prank(settlementAgent);
        usdc.approve(address(redemptions), 1_040e6);
    }

    function test_FullInvestmentLifecycle() public {
        // ----------------------------------
        // 1. Administrator reports NAV $1.25
        // ----------------------------------

        vm.prank(navPublisher);
        oracle.updateNAV(1.25e18);

        // ----------------------------------
        // 2. Rahul subscribes with $1,000
        // ----------------------------------

        vm.prank(rahul);
        uint256 subscriptionId = subscriptions.requestSubscription(1_000e6);

        assertEq(usdc.balanceOf(address(subscriptions)), 1_000e6);

        assertEq(token.totalSupply(), 0);

        // ----------------------------------
        // 3. Off-chain settlement confirmed
        // ----------------------------------

        vm.prank(settlementAgent);
        subscriptions.confirmSubscription(subscriptionId);

        // $1,000 / $1.25 = 800 ATF
        assertEq(token.balanceOf(rahul), 800e18);
        assertEq(token.totalSupply(), 800e18);

        assertEq(usdc.balanceOf(fundTreasury), 1_000e6);

        // ----------------------------------
        // 4. Fund NAV increases to $1.30
        // ----------------------------------

        vm.warp(block.timestamp + 1 days);

        vm.prank(navPublisher);
        oracle.updateNAV(1.30e18);

        // ----------------------------------
        // 5. Rahul requests redemption
        // ----------------------------------

        vm.prank(rahul);
        token.approve(address(redemptions), 800e18);

        vm.prank(rahul);
        uint256 redemptionId = redemptions.requestRedemption(800e18);

        assertEq(token.balanceOf(rahul), 0);

        assertEq(token.balanceOf(address(redemptions)), 800e18);

        // Escrow doesn't burn tokens.
        assertEq(token.totalSupply(), 800e18);

        // ----------------------------------
        // 6. Settlement agent completes it
        // ----------------------------------

        vm.prank(settlementAgent);
        redemptions.settleRedemption(redemptionId);

        // 800 * $1.30 = $1,040
        assertEq(usdc.balanceOf(rahul), 1_040e6);

        assertEq(token.balanceOf(rahul), 0);
        assertEq(token.balanceOf(address(redemptions)), 0);
        assertEq(token.totalSupply(), 0);

        // No USDC left in redemption escrow.
        assertEq(usdc.balanceOf(address(redemptions)), 0);
    }
}
