// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface ILccToken is IERC20 {
    function mint(address _to, uint256 _amount) external;

    function burn(address _account, uint256 _amount) external;
}
