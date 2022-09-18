// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../type/L1.sol";

contract Erc20Mock is ERC20 {
    uint public balance;

    constructor (string memory name_, string memory symbol_)
        ERC20(name_, symbol_)
    { }

    function withdraw(uint amount) external {
        _burn(msg.sender, amount);
    }

    function mint(uint amount) external {
        _mint(msg.sender, amount);
    }

    function deposit(bytes memory message) external {
        // BatchRouter memory batch = abi.decode(message, (BatchRouter));
        // uint sum = 0;
        // for (uint i = 0; i < batch.amounts.length; i++) {
        //     sum += batch.amounts[i];
        // }
        // balance += sum;
    }

    function sell(bytes memory message) external {
        // BatchRouter memory batch = abi.decode(message, (BatchRouter));
        // uint sum = 0;
        
        // for (uint i = 0; i < batch.amounts.length; i++) {
        //     sum += batch.amounts[i];
        // }

        // require(balance >= sum, "Insufficient balance");
        // balance -= sum;
    }
}
