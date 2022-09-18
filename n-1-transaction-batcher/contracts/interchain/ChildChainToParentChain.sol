// SPDX-License-Identifier: UNLICENSED

/**
 * Contract would be deployed to Matic Mumbai Testnet
 *
 * Requirements:
 * Test ERC20 Tokens on Matic (Dummy ERC20 in our case)
 * Mapping of ethereum <> matic contract
 * Using PoS Chain (Patience !)
 */

/**
 * Key Variables
 */

pragma solidity ^0.8.4;

abstract contract Context {
    function msgSender() internal virtual returns (address) {
        return msg.sender;
    }
}

interface IChildContract {
    function withdraw(uint256 amount) external;

    function balanceOf(address user) external view returns (uint256);
}

contract ChildToParent is Context {
    IChildContract public token;

    event Burn();

    constructor(address _contract) {
        token = IChildContract(_contract);
    }

    function burn() public virtual returns (bool) {
        uint256 amount = token.balanceOf(address(this));
        token.withdraw(amount);

        emit Burn();
        return true;
    }
}
