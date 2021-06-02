// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/proxy/Initializable.sol";
import "../interfaces/ILccToken.sol";
import "../AccessControl/ExternalAdminAccessControl.sol";

contract MasterChef is
    ExternalAdminAccessControl,
    Initializable,
    ReentrancyGuard
{
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    struct UserInfo {
        uint256 amount; // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt.
    }

    struct PoolInfo {
        IERC20 lpToken; // Address of LP token contract.
        uint256 allocPoint; // How many allocation points assigned to this pool. LCCs to distribute per block.
        uint256 lastRewardBlock; // Last block number that LCCs distribution occurs.
        uint256 accLccPerShare; // Accumulated LCCs per share, times `SAFE_MULTIPLIER`. See below.
    }

    /// @notice The LCC TOKEN!
    ILccToken public lcc;

    /// @notice LCC tokens created per block.
    uint256 public lccPerBlock;

    /// @notice Info of each pool.
    PoolInfo[] public poolInfo;

    /// @notice Info of each user that stakes LP tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;

    /// @notice Total allocation poitns. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;

    /// @notice The block number when LCC mining starts.
    uint256 public startBlock;

    /// @notice reduce block point
    uint256 public blockPoint;

    /// @notice reward reduce period (one month)
    uint256 public reducePeriod;

    /// @notice halve rate max
    uint256 public constant max = 10000;

    /// @notice halve rete min
    uint256 public min;

    /// @notice lucky cat vault
    address public vault;

    /// @notice Dev address.
    address public devaddr;

    uint256 public constant SAFE_MULTIPLIER = 1e12;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(
        address indexed user,
        uint256 indexed pid,
        uint256 amount
    );

    function initialize(
        ILccToken _lcc,
        address _devaddr,
        address _vault,
        uint256 _lccPerBlock,
        uint256 _startBlock
    ) public initializer {
        lcc = _lcc;
        devaddr = _devaddr;
        vault = _vault;
        lccPerBlock = _lccPerBlock;
        startBlock = _startBlock;
        reducePeriod = 864000;
        blockPoint = _startBlock.add(reducePeriod);
        min = 9000;

        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(EXTERNAL_ADMIN_ROLE, msg.sender);
    }

    /**
     * @notice get pool length
     */
    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    /**
     * @dev Add a new lp to the pool. DO NOT add the same LP token more than once. Rewards will be messed up if you do.
     */
    function add(
        uint256 _allocPoint,
        IERC20 _lpToken,
        bool _withUpdate
    ) public onlyAdmin {
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardBlock =
            block.number > startBlock ? block.number : startBlock;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);

        poolInfo.push(
            PoolInfo({
                lpToken: _lpToken,
                allocPoint: _allocPoint,
                lastRewardBlock: lastRewardBlock,
                accLccPerShare: 0
            })
        );
    }

    /**
     * @dev Update the given pool's LCC allocation point.
     */
    function setAllocPoint(
        uint256 _pid,
        uint256 _allocPoint,
        bool _withUpdate
    ) public onlyAdmin {
        if (_withUpdate) {
            massUpdatePools();
        }
        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(
            _allocPoint
        );
        poolInfo[_pid].allocPoint = _allocPoint;
    }

    /**
     * @notice Return reward multiplier over the given _from to _to block.
     */
    function getMultiplier(uint256 _from, uint256 _to)
        public
        view
        returns (uint256)
    {
        require(_from <= _to, "from smaller than to");

        if (_to <= startBlock) {
            return 0;
        }

        if (_to <= blockPoint) {
            return _to.sub(_from).mul(SAFE_MULTIPLIER);
        }
        if (_from <= blockPoint && _to > blockPoint) {
            return
                blockPoint.sub(_from).mul(SAFE_MULTIPLIER).add(
                    _to.sub(blockPoint).mul(SAFE_MULTIPLIER).mul(min).div(max)
                );
        }
        if (_from > blockPoint) {
            return _to.sub(_from).mul(SAFE_MULTIPLIER).mul(min).div(max);
        }
        return 0;
    }

    /**
     * @notice View function to see pending LCCs on frontend.
     */
    function pendingLcc(uint256 _pid, address _user)
        external
        view
        returns (uint256)
    {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];

        uint256 accLccPerShare = pool.accLccPerShare;
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));

        if (block.number > pool.lastRewardBlock && lpSupply != 0) {
            uint256 multiplier =
                getMultiplier(pool.lastRewardBlock, block.number);
            uint256 lccReward =
                multiplier
                    .mul(lccPerBlock)
                    .mul(pool.allocPoint)
                    .div(totalAllocPoint)
                    .div(SAFE_MULTIPLIER);

            accLccPerShare = accLccPerShare.add(
                lccReward.mul(SAFE_MULTIPLIER).div(lpSupply)
            );
        }
        return
            user.amount.mul(accLccPerShare).div(SAFE_MULTIPLIER).sub(
                user.rewardDebt
            );
    }

    /**
     * @dev Update reward vairables for all pools. Be careful of gas spending!
     */
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    /**
     * @dev Update reward variables of the given pool to be up-to-date.
     */
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];

        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (lpSupply == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }

        uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
        uint256 lccReward =
            multiplier
                .mul(lccPerBlock)
                .mul(pool.allocPoint)
                .div(totalAllocPoint)
                .div(SAFE_MULTIPLIER);

        _mintLcc(lccReward);

        pool.accLccPerShare = pool.accLccPerShare.add(
            lccReward.mul(SAFE_MULTIPLIER).div(lpSupply)
        );
        pool.lastRewardBlock = block.number;

        if (block.number > blockPoint) {
            lccPerBlock = lccPerBlock.mul(min).div(max);
            blockPoint = blockPoint.add(reducePeriod);
        }
    }

    /**
     * @dev Deposit LP tokens to MasterChef for LCC allocation.
     */
    function deposit(uint256 _pid, uint256 _amount) public nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        updatePool(_pid);

        if (user.amount > 0) {
            uint256 pending =
                user.amount.mul(pool.accLccPerShare).div(SAFE_MULTIPLIER).sub(
                    user.rewardDebt
                );
            safeLccTransfer(msg.sender, pending);
        }
        pool.lpToken.safeTransferFrom(
            address(msg.sender),
            address(this),
            _amount
        );
        user.amount = user.amount.add(_amount);
        user.rewardDebt = user.amount.mul(pool.accLccPerShare).div(
            SAFE_MULTIPLIER
        );

        emit Deposit(msg.sender, _pid, _amount);
    }

    /**
     * @dev Withdraw LP tokens from MasterChef.
     */
    function withdraw(uint256 _pid, uint256 _amount) public nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");

        updatePool(_pid);

        uint256 pending =
            user.amount.mul(pool.accLccPerShare).div(SAFE_MULTIPLIER).sub(
                user.rewardDebt
            );
        safeLccTransfer(msg.sender, pending);

        user.amount = user.amount.sub(_amount);
        user.rewardDebt = user.amount.mul(pool.accLccPerShare).div(
            SAFE_MULTIPLIER
        );
        pool.lpToken.safeTransfer(address(msg.sender), _amount);

        emit Withdraw(msg.sender, _pid, _amount);
    }

    /**
     * @dev Withdraw without caring about rewards. EMERGENCY ONLY.
     */
    function emergencyWithdraw(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        pool.lpToken.safeTransfer(address(msg.sender), user.amount);
        user.amount = 0;
        user.rewardDebt = 0;

        emit EmergencyWithdraw(msg.sender, _pid, user.amount);
    }

    /**
     * @dev mint lcc to user| devaddr| vault
     */
    function _mintLcc(uint256 _reward) internal {
        lcc.mint(devaddr, _reward.div(10));
        lcc.mint(vault, _reward.div(10));
        lcc.mint(address(this), _reward);
    }

    /**
     * @dev Safe lcc transfer function, just in case if rounding error causes pool to not have enough LCCs.
     */
    function safeLccTransfer(address _to, uint256 _amount) internal {
        if (_amount > 0) {
            uint256 lccBal = lcc.balanceOf(address(this));
            if (_amount > lccBal) {
                lcc.transfer(_to, lccBal);
            } else {
                lcc.transfer(_to, _amount);
            }
        }
    }

    /**
     * @dev set min
     */
    function setMin(uint256 _min) public onlyAdmin {
        require(_min > 0, "min > 0");
        min = _min;
    }

    /**
     * @dev Set the number of lcc produced by each block
     */
    function setLccPerBlock(uint256 _newPerBlock) public onlyAdmin {
        massUpdatePools();
        lccPerBlock = _newPerBlock;
    }

    /**
     * @dev Update dev address by the previous dev.
     */
    function setDevAddr(address _devaddr) public {
        require(msg.sender == devaddr, "not previous dev addr");
        devaddr = _devaddr;
    }

    /**
     * @dev set `vault` address
     */
    function setVault(address _vault) public onlyAdmin {
        vault = _vault;
    }
}
