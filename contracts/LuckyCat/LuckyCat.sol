// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "../AccessControl/MinterAccessControl.sol";

contract LuckyCatBase is MinterAccessControl {
    using EnumerableSet for EnumerableSet.UintSet;

    /* ========== ENUM ========== */

    /// @notice lucky cat states
    enum LuckyCatState {Blind, Active, Burned}

    /* ========== LUCKYCAT STRUCT ========== */

    struct LuckyCat {
        uint256 _type; // cat card type
        uint64 birthTime; // birthtime
        uint256 MiningFactor; // nft mining factor
        LuckyCatState state; // cat state
    }

    /* ========== VARIABLES ========== */

    /// @notice from cat type to cat mining factor
    mapping(uint256 => uint256) public catMiningFactor;

    /// @dev lucky cat types
    EnumerableSet.UintSet types;

    /// @dev all lucky cats
    LuckyCat[] LuckyCats;

    /* ========== VIEWS ========== */

    /**
     * @notice get lucky cat infomation by `id`
     */
    function getLuckyCat(uint256 id)
        public
        view
        returns (
            uint256,
            uint64,
            uint256,
            uint256
        )
    {
        LuckyCat storage cat = LuckyCats[id];

        if (cat.state == LuckyCatState.Active) {
            return (
                cat._type,
                cat.birthTime,
                cat.MiningFactor,
                uint256(cat.state)
            );
        } else {
            return (0, 0, 0, uint256(cat.state));
        }
    }

    /**
     * @notice get all lucky cat types
     */
    function getAllCatTypes() public view returns (uint256[] memory) {
        uint256 len = types.length();
        uint256[] memory _types = new uint256[](len);

        for (uint256 i = 0; i < len; i++) {
            _types[i] = types.at(i);
        }
        return _types;
    }

    /* ========== OWNER MUTATIVE FUNCTION ========== */

    /**
     * @dev set LuckyCat `_type` and it's `_miningFactor`
     */
    function setTypesAndMiningFactor(uint256 _type, uint256 _miningFactor)
        public
        onlyOwner
    {
        require(_type != 0, "LuckyCatBase: cat type error");
        if (!types.contains(_type)) {
            types.add(_type);
        }
        catMiningFactor[_type] = _miningFactor;
    }
}

contract LuckyCatCore is LuckyCatBase, ERC721, ReentrancyGuard {
    /* ========== EVENTS ========== */

    event CreateCats(
        uint256 _catType,
        uint256 _state,
        address _to,
        uint256[] ids
    );

    event BurnCat(address _burner, uint256 _catId);

    event ActivateCat(address activator, uint256 catId);

    /* ========== CONSTRUCTOR ========== */

    constructor() public ERC721("Lucky Cat", "LC") {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);

        // avoid id 0
        LuckyCat memory cat =
            LuckyCat({
                _type: 0,
                birthTime: uint64(0),
                MiningFactor: 0,
                state: LuckyCatState.Burned
            });
        LuckyCats.push(cat);
    }

    /* ========== OWNER FUNCTIONS ========== */

    /**
     * @dev create `_amount` Blind state cats
     */
    function createBlindCats(
        uint256 _catType,
        uint256 _amount,
        address _to
    ) public nonReentrant onlyMinter returns (uint256[] memory) {
        return _createCats(_catType, LuckyCatState.Blind, _amount, _to);
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

    /**
     * @dev activate cat from blind state to active state
     */
    function activateCat(uint256 catId) public {
        require(ownerOf(catId) == msg.sender, "LuckyCatCore: not cat owner");
        require(
            LuckyCats[catId].state == LuckyCatState.Blind,
            "LuckyCatCore: cat has been activated or burned"
        );

        LuckyCats[catId].state = LuckyCatState.Active;
        LuckyCats[catId].birthTime = uint64(now);

        emit ActivateCat(msg.sender, catId);
    }

    /**
     * @dev burn cat from active state to burned state
     */
    function burnCat(uint256 catId) public {
        require(
            _isApprovedOrOwner(msg.sender, catId),
            "LuckyCatCore: not owner or approved"
        );
        require(
            LuckyCats[catId].state != LuckyCatState.Burned,
            "LuckyCatCore: cat has been burned"
        );
        LuckyCats[catId].state = LuckyCatState.Burned;

        _burn(catId);

        emit BurnCat(msg.sender, catId);
    }

    /* ========== INTERNAL FUNCTIONS ========== */

    function _createCats(
        uint256 _catType,
        LuckyCatState state,
        uint256 _amount,
        address _to
    ) internal returns (uint256[] memory) {
        require(_to != address(0), "LuckyCatCore: mint to address zero");
        require(types.contains(_catType), "LuckyCatCore: _catType not exist");

        uint256[] memory ids = new uint256[](_amount);

        for (uint256 i = 0; i < _amount; i++) {
            LuckyCat memory cat =
                LuckyCat({
                    _type: _catType,
                    birthTime: uint64(0),
                    MiningFactor: catMiningFactor[_catType],
                    state: state
                });
            LuckyCats.push(cat);

            uint256 tokenId = LuckyCats.length.sub(1);
            ids[i] = tokenId;
            _safeMint(_to, tokenId);
        }

        emit CreateCats(_catType, uint256(state), _to, ids);
        return ids;
    }
}
