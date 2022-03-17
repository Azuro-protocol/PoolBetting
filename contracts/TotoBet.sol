// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.3;

import "./interface/ITotoBet.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC1155/ERC1155Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract TotoBet is OwnableUpgradeable, ERC1155Upgradeable, ITotoBet {
    mapping(address => mapping(uint256 => uint256)) private _tokenIDs; // core -> coreConditionID -> tokenID
    uint256 private _lastTokenID;

    mapping(address => bool) cores;

    modifier onlyCore() {
        require(cores[msg.sender] == true, "BetToken: Only core");
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

    function getTokenID(
        address core_,
        uint256 coreConditionID_,
        uint8 outcomeIndex_
    ) public view override returns (uint256) {
        uint256 tokenID = _tokenIDs[core_][coreConditionID_];
        require(tokenID != 0, "BetToken: Token does not exist");

        return tokenID + outcomeIndex_;
    }

    function balanceOf(address account, uint256 conditionOutcomeID_)
        public
        view
        override(ERC1155Upgradeable, ITotoBet)
        returns (uint256)
    {
        return balanceOf(account, conditionOutcomeID_);
    }

    function mint(
        address account_,
        uint256 coreConditionID_,
        uint8 outcomeIndex_,
        uint128 amount_
    ) external override onlyCore returns (uint256) {
        uint256 tokenID = _tokenIDs[msg.sender][coreConditionID_];
        if (tokenID == 0) {
            tokenID = _lastTokenID + 1;
            _tokenIDs[msg.sender][coreConditionID_] = tokenID;
            _lastTokenID += 2;
        }
        tokenID += outcomeIndex_;

        super._mint(account_, tokenID, amount_, "");

        return tokenID;
    }

    function burn(
        address account_,
        uint256 coreConditionID_,
        uint8 outcomeIndex_,
        uint256 amount_
    ) external override onlyCore {
        super._burn(
            account_,
            getTokenID(msg.sender, coreConditionID_, outcomeIndex_),
            amount_
        );
    }
}
