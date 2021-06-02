// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721Holder.sol";
import "@openzeppelin/contracts/proxy/Initializable.sol";
import "../AccessControl/ExternalAdminAccessControl.sol";
import "../interfaces/ILuckyCat.sol";

contract LuckyCatAirDrop is
    ERC721Holder,
    ExternalAdminAccessControl,
    Initializable
{
    using EnumerableSet for EnumerableSet.AddressSet;
    using SafeMath for uint256;

    /* ========== VARIABLES ========== */
    ILuckyCat public luckyCat;
    uint256 public airdropCatType;
    mapping(address => uint256) claimWhitelist;
    EnumerableSet.AddressSet _whitelistKeys;
    uint256 public endTimestamp;

    /* ========== EVENTS ========== */

    event Registered(address token_, address add_, uint256 amount_);
    event Claimed(address token_, address add_, uint256 amount_);

    /* ========== CONSTRUCTOR ========== */

    function initialize(
        address _luckyCat,
        uint256 _airdropCatType,
        uint256 _endTimestamp
    ) public initializer {
        luckyCat = ILuckyCat(_luckyCat);
        endTimestamp = _endTimestamp;
        airdropCatType = _airdropCatType;
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(EXTERNAL_ADMIN_ROLE, msg.sender);
    }

    /* ========== VIEWS ========== */

    /**
     * @notice get user claim airDropToken_ amount
     */
    function getClaimAmount(address user_) public view returns (uint256) {
        return claimWhitelist[user_];
    }

    /**
     * @notice the remaining sum claimable amount
     */
    function sumClaimableAmount() public view returns (uint256 sum) {
        uint256 length = _whitelistKeys.length();
        for (uint256 i = 0; i < length; i++) {
            sum = sum.add(claimWhitelist[_whitelistKeys.at(i)]);
        }
    }

    /**
     * @notice the remaining claimable address
     */
    function whitelistLength() public view returns (uint256) {
        return _whitelistKeys.length();
    }

    /* ========== PUBLIC FUNCTIONS ========== */

    function claim() public {
        require(block.timestamp <= endTimestamp, "AirDrop: airdrop over");
        uint256 amount = claimWhitelist[msg.sender];

        if (amount > 0) {
            uint256[] memory tokenIds =
                luckyCat.createBlindCats(airdropCatType, amount, address(this));

            for (uint256 i = 0; i < tokenIds.length; i++) {
                luckyCat.activateCat(tokenIds[i]);
                luckyCat.safeTransferFrom(
                    address(this),
                    _msgSender(),
                    tokenIds[i]
                );
            }

            delete claimWhitelist[msg.sender];
            _whitelistKeys.remove(msg.sender);

            emit Claimed(address(luckyCat), msg.sender, amount);
        }
    }

    /* ========== ADMIN FUNCTIONS ========== */

    /**
     * @dev set Airdrop end timestamp
     */
    function setEndTimestamp(uint256 endTimestamp_) public onlyAdmin {
        endTimestamp = endTimestamp_;
    }

    /**
     * @dev set airdropCat's type
     */
    function setAirdropCatType(uint256 _airdropCatType) public onlyAdmin {
        airdropCatType = _airdropCatType;
    }

    /**
     * @dev set whitelist, including candidates, values
     */
    function setupWhitelist(address[] calldata candidates_, uint256 amount)
        public
        onlyAdmin
        returns (bool)
    {
        require(candidates_.length > 0, "The length is 0");

        for (uint256 i = 0; i < candidates_.length; i++) {
            require(candidates_[i] != address(0), "address zero!!!");

            claimWhitelist[candidates_[i]] = amount;
            _whitelistKeys.add(candidates_[i]);

            emit Registered(address(luckyCat), candidates_[i], amount);
        }

        return true;
    }

    /**
     * @dev clean the whitelist of token
     */
    function cleanWhitelist() public onlyAdmin returns (bool) {
        uint256 length = _whitelistKeys.length();
        for (uint256 i = 0; i < length; i++) {
            address key = _whitelistKeys.at(0);

            delete claimWhitelist[key];
            _whitelistKeys.remove(key);
        }

        require(_whitelistKeys.length() == 0);

        return true;
    }
}
