// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;
import "@openzeppelin/contracts/token/ERC721/IERC721Enumerable.sol";

interface IAcceleratorCard is IERC721Enumerable {
    function mint(
        address to,
        uint256 _factor,
        uint256 _period
    ) external returns (uint256);

    function burn(uint256 id) external;

    function cards(uint256 index)
        external
        view
        returns (
            uint256,
            uint256,
            uint256
        );

    function AcceleratorFactorMax() external view returns (uint256);

    function activateCard(uint256 id, uint256 start) external;
}
