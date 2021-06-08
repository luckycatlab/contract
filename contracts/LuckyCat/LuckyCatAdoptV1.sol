// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721Holder.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/proxy/Initializable.sol";
import "../interfaces/IAcceleratorCard.sol";
import "../interfaces/ILuckyCat.sol";
import "../interfaces/IRandom.sol";
import "../AccessControl/ExternalAdminAccessControl.sol";

contract LuckyCatAdoptBase is ExternalAdminAccessControl {
    using EnumerableSet for EnumerableSet.UintSet;
    using SafeMath for uint256;

    struct SellInfo {
        uint256 seriesCatCounts;
        EnumerableSet.UintSet types;
        mapping(uint256 => uint256) typeCatCounts;
        mapping(address => EnumerableSet.UintSet) AdoptRecords; // user's Purchase History
        address feeToken;
        uint256 fee;
    }

    /// @dev from series to it's sellinfo
    mapping(uint256 => SellInfo) sellInfos;

    /// @notice lucky cat NFT
    ILuckyCat public luckyCat;

    IRandom public random;

    uint256 public constant max = 10000;

    uint256 public constant SAFE_MULTIPLIER = 1e18;

    /* ========== VIEWS ========== */

    function getSellInfo(uint256 series)
        public
        view
        returns (
            uint256,
            uint256,
            address,
            uint256
        )
    {
        SellInfo storage info = sellInfos[series];

        return (
            info.seriesCatCounts,
            getRemainingCats(series),
            info.feeToken,
            info.fee
        );
    }

    function getRemainingCats(uint256 series) public view returns (uint256) {
        SellInfo storage info = sellInfos[series];
        uint256 remaining;
        for (uint256 i = 0; i < info.types.length(); i++) {
            remaining = remaining.add(info.typeCatCounts[info.types.at(i)]);
        }
        return remaining;
    }

    /* ========== ADMIN FUNCTIONS ========== */

    /**
     * @dev set `series` cats for sale
     */
    function setSeriesCatsData(
        uint256 series,
        uint256[] memory catTypes,
        uint256[] memory catCounts
    ) public onlyAdmin {
        SellInfo storage info = sellInfos[series];

        require(catTypes.length == catCounts.length, "length error");

        for (uint256 i = 0; i < catTypes.length; i++) {
            info.types.add(catTypes[i]);
            info.typeCatCounts[catTypes[i]] = info.typeCatCounts[catTypes[i]]
                .add(catCounts[i]);
            info.seriesCatCounts = info.seriesCatCounts.add(catCounts[i]);
        }
    }

    /**
     * @dev set `series` adopt fee and token
     */
    function setSeriesFeeAndToken(
        uint256 series,
        uint256 fee,
        address feeToken
    ) public onlyAdmin {
        require(series != 0, "LuckyCatAdoptBase: not series 0");
        require(
            feeToken != address(0),
            "LuckyCatAdoptBase: feeToken zero address"
        );
        SellInfo storage info = sellInfos[series];
        info.fee = fee;
        info.feeToken = feeToken;
    }

    /**
     * @dev set `random` address
     */
    function setRandom(address _random) public onlyAdmin {
        random = IRandom(_random);
    }

    /**
     * @dev set `luckyCat` address
     */
    function setLuckyCat(address _luckyCat) public onlyAdmin {
        luckyCat = ILuckyCat(_luckyCat);
    }
}

