// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
import "../utils/Ownable.sol";

contract LogicV1 is Ownable {
    uint public data;

    function initialize() public override {
        Ownable.initialize();
    }

    function set(uint val) virtual external {
        data = val;
    }
}
