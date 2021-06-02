// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;

import "../AccessControl/MinterAccessControl.sol";

contract AcceleratorCardAccessControl is MinterAccessControl {
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    modifier onlyOperator() {
        require(
            hasRole(OPERATOR_ROLE, msg.sender),
            "AcceleratorCardAccessControl: not operator"
        );
        _;
    }
}
