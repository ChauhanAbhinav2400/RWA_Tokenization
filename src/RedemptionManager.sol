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

contract RedemptionManager is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    bytes32 public constant SETTLEMENT_ROLE = keccak256("SETTLEMENT_ROLE");

    uint256 private constant WAD = 1e18;
    uint256 private constant USDC_SCALE = 1e12;

    enum Status {
        Pending,
        Completed,
        Cancelled
    }

    struct Redemption {
        address investor;
        uint256 shares;
        Status status;
    }

    IERC20 public immutable usdc;
    TreasuryToken public immutable token;
    ComplianceRegistry public immutable registry;
    NAVOracle public immutable oracle;

    uint256 public nextRedemptionId;

    mapping(uint256 => Redemption) public redemptions;

    error InvalidAmount();
    error NotEligible();
    error InvalidRedemption();
    error InvalidStatus();
    error ZeroPayout();

    event RedemptionRequested(
        uint256 indexed id,
        address indexed investor,
        uint256 shares
    );

    event RedemptionCompleted(
        uint256 indexed id,
        address indexed investor,
        uint256 shares,
        uint256 amountUSDC,
        uint256 nav
    );

    event RedemptionCancelled(uint256 indexed id);

    constructor(
        address admin,
        address usdc_,
        address token_,
        address registry_,
        address oracle_
    ) {
        require(
            admin != address(0) &&
                usdc_ != address(0) &&
                token_ != address(0) &&
                registry_ != address(0) &&
                oracle_ != address(0),
            "Invalid address"
        );

        _grantRole(DEFAULT_ADMIN_ROLE, admin);

        usdc = IERC20(usdc_);
        token = TreasuryToken(token_);
        registry = ComplianceRegistry(registry_);
        oracle = NAVOracle(oracle_);
    }

    function requestRedemption(
        uint256 shares
    ) external nonReentrant returns (uint256 id) {
        if (shares == 0) revert InvalidAmount();

        if (!registry.canHold(msg.sender)) {
            revert NotEligible();
        }

        id = ++nextRedemptionId;

        redemptions[id] = Redemption({
            investor: msg.sender,
            shares: shares,
            status: Status.Pending
        });

        token.transferFrom(msg.sender, address(this), shares);

        emit RedemptionRequested(id, msg.sender, shares);
    }

    function settleRedemption(
        uint256 id
    ) external onlyRole(SETTLEMENT_ROLE) nonReentrant {
        Redemption storage redemption = redemptions[id];

        if (redemption.investor == address(0)) {
            revert InvalidRedemption();
        }

        if (redemption.status != Status.Pending) {
            revert InvalidStatus();
        }

        // Current policy: frozen/revoked investors
        // cannot complete normal redemption.
        if (!registry.canHold(redemption.investor)) {
            revert NotEligible();
        }

        uint256 nav = oracle.getNAV();

        // shares: 18 decimals
        // nav: 18 decimals (USD per ATF)
        // result: 18-decimal USD amount
        uint256 payoutWad = Math.mulDiv(redemption.shares, nav, WAD);

        // Convert USD WAD to 6-decimal USDC.
        // Rounds down in favor of the fund.
        uint256 payoutUSDC = payoutWad / USDC_SCALE;

        if (payoutUSDC == 0) revert ZeroPayout();

        redemption.status = Status.Completed;

        // Settlement agent supplies liquidity.
        // If this fails, the whole transaction reverts.
        usdc.safeTransferFrom(msg.sender, address(this), payoutUSDC);

        // Manager holds the escrowed shares.
        token.burn(address(this), redemption.shares);

        // Pay investor.
        usdc.safeTransfer(redemption.investor, payoutUSDC);

        emit RedemptionCompleted(
            id,
            redemption.investor,
            redemption.shares,
            payoutUSDC,
            nav
        );
    }

    function cancelRedemption(uint256 id) external nonReentrant {
        Redemption storage redemption = redemptions[id];

        if (redemption.investor != msg.sender) {
            revert InvalidRedemption();
        }

        if (redemption.status != Status.Pending) {
            revert InvalidStatus();
        }

        if (!registry.canHold(msg.sender)) {
            revert NotEligible();
        }

        redemption.status = Status.Cancelled;

        token.transfer(msg.sender, redemption.shares);

        emit RedemptionCancelled(id);
    }
}