contract LuckyCatAdoptV1 is
    LuckyCatAdoptBase,
    Initializable,
    ERC721Holder,
    ReentrancyGuard
{
    using EnumerableSet for EnumerableSet.UintSet;
    using SafeMath for uint256;

    /// @notice user's invite code
    mapping(address => bytes3) public userInviteCodes;

    /// @notice invite code's user
    mapping(bytes3 => address) public inviteCodeUsers;

    /// @notice user's invite counts
    mapping(address => uint256) public inviteCounts;

    /// @notice Accelerator card
    IAcceleratorCard public accelerator;

    /// @notice discount for series 0
    uint256 public discount;

    uint256 public inviteCountForAccelerator;

    /// @notice 7 days
    uint256 public acceleratorPeriod;

    /* ========== EVENTS ========== */

    event Buy(uint256 series, address user, uint256 catId);

    receive() payable external {}

    fallback() payable external {}

    /* ========== INITIALIZE ========== */

    function initialize(
        address _luckyCat,
        address _acceleratorCard,
        address _random
    ) public initializer {
        require(
            _acceleratorCard != address(0) &&
                _luckyCat != address(0) &&
                _random != address(0),
            "LuckyCatAdoptV1: address zero"
        );
        luckyCat = ILuckyCat(_luckyCat);
        accelerator = IAcceleratorCard(_acceleratorCard);
        random = IRandom(_random);
        discount = 9500;
        inviteCountForAccelerator = 10;
        acceleratorPeriod = 201600;

        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(EXTERNAL_ADMIN_ROLE, msg.sender);
    }

    /* ========== VIEWS ========== */

    /**
     * @notice get series 0 current cost of a cat
     * 0 ~ 10000        price = 3* sold / 10000 + 1
     * 10000 ~ 20000    price = (sold - 5000)^2 / 6250000 + 2.5
     */
    function getSeries0TotalCost(uint256 amount) public view returns (uint256) {
        SellInfo storage info = sellInfos[0];
        uint256 remaining = getRemainingCats(0);

        require(
            remaining >= amount,
            "LuckyCatAdoptV1: Purchase quantity exceed remaining"
        );
        uint256 totalCost;

        uint256 half = info.seriesCatCounts.div(2);
        uint256 sold = info.seriesCatCounts.sub(remaining);

        for (uint256 i = 0; i < amount; i++) {
            if (sold <= half) {
                totalCost = totalCost.add(
                    sold.mul(3).add(10000).mul(SAFE_MULTIPLIER).div(10000)
                );
            } else {
                totalCost = totalCost.add(
                    sold
                        .sub(half)
                        .mul(sold.sub(half))
                        .add(15625000)
                        .mul(SAFE_MULTIPLIER)
                        .div(6250000)
                );
            }
            sold = sold.add(1);
        }

        return totalCost;
    }

    /* ========== PUBLIC FUNCTIONS ========== */

    /**
     * @dev buy cat series 0
     */
    function buySeries0Cats(uint256 amount, bytes3 inviteCode)
        public
        payable
        nonReentrant
    {
        SellInfo storage info = sellInfos[0];
        uint256 remaining = getRemainingCats(0);

        require(remaining > 0, "LuckyCatAdoptV1: cats sold out");

        uint256 cost = getSeries0TotalCost(amount);

        address inviter = inviteCodeUsers[inviteCode];
        address invitee = msg.sender;

        if (inviter != address(0) && inviter != invitee) {
            cost = cost.mul(discount).div(max);
        }
        require(msg.value >= cost, "LuckyCatAdoptV1: cost error");
        uint256[] memory ids;

        for (uint256 i = 0; i < amount; i++) {
            uint256 catType = getRandomCatType();

            ids = luckyCat.createBlindCats(catType, 1, address(this));
            uint256 catId = ids[0];

            luckyCat.activateCat(catId);
            luckyCat.safeTransferFrom(address(this), invitee, catId);

            info.AdoptRecords[invitee].add(catId);
            info.typeCatCounts[catType] = info.typeCatCounts[catType].sub(1);

            if (inviter != address(0) && inviter != invitee) {
                inviteCounts[inviter] = inviteCounts[inviter].add(1);
                if (inviteCounts[inviter].mod(inviteCountForAccelerator) == 0) {
                    uint256 factor =
                        generateAcceleratorFactor(catId, inviteCode);
                    accelerator.mint(inviter, factor, acceleratorPeriod);
                }
            }

            emit Buy(0, invitee, catId);
        }

        if (userInviteCodes[invitee] == bytes3("") && amount > 0) {
            bytes3 _inviteCode = generateInviteCode(invitee);
            userInviteCodes[invitee] = _inviteCode;
            inviteCodeUsers[_inviteCode] = invitee;
        }

        if (msg.value > cost) {
            msg.sender.transfer(msg.value.sub(cost));
        }
    }

    /* ========== INTERNAL FUNCTIONS ========== */

    /**
     * @dev generate user's invite code
     * inviteCode = bytes3(keccak256(address + first cat's id))
     * @param _user user address
     */
    function generateInviteCode(address _user) internal view returns (bytes3) {
        SellInfo storage info = sellInfos[0];

        uint256 firstId = info.AdoptRecords[_user].at(0);
        return bytes3(keccak256(abi.encodePacked(_user, firstId)));
    }

    /**
     * @dev generate accelerator card's factor
     */
    function generateAcceleratorFactor(uint256 id, bytes3 inviteCode)
        internal
        pure
        returns (uint256)
    {
        bytes32 factorHash = keccak256(abi.encodePacked(id, inviteCode));
        return uint256(factorHash).mod(10).add(1).mul(100);
    }

    /**
     * @dev get a random cat type
     */
    function getRandomCatType() internal view returns (uint256) {
        uint256 remaing = getRemainingCats(0);

        uint256 randomUint = random.getRandom().mod(remaing).add(1);
        SellInfo storage info = sellInfos[0];
        uint256 count;
        uint256 catType;

        for (uint256 i = 0; i < info.types.length(); i++) {
            catType = info.types.at(i);
            count = count.add(info.typeCatCounts[catType]);
            if (count >= randomUint) {
                break;
            }
        }

        return catType;
    }

    /* ========== ADMIN FUNCTIONS ========== */

    /**
     * @dev set `inviteCountForAc`
     */
    function setInviteCountForAccelerator(uint256 count) public onlyAdmin {
        inviteCountForAccelerator = count;
    }

    /**
     * @dev set `ACPeriod`
     */
    function setacceleratorPeriod(uint256 period) public onlyAdmin {
        acceleratorPeriod = period;
    }

    /**
     * @dev set `discount` for series 0
     */
    function setDiscount(uint256 _discount) public onlyAdmin {
        discount = _discount;
    }

    /**
     * @dev set `accelerator` address
     */
    function setAcceleratorCard(address _card) public onlyAdmin {
        accelerator = IAcceleratorCard(_card);
    }

    /**
     * @dev withdraw balance
     */
    function withdraw(address payable _to) public onlyOwner {
        _to.transfer(address(this).balance);
    }
}
