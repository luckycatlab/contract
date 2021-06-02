// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;

import "@openzeppelin/contracts/token/ERC721/ERC721Holder.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/utils/EnumerableSet.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/proxy/Initializable.sol";
import "../AccessControl/ExternalAdminAccessControl.sol";
import "../interfaces/ILuckyCat.sol";
import "../interfaces/IAcceleratorCard.sol";
import "../interfaces/ILccToken.sol";

contract LuckyCatBase is ExternalAdminAccessControl {
    struct UserInfo {
        EnumerableSet.UintSet cats;
        uint256 updatedBlock;
    }

    struct CardInfo {
        uint256 id;
        uint256 updatedBlock;
    }

    struct PoolInfo {
        uint256 startBlock; // The block number when LCC mining starts.
        uint256 updatedBlock;
        uint256 lccPerBlock;
        uint256 blockPoint;
        uint256 reducePeriod; // reward reduce period (one month)
    }

    /* ========== VARIABLES ========== */

    ILuckyCat public luckyCat;

    IAcceleratorCard public accelerator;

    ILccToken public lcc;

    PoolInfo public pool;

    mapping(address => UserInfo) userInfo;

    mapping(uint256 => CardInfo) public catAcceleratorCard;

    mapping(uint256 => uint256) public catTypeCounts;

    uint256 public miningFactorTotal;

    /// @notice halve rate max
    uint256 public constant max = 10000;

    /// @notice halve rete min
    uint256 public min;

    uint256 public constant SAFE_MULTIPLIER = 1e12;

    /* ========== ADMIN FUNCTIONS ========== */

    /**
     * @dev set `min`
     */
    function setMin(uint256 _min) public onlyAdmin {
        min = _min;
    }

    /**
     * @dev set `pool.reducePeriod`
     */
    function setReducePeriod(uint256 _reducePeriod) public onlyAdmin {
        pool.reducePeriod = _reducePeriod;
    }

    /**
     * @dev Set the number of some types of cats
     */
    function setCatTypeCounts(
        uint256[] memory catTypes,
        uint256[] memory catCounts
    ) public onlyAdmin {
        require(catTypes.length == catCounts.length, "length error");

        for (uint256 i = 0; i < catTypes.length; i++) {
            catTypeCounts[catTypes[i]] = catCounts[i];
        }
    }

    /**
     * @dev set `accelerator` address
     */
    function setAcceleratorCard(address _card) public onlyAdmin {
        accelerator = IAcceleratorCard(_card);
    }
}

