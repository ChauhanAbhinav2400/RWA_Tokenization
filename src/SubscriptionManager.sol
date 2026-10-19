// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControl} from "openzeppelin-contracts/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {Math} from "openzeppelin-contracts/contracts/utils/math/Math.sol";

import {TreasuryToken} from "./TreasuryToken.sol";
import {ComplianceRegistry} from "./ComplianceRegistry.sol";
import {NAVOracle} from "./NAVOracle.sol";

contract SubscriptionManager is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    bytes32 public constant SETTLEMENT_ROLE = keccak256("SETTLEMENT_ROLE");

    uint256 private constant WAD = 1e18;
    uint256 private constant USDC_SCALE = 1e12;

    enum Status {
        Pending,
        Completed,
        Cancelled
    }

    struct Subscription {
        address investor;
        uint256 amountUSDC;
        Status status;
    }

    IERC20 public immutable usdc;
    TreasuryToken public immutable token;
    ComplianceRegistry public immutable registry;
    NAVOracle public immutable oracle;

    address public immutable fundTreasury;

    uint256 public nextSubscriptionId;

    mapping(uint256 => Subscription) public subscriptions;

    error InvalidAmount();
    error NotEligible();
    error InvalidSubscription();
    error InvalidStatus();
    error ZeroShares();

    event SubscriptionRequested(
        uint256 indexed id,
        address indexed investor,
        uint256 amount
    );

    event SubscriptionCompleted(
        uint256 indexed id,
        address indexed investor,
        uint256 shares,
        uint256 nav
    );

    event SubscriptionCancelled(uint256 indexed id);

    constructor(
        address admin,
        address usdc_,
        address token_,
        address registry_,
        address oracle_,
        address fundTreasury_
    ) {
        require(
            admin != address(0) &&
                usdc_ != address(0) &&
                token_ != address(0) &&
                registry_ != address(0) &&
                oracle_ != address(0) &&
                fundTreasury_ != address(0),
            "Invalid address"
        );

        _grantRole(DEFAULT_ADMIN_ROLE, admin);

        usdc = IERC20(usdc_);
        token = TreasuryToken(token_);
        registry = ComplianceRegistry(registry_);
        oracle = NAVOracle(oracle_);
        fundTreasury = fundTreasury_;
    }

    function requestSubscription(
        uint256 amountUSDC
    ) external nonReentrant returns (uint256 id) {
        if (amountUSDC == 0) revert InvalidAmount();
        if (!registry.canHold(msg.sender)) revert NotEligible();

        id = ++nextSubscriptionId;

        subscriptions[id] = Subscription({
            investor: msg.sender,
            amountUSDC: amountUSDC,
            status: Status.Pending
        });

        usdc.safeTransferFrom(msg.sender, address(this), amountUSDC);

        emit SubscriptionRequested(id, msg.sender, amountUSDC);
    }

    function confirmSubscription(
        uint256 id
    ) external onlyRole(SETTLEMENT_ROLE) nonReentrant {
        Subscription storage sub = subscriptions[id];

        if (sub.investor == address(0)) {
            revert InvalidSubscription();
        }

        if (sub.status != Status.Pending) {
            revert InvalidStatus();
        }

        if (!registry.canHold(sub.investor)) {
            revert NotEligible();
        }

        uint256 nav = oracle.getNAV();

        // Convert 6-decimal USDC to 18-decimal USD.
        uint256 depositWad = sub.amountUSDC * USDC_SCALE;

        // ATF shares have 18 decimals.
        uint256 shares = Math.mulDiv(depositWad, WAD, nav);

        if (shares == 0) revert ZeroShares();

        sub.status = Status.Completed;

        usdc.safeTransfer(fundTreasury, sub.amountUSDC);
        token.mint(sub.investor, shares);

        emit SubscriptionCompleted(id, sub.investor, shares, nav);
    }

    function cancelSubscription(uint256 id) external nonReentrant {
        Subscription storage sub = subscriptions[id];

        if (sub.investor != msg.sender) {
            revert InvalidSubscription();
        }

        if (sub.status != Status.Pending) {
            revert InvalidStatus();
        }

        sub.status = Status.Cancelled;

        usdc.safeTransfer(sub.investor, sub.amountUSDC);

        emit SubscriptionCancelled(id);
    }
}
