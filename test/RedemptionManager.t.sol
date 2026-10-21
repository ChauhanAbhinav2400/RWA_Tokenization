// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

import {ComplianceRegistry} from "../src/ComplianceRegistry.sol";
import {TreasuryToken} from "../src/TreasuryToken.sol";
import {NAVOracle} from "../src/NAVOracle.sol";
import {RedemptionManager} from "../src/RedemptionManager.sol";
import {MockUSDC} from "../src/mocks/MockUSDC.sol";

contract RedemptionManagerTest is Test {
    ComplianceRegistry registry;
    TreasuryToken token;
    NAVOracle oracle;
    RedemptionManager manager;
    MockUSDC usdc;

    address admin = makeAddr("admin");
    address kycOfficer = makeAddr("kycOfficer");
    address freezer = makeAddr("freezer");
    address navPublisher = makeAddr("navPublisher");
    address settlementAgent = makeAddr("settlementAgent");
    address rahul = makeAddr("rahul");

    function setUp() public {
        registry = new ComplianceRegistry(admin);
        token = new TreasuryToken(admin, address(registry));
        oracle = new NAVOracle(admin);
        usdc = new MockUSDC();

        manager = new RedemptionManager(
            admin,
            address(usdc),
            address(token),
            address(registry),
            address(oracle)
        );

        vm.startPrank(admin);
        registry.grantRole(registry.KYC_ROLE(), kycOfficer);
        registry.grantRole(registry.FREEZER_ROLE(), freezer);
        token.grantRole(token.MINTER_ROLE(), admin);

        token.grantRole(token.BURNER_ROLE(), address(manager));
        oracle.grantRole(oracle.NAV_UPDATER_ROLE(), navPublisher);
        manager.grantRole(manager.SETTLEMENT_ROLE(), settlementAgent);
        vm.stopPrank();

        vm.startPrank(kycOfficer);
        registry.verifyInvestor(rahul);
        registry.verifyInvestor(address(manager));
        vm.stopPrank();

        vm.prank(admin);
        token.mint(rahul, 800e18);

        vm.prank(navPublisher);
        oracle.updateNAV(1.30e18);

        usdc.mint(settlementAgent, 2_000e6);

        vm.prank(settlementAgent);
        usdc.approve(address(manager), 2_000e6);

        vm.prank(rahul);
        token.approve(address(manager), 800e18);
    }

    function test_RedemptionPaysCorrectAmount() public {
        vm.prank(rahul);
        uint256 id = manager.requestRedemption(800e18);

        assertEq(token.balanceOf(rahul), 0);
        assertEq(token.balanceOf(address(manager)), 800e18);

        vm.prank(settlementAgent);
        manager.settleRedemption(id);

        assertEq(usdc.balanceOf(rahul), 1_040e6);
        assertEq(token.balanceOf(address(manager)), 0);
        assertEq(token.totalSupply(), 0);
    }

    function test_CancellationReturnsShares() public {
        vm.prank(rahul);
        uint256 id = manager.requestRedemption(800e18);

        vm.prank(rahul);
        manager.cancelRedemption(id);

        assertEq(token.balanceOf(rahul), 800e18);
        assertEq(token.totalSupply(), 800e18);
    }

    function test_CannotSettleTwice() public {
        vm.prank(rahul);
        uint256 id = manager.requestRedemption(800e18);

        vm.prank(settlementAgent);
        manager.settleRedemption(id);

        vm.prank(settlementAgent);
        vm.expectRevert(RedemptionManager.InvalidStatus.selector);
        manager.settleRedemption(id);
    }

    function test_InsufficientLiquidityRevertsAtomically() public {
        vm.prank(rahul);
        uint256 id = manager.requestRedemption(800e18);

        // Remove settlement agent's USDC.
        vm.prank(settlementAgent);
        usdc.transfer(admin, 2_000e6);

        vm.prank(settlementAgent);
        vm.expectRevert();
        manager.settleRedemption(id);

        // No shares burned, request remains pending.
        assertEq(token.totalSupply(), 800e18);
        assertEq(token.balanceOf(address(manager)), 800e18);

        (, , RedemptionManager.Status status) = manager.redemptions(id);

        assertEq(uint256(status), uint256(RedemptionManager.Status.Pending));
    }

    function test_FrozenInvestorCannotSettleNormally() public {
        vm.prank(rahul);
        uint256 id = manager.requestRedemption(800e18);

        vm.prank(freezer);
        registry.freezeInvestor(rahul);

        vm.prank(settlementAgent);
        vm.expectRevert(RedemptionManager.NotEligible.selector);
        manager.settleRedemption(id);
    }

    function test_StaleNAVBlocksSettlement() public {
        vm.prank(rahul);
        uint256 id = manager.requestRedemption(800e18);

        vm.warp(block.timestamp + 3 days);

        vm.prank(settlementAgent);
        vm.expectRevert(NAVOracle.StaleNAV.selector);
        manager.settleRedemption(id);
    }
}
