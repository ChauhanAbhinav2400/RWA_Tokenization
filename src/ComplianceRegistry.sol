// SPDX-License-Identifier : MIT
pragma solidity ^0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

contract ComplianceRegistry is AccessControl {
    bytes32 public constant KYC_ROLE = keccak256("KYC_ROLE");
    bytes32 public constant FREEZER_ROLE = keccak256("FREEZER_ROLE");

    mapping(address => bool) public isVerified;
    mapping(address => bool) public isFrozen;

    event InvestorVerified(address indexed investor);
    event InvestorRevoked(address indexed investor);
    event InvestorFrozen(address indexed investor);
    event InvestorUnfrozen(address indexed investor);

    constructor(address admin) {
        require(admin != address(0), "Invalid admin address");
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    function verifyInvestor(address investor) external onlyRole(KYC_ROLE) {
        require(investor != address(0), "Invalid investor address");
        require(!isVerified[investor], "Investor already verified");
        isVerified[investor] = true;
        emit InvestorVerified(investor);
    }

    function revokeInvestor(address investor) external onlyRole(KYC_ROLE) {
        require(investor != address(0), "Invalid investor address");
        require(isVerified[investor], "Investor not verified");
        isVerified[investor] = false;
        emit InvestorRevoked(investor);
    }

    function freezeInvestor(address investor) external onlyRole(FREEZER_ROLE) {
        require(investor != address(0), "Invalid investor address");
        require(!isFrozen[investor], "Investor already frozen");
        isFrozen[investor] = true;
        emit InvestorFrozen(investor);
    }

    function unfreezeInvestor(
        address investor
    ) external onlyRole(FREEZER_ROLE) {
        require(investor != address(0), "Invalid investor address");
        require(isFrozen[investor], "Investor not frozen");
        isFrozen[investor] = false;
        emit InvestorUnfrozen(investor);
    }

    function canHold(address investor) external view returns (bool) {
        require(investor != address(0), "Invalid investor address");
        return isVerified[investor] && !isFrozen[investor];
    }
}
