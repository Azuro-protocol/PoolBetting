// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.3;

import "./interface/ITotoBet.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC1155/ERC1155Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

/// @title Azuro Totalizator bet token contract
contract TotoBet is OwnableUpgradeable, ERC1155Upgradeable, ITotoBet {
    mapping(address => mapping(uint256 => uint256)) private _tokenIDs; // core -> coreConditionID -> tokenID
    uint256 private _lastTokenID;

    mapping(address => bool) cores;

    /**
     * @dev requires the function to be called only by TotoBetting contract owner
     */
    modifier onlyCore() {
        require(cores[msg.sender] == true, "BetToken: Only core");
        _;
    }

    /**
     * @dev initialize TotoBet contract
     */
    function initialize() public virtual initializer {
        __Ownable_init();
        __ERC1155_init("TotoBet");
    }

    /**
     * @dev Set/unset address as allowed TotoBetting contract address
     * @param core_ TotoBetting contract address
     * @param active_ if the contract is allowed
     */
    function updateCore(address core_, bool active_)
        external
        override
        onlyOwner
    {
        cores[core_] = active_;
    }

    /**
     * @dev get bet token id
     * @param core_ TotoBetting contract address
     * @param coreConditionID_ the match or game id in TotoBetting's internal system
     * @param outcomeIndex_ index of condition's outcome in TotoBetting's internal system
     * @return unique for every core, condition and its outcomes bet token id
     */
    function getTokenID(
        address core_,
        uint256 coreConditionID_,
        uint8 outcomeIndex_
    ) public view override returns (uint256) {
        uint256 tokenID = _tokenIDs[core_][coreConditionID_];
        require(tokenID != 0, "BetToken: Token does not exist");

        return tokenID + outcomeIndex_;
    }

    /**
     * @dev See {IERC1155-balanceOf}
     */
    function balanceOf(address account, uint256 conditionOutcomeID_)
        public
        view
        override(ERC1155Upgradeable, ITotoBet)
        returns (uint256)
    {
        return balanceOf(account, conditionOutcomeID_);
    }

    /**
     * @dev creates `amount_` bet tokens, and assigns them to `to_`.
     *
     * See also {ERC1155Upgradeable-_mint}
     *
     * @param to_ account address bet token assign to
     * @param coreConditionID_ the match or game id in TotoBetting's internal system
     * @param outcomeIndex_ index of condition's outcome in TotoBetting's internal system
     * @param amount_ amount of bet token create to
     * @return unique for every core, condition and its outcomes bet token id
     */
    function mint(
        address to_,
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

        super._mint(to_, tokenID, amount_, "");

        return tokenID;
    }

    /**
     * @dev destroys `amount_` bet tokens from `from`.
     *
     * See also {ERC1155Upgradeable-_burn}
     *
     * @param from_ account address bet token burn from
     * @param coreConditionID_ the match or game id in TotoBetting's internal system
     * @param outcomeIndex_ index of condition's outcome in TotoBetting's internal system
     * @param amount_ amount of bet token burn to
     */
    function burn(
        address from_,
        uint256 coreConditionID_,
        uint8 outcomeIndex_,
        uint256 amount_
    ) external override onlyCore {
        super._burn(
            from_,
            getTokenID(msg.sender, coreConditionID_, outcomeIndex_),
            amount_
        );
    }
}
