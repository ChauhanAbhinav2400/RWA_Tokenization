// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {AccessControl} from "openzeppelin-contracts/contracts/access/AccessControl.sol";
import {ComplianceRegistry} from "./ComplianceRegistry.sol";

contract TreasuryToken is ERC20, AccessControl {
    bytes32 public constant ISSUER_ROLE = keccak256("ISSUER_ROLE");

    ComplianceRegistry public immutable complianceRegistry;

    error InvalidAddress();
    error InvestorNotEligible(address investor);

    constructor(
        address admin,
        address registry
    ) ERC20("Abhinav Treasury Fund", "ATF") {
        if (admin == address(0) || registry == address(0)) {
            revert InvalidAddress();
        }

        _grantRole(DEFAULT_ADMIN_ROLE, admin);

        complianceRegistry = ComplianceRegistry(registry);
    }

    function mint(address to, uint256 amount) external onlyRole(ISSUER_ROLE) {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external onlyRole(ISSUER_ROLE) {
        _burn(from, amount);
    }

    function _update(
        address from,
        address to,
        uint256 amount
    ) internal override {
        // Mint: from == address(0)
        // Burn: to == address(0)

        if (from != address(0)) {
            if (!complianceRegistry.canHold(from)) {
                revert InvestorNotEligible(from);
            }
        }

        if (to != address(0)) {
            if (!complianceRegistry.canHold(to)) {
                revert InvestorNotEligible(to);
            }
        }

        super._update(from, to, amount);
    }
}
