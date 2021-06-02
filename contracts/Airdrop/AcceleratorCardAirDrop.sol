// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;

import "@openzeppelin/contracts/utils/EnumerableSet.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/proxy/Initializable.sol";
import "../AccessControl/ExternalAdminAccessControl.sol";
import "../interfaces/IAcceleratorCard.sol";

contract AcceleratorCardAirDrop is
    ExternalAdminAccessControl,
    Initializable,
    ReentrancyGuard,
    Pausable
{
    using EnumerableSet for EnumerableSet.AddressSet;

    IAcceleratorCard public accelerator;
    uint256 public factor;
    uint256 public period;

    uint256 public max; // the maximum number of participant

    EnumerableSet.AddressSet participants;

    event Claim(address user, uint256 card);

    function initialize(
        address _acceleratorCard,
        uint256 _factor,
        uint256 _period,
        uint256 _max
    ) public initializer {
        accelerator = IAcceleratorCard(_acceleratorCard);
        period = _period;
        factor = _factor;
        max = _max;
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(EXTERNAL_ADMIN_ROLE, msg.sender);
    }

    function participantAtIndex(uint256 index) public view returns (address) {
        return participants.at(index);
    }

    /**
     * @notice Participation quantity
     */
    function participantsLength() public view returns (uint256) {
        return participants.length();
    }

    /**
     * @notice check claimed status
     */
    function isClaimed(address user) public view returns (bool) {
        return participants.contains(user);
    }

    /**
     * @dev cliam a free Accelerator card
     */
    function claim() public whenNotPaused nonReentrant {
        require(
            participants.length() < max,
            "AcceleratorCardAirDrop: Has reached the maximum number of participant"
        );
        require(
            !participants.contains(msg.sender),
            "AcceleratorCardAirDrop: Has claimed"
        );

        uint256 card = accelerator.mint(msg.sender, factor, period);

        participants.add(msg.sender);

        emit Claim(msg.sender, card);
    }

    /**
     * @dev clear records
     */
    function clear() public onlyAdmin {
        uint256 len = participants.length();

        for (uint256 i = 0; i < len; i++) {
            participants.remove(participants.at(0));
        }
    }

    /**
     * @dev set accelerator card `period` ,`factor`
     */
    function setCardInfo(uint256 _factor, uint256 _period) public onlyAdmin {
        period = _period;
        factor = _factor;
    }

    /**
     * @dev set `accelerator card ` NFT address
     */
    function setAcceleratorCard(address _accelerator) public onlyAdmin {
        accelerator = IAcceleratorCard(_accelerator);
    }

    /**
     * @dev set `max`  the max number of participants
     */
    function setMax(uint256 _max) public onlyAdmin {
        max = _max;
    }

    function pause() public onlyAdmin {
        _pause();
    }

    function unpause() public onlyAdmin {
        _unpause();
    }
}
