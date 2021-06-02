// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;
import "@openzeppelin/contracts/access/AccessControl.sol";

contract ExternalAdminAccessControl is AccessControl {
    /// @notice external admin role
    bytes32 public constant EXTERNAL_ADMIN_ROLE =
        keccak256("EXTERNAL_ADMIN_ROLE");

    modifier onlyOwner() {
        require(
            hasRole(DEFAULT_ADMIN_ROLE, msg.sender),
            "ExternalAdminAccessControl: not owner"
        );
        _;
    }

    modifier onlyAdmin() {
        require(
            hasRole(EXTERNAL_ADMIN_ROLE, msg.sender),
            "ExternalAdminAccessControl: not admin"
        );
        _;
    }
}
