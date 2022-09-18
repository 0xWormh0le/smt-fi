// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IERC20L2 is IERC20 {
    function withdraw(uint amount) external;
}
