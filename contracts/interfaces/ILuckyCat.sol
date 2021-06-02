// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;

import "@openzeppelin/contracts/token/ERC721/IERC721Enumerable.sol";

interface ILuckyCat is IERC721Enumerable {
    function getLuckyCat(uint256 id)
        external
        view
        returns (
            uint256,
            uint64,
            uint256,
            uint256
        );

    function getAllCatTypes() external view returns (uint256[] memory);

    function catMiningFactor(uint256 _type) external view returns (uint256);

    function activateCat(uint256 catId) external;

    function createBlindCats(
        uint256 _catType,
        uint256 _amount,
        address _to
    ) external returns (uint256[] memory);
}
