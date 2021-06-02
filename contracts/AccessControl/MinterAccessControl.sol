// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;
import "@openzeppelin/contracts/access/AccessControl.sol";

contract MinterAccessControl is AccessControl {
    /// @notice minter role
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    /* ========== MODIFIERS ========== */

    modifier onlyOwner() {
        require(
            hasRole(DEFAULT_ADMIN_ROLE, msg.sender),
            "MinterAccessControl: not owner"
        );
        _;
    }

    modifier onlyMinter() {
        require(
            hasRole(MINTER_ROLE, msg.sender),
            "MinterAccessControl: not minter"
        );
        _;
    }
}
