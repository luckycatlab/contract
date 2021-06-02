// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "../AccessControl/AcceleratorCardAccessControl.sol";

contract AcceleratorCard is ERC721, ReentrancyGuard, AcceleratorCardAccessControl {
    using SafeMath for uint256;

    /// @notice card infomation
    struct Card {
        uint256 factor;
        uint256 startBlock;
        uint256 period;
    }

    Card[] public cards;

    uint256 public constant AcceleratorFactorMax = 1000;

    /* ========== CONSTRUCTOR ========== */

    constructor() public ERC721("Accelerator Card", "AC") {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);

        // avoid id 0
        Card memory card = Card({factor: 0, startBlock: 0, period: 0});
        cards.push(card);
    }

    /* ========== ADMIN FUNCTIONS ========== */

    function mint(
        address to,
        uint256 _factor,
        uint256 _period
    ) public onlyMinter nonReentrant returns (uint256) {
        Card memory card =
            Card({factor: _factor, startBlock: 0, period: _period});

        cards.push(card);

        uint256 id = cards.length.sub(1);

        _safeMint(to, id);

        return id;
    }

    function activateCard(uint256 id, uint256 start) public onlyOperator {
        require(_exists(id), "AcceleratorCard: card is not exist");
        Card storage card = cards[id];
        require(card.startBlock == 0, "AcceleratorCard: card has been activated");
        card.startBlock = start;
    }

    /**
     * @dev set the base URI for all token IDs. It is
     * automatically added as a prefix to the value returned in {tokenURI},
     * or to the token ID if {tokenURI} is empty.
     */
    function setBaseURI(string memory baseURI_) public virtual onlyOwner {
        _setBaseURI(baseURI_);
    }

    /**
     * @dev Sets `_tokenURI` as the tokenURI of `tokenId`.
     *
     * Requirements:
     *
     * - `tokenId` must exist.
     */
    function setTokenURI(uint256 tokenId, string memory _tokenURI)
        public
        virtual
        onlyOwner
    {
        _setTokenURI(tokenId, _tokenURI);
    }

    /* ========== PUBLIC FUNCTIONS ========== */

    function burn(uint256 id) public {
        require(
            _isApprovedOrOwner(msg.sender, id),
            "AcceleratorCard: not owner or approved"
        );
        _burn(id);
    }
}