contract LuckyCatFarm is LuckyCatBase, ERC721Holder, Initializable {
    using EnumerableSet for EnumerableSet.UintSet;
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    /* ========== EVENTS ========== */

    event StakeCats(address user, uint256[] cats);
    event StakeAcceleratorCard(uint256 catId, uint256 cardId);
    event WithdrawCats(address user, uint256[] cats);
    event EmergencyWithdraw(address user, uint256[] cats);

    /* ========== CONSTRUCTOR ========== */

    function initialize(
        address _lcc,
        address _luckyCat,
        address _accelerator,
        uint256 _startBlock,
        uint256 _lccPerBlock
    ) public initializer {
        lcc = ILccToken(_lcc);
        luckyCat = ILuckyCat(_luckyCat);
        accelerator = IAcceleratorCard(_accelerator);

        pool.startBlock = _startBlock;
        pool.reducePeriod = 864000;
        pool.blockPoint = _startBlock.add(pool.reducePeriod);
        pool.lccPerBlock = _lccPerBlock;

        miningFactorTotal = 10000;
        min = 9000;

        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(EXTERNAL_ADMIN_ROLE, msg.sender);
    }

    /* ========== VIEWS ========== */

    /**
     * @notice get user's staked cats
     */
    function getUserInfo(address _user)
        public
        view
        returns (uint256[] memory, uint256)
    {
        UserInfo storage user = userInfo[_user];
        uint256 len = user.cats.length();
        uint256[] memory cats = new uint256[](len);

        for (uint256 i = 0; i < len; i++) {
            cats[i] = user.cats.at(i);
        }
        return (cats, user.updatedBlock);
    }

    /**
     * @notice get user's all cats NFT mining reward
     */
    function pengingLccAll(address _user) public view returns (uint256) {
        UserInfo storage user = userInfo[_user];

        uint256 pending;

        for (uint256 i = 0; i < user.cats.length(); i++) {
            pending = pending.add(pendingLcc(_user, user.cats.at(i)));
        }

        return pending;
    }

    /**
     * @notice get one cat NFT mining reward
     */
    function pendingLcc(address _user, uint256 cat)
        public
        view
        returns (uint256)
    {
        UserInfo storage user = userInfo[_user];

        if (!user.cats.contains(cat)) {
            return 0;
        }

        return
            earnedLcc(_user, cat).add(earnedLccExtra(_user, cat)).div(
                SAFE_MULTIPLIER
            );
    }

    /**
     * @notice per `_type` cat per block reward
     */
    function lccPerCatBlock(uint256 _type) public view returns (uint256) {
        uint256 miningFactor = luckyCat.catMiningFactor(_type);

        if (miningFactor != 0 && catTypeCounts[_type] != 0) {
            return
                pool.lccPerBlock.mul(miningFactor).div(miningFactorTotal).div(
                    catTypeCounts[_type]
                );
        }
        return 0;
    }

    /* ========== PUBLIC FUNCTIONS ========== */

    function updatePool() public {
        uint256 poolReward =
            getBlockDelta(pool.updatedBlock).mul(pool.lccPerBlock).div(
                SAFE_MULTIPLIER
            );
        if (poolReward > 0) {
            lcc.mint(address(this), poolReward);
        }
        pool.updatedBlock = block.number;
    }

    /**
     * @dev harvest NFT mining reward
     */
    function earn() public {
        updatePool();

        UserInfo storage user = userInfo[msg.sender];
        uint256 _earnedLcc;
        uint256 _earnedLccExtra;

        for (uint256 i = 0; i < user.cats.length(); i++) {
            _earnedLcc = _earnedLcc.add(earnedLcc(msg.sender, user.cats.at(i)));
            _earnedLccExtra = _earnedLccExtra.add(
                earnedLccExtra(msg.sender, user.cats.at(i))
            );
        }

        safeLccTransfer(
            msg.sender,
            _earnedLcc.add(_earnedLccExtra).div(SAFE_MULTIPLIER)
        );
        user.updatedBlock = block.number;

        updateUserAcceleratorCards(msg.sender);

        if (block.number >= pool.blockPoint) {
            pool.blockPoint = pool.blockPoint.add(pool.reducePeriod);
            pool.lccPerBlock = pool.lccPerBlock.mul(min).div(max);
        }
    }

    /**
     * @dev stake cat NFTs for mining and harvest reward
     */
    function stakeLuckyCats(uint256[] memory ids) public {
        earn();

        UserInfo storage user = userInfo[msg.sender];
        uint256 len = ids.length;

        for (uint256 i = 0; i < len; i++) {
            (, , , uint256 state) = luckyCat.getLuckyCat(ids[i]);
            require(state == 1, "LuckyCatFarm: cat is not active");
            luckyCat.safeTransferFrom(msg.sender, address(this), ids[i]);
            user.cats.add(ids[i]);
            updateCatAcceleratorCard(ids[i]);
        }
        emit StakeCats(msg.sender, ids);
    }

    /**
     * @dev stake accelerator for cat mining and harvest reward
     */
    function stakeAcceleratorCard(uint256 catId, uint256 cardId) public {
        earn();

        UserInfo storage user = userInfo[msg.sender];
        require(user.cats.contains(catId), "LuckyCatFarm: cat is not staked");

        CardInfo storage card = catAcceleratorCard[catId];
        require(card.id == 0, "LuckyCatFarm: already speed up");

        accelerator.safeTransferFrom(msg.sender, address(this), cardId);
        accelerator.activateCard(cardId, block.number);
        card.id = cardId;
        card.updatedBlock = block.number;

        emit StakeAcceleratorCard(catId, cardId);
    }

    /**
     * @dev withdraw cat NFTs from mining and harvest reward
     */
    function withdraw(uint256[] memory ids) public {
        earn();

        UserInfo storage user = userInfo[msg.sender];
        for (uint256 i = 0; i < ids.length; i++) {
            require(
                user.cats.contains(ids[i]),
                "LuckyCatFarm: cat is not staked"
            );
            luckyCat.safeTransferFrom(address(this), msg.sender, ids[i]);
            user.cats.remove(ids[i]);
        }

        emit WithdrawCats(msg.sender, ids);
    }

    /**
     * @dev only withdraw cat NFTs from mining
     */
    function emergencyWithdraw() public {
        UserInfo storage user = userInfo[msg.sender];
        (uint256[] memory ids, ) = getUserInfo(msg.sender);

        for (uint256 i = 0; i < ids.length; i++) {
            luckyCat.safeTransferFrom(address(this), msg.sender, ids[i]);
            user.cats.remove(ids[i]);
        }
        user.updatedBlock = 0;

        emit EmergencyWithdraw(msg.sender, ids);
    }

    /* ========== INTERNAL FUNCTIONS ========== */

    function lccPerCatBlockExtra(uint256 _type, uint256 _factor)
        internal
        view
        returns (uint256)
    {
        uint256 _lccPerCatBlock = lccPerCatBlock(_type);
        return
            _lccPerCatBlock.mul(_factor).div(
                accelerator.AcceleratorFactorMax()
            );
    }

    /**
     * @dev get accelerator card accelerate blocks
     */
    function getCardAccelerateBlocks(
        uint256 _startBlock,
        uint256 _endBlock,
        uint256 _updatedBlock
    ) internal view returns (uint256) {
        _startBlock = _updatedBlock > _startBlock ? _updatedBlock : _startBlock;
        _startBlock = _startBlock > pool.startBlock
            ? _startBlock
            : pool.startBlock;

        if (block.number < _startBlock || _endBlock < _startBlock) {
            return 0;
        }
        uint256 blockPoint = pool.blockPoint;

        if (_startBlock <= block.number && block.number < _endBlock) {
            if (blockPoint < _startBlock) {
                return
                    block
                        .number
                        .sub(_startBlock)
                        .mul(SAFE_MULTIPLIER)
                        .mul(min)
                        .div(max);
            }
            if (_startBlock <= blockPoint && blockPoint < block.number) {
                return
                    blockPoint.sub(_startBlock).mul(SAFE_MULTIPLIER).add(
                        block
                            .number
                            .sub(blockPoint)
                            .mul(SAFE_MULTIPLIER)
                            .mul(min)
                            .div(max)
                    );
            }
            return block.number.sub(_startBlock).mul(SAFE_MULTIPLIER);
        }
        if (block.number >= _endBlock) {
            if (blockPoint < _startBlock) {
                return
                    _endBlock
                        .sub(_startBlock)
                        .mul(SAFE_MULTIPLIER)
                        .mul(min)
                        .div(max);
            }
            if (_startBlock <= blockPoint && blockPoint < block.number) {
                return
                    blockPoint.sub(_startBlock).mul(SAFE_MULTIPLIER).add(
                        _endBlock
                            .sub(blockPoint)
                            .mul(SAFE_MULTIPLIER)
                            .mul(min)
                            .div(max)
                    );
            }
            return _endBlock.sub(_startBlock).mul(SAFE_MULTIPLIER);
        }
    }

    /**
     * @dev get block delta from since to now
     */
    function getBlockDelta(uint256 since) internal view returns (uint256) {
        since = since > pool.startBlock ? since : pool.startBlock;

        if (since > block.number) {
            return 0;
        }

        uint256 blockPoint = pool.blockPoint;

        if (block.number < blockPoint) {
            return block.number.sub(since).mul(SAFE_MULTIPLIER);
        }
        if (since < blockPoint && block.number >= blockPoint) {
            return
                blockPoint.sub(since).mul(SAFE_MULTIPLIER).add(
                    block
                        .number
                        .sub(blockPoint)
                        .mul(SAFE_MULTIPLIER)
                        .mul(min)
                        .div(max)
                );
        }
        if (since >= blockPoint) {
            return since.sub(blockPoint).mul(SAFE_MULTIPLIER).mul(min).div(max);
        }
    }

    /**
     * @dev The reward of NFT mining
     */
    function earnedLcc(address _user, uint256 cat)
        internal
        view
        returns (uint256)
    {
        UserInfo storage user = userInfo[_user];

        if (user.updatedBlock == 0 || user.cats.length() == 0) {
            return 0;
        }

        uint256 blockDelta = getBlockDelta(user.updatedBlock);

        (uint256 _type, , , ) = luckyCat.getLuckyCat(cat);
        uint256 per = lccPerCatBlock(_type);
        uint256 reward = blockDelta.mul(per);

        return reward;
    }

    /**
     * @dev The extra reward of accelerator cards
     */
    function earnedLccExtra(address _user, uint256 cat)
        internal
        view
        returns (uint256)
    {
        UserInfo storage user = userInfo[_user];

        if (user.updatedBlock == 0 || user.cats.length() == 0) {
            return 0;
        }

        (uint256 _type, , , ) = luckyCat.getLuckyCat(cat);
        uint256 reward;
        CardInfo storage card = catAcceleratorCard[cat];
        if (card.id != 0) {
            (uint256 _factor, uint256 _startBlock, uint256 _period) =
                accelerator.cards(card.id);

            uint256 extraPer = lccPerCatBlockExtra(_type, _factor);
            reward = reward.add(
                extraPer.mul(
                    getCardAccelerateBlocks(
                        _startBlock,
                        _startBlock.add(_period),
                        card.updatedBlock
                    )
                )
            );
        }

        return reward;
    }

    /**
     * @dev update user's all accelerators state and burn while becoming invalid
     */
    function updateUserAcceleratorCards(address _user) internal {
        UserInfo storage user = userInfo[_user];

        for (uint256 i = 0; i < user.cats.length(); i++) {
            updateCatAcceleratorCard(user.cats.at(i));
        }
    }

    /**
     * @dev update accelerator card state and burn while becoming invalid
     */
    function updateCatAcceleratorCard(uint256 catId) internal {
        CardInfo storage card = catAcceleratorCard[catId];

        if (card.id != 0) {
            (, uint256 _startBlock, uint256 _period) =
                accelerator.cards(card.id);

            if (block.number >= _startBlock.add(_period)) {
                accelerator.burn(card.id);
                delete catAcceleratorCard[catId];
            } else {
                card.updatedBlock = block.number;
            }
        }
    }

    function safeLccTransfer(address to, uint256 amount) internal {
        uint256 bal = lcc.balanceOf(address(this));
        if (bal < amount) {
            amount = bal;
        }
        if (amount > 0) {
            IERC20(lcc).safeTransfer(to, amount);
        }
    }
}
