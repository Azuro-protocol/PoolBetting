// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.3;

import "./interface/IBetToken.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC1155/ERC1155Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract BetToken is OwnableUpgradeable, ERC1155Upgradeable, IBetToken {
    uint256 public lastConditionID;
    mapping(address => bool) cores;
    mapping(address => mapping(uint256 => uint256)) private _conditionIDs; // core -> coreCondition -> condition -> conditionOutcomeID

    modifier onlyCore() {
        require(cores[msg.sender] == true, "BetToken: OnlyCore");
        _;
    }

    function initialize() public virtual initializer {
        __Ownable_init();
        __ERC1155_init("TotoBetting");
    }

    function updateCore(address core_, bool active_)
        external
        override
        onlyOwner
    {
        cores[core_] = active_;
    }

    function getConditionOutcomeID(
        address core_,
        uint256 coreConditionID_,
        uint8 outcomeIndex_
    ) public view override returns (uint256) {
        return _conditionIDs[core_][coreConditionID_] + outcomeIndex_;
    }

    function balanceOfToken(address account, uint256 conditionOutcomeID_)
        public
        view
        override
        returns (uint256)
    {
        return super.balanceOf(account, conditionOutcomeID_);
    }

    function mint(
        address account_,
        uint256 coreConditionID_,
        uint8 outcomeIndex_,
        uint128 amount_
    ) external override onlyCore returns (uint256) {
        uint256 conditionID = getConditionOutcomeID(
            msg.sender,
            coreConditionID_,
            0
        );
        if (conditionID == 0) {
            conditionID = lastConditionID + 1;
            _conditionIDs[msg.sender][coreConditionID_] = conditionID;
            lastConditionID += 2;
        }
        super._mint(account_, conditionID + outcomeIndex_, amount_, "");

        return conditionID + outcomeIndex_;
    }

    function burn(
        address account_,
        uint256 coreConditionID_,
        uint8 outcomeIndex_,
        uint256 amount_
    ) external override onlyCore {
        super._burn(
            account_,
            getConditionOutcomeID(msg.sender, coreConditionID_, outcomeIndex_),
            amount_
        );
    }
}
