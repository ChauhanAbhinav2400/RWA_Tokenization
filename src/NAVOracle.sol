// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControl} from "openzeppelin-contracts/contracts/access/AccessControl.sol";

contract NAVOracle is AccessControl {
    bytes32 public constant NAV_UPDATER_ROLE = keccak256("NAV_UPDATER_ROLE");

    uint256 public navPerShare;
    uint256 public lastUpdatedAt;

    uint256 public constant MAX_NAV_AGE = 2 days;

    error InvalidNAV();
    error StaleNAV();

    event NAVUpdated(uint256 nav, uint256 timestamp);

    constructor(address admin) {
        require(admin != address(0), "Invalid admin");
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    function updateNAV(uint256 newNAV) external onlyRole(NAV_UPDATER_ROLE) {
        if (newNAV == 0) revert InvalidNAV();

        navPerShare = newNAV;
        lastUpdatedAt = block.timestamp;

        emit NAVUpdated(newNAV, block.timestamp);
    }

    function getNAV() external view returns (uint256) {
        if (
            lastUpdatedAt == 0 || block.timestamp > lastUpdatedAt + MAX_NAV_AGE
        ) {
            revert StaleNAV();
        }

        return navPerShare;
    }
}
