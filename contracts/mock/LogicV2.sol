// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./LogicV1.sol";

contract LogicV2 is LogicV1 {
    uint public anotherData;

    function set(uint val) override external {
        data = val * val;
    }

    function setAnotherData(uint val)
        virtual
        onlyOwner
        external
    {
        anotherData = val;
    }
}
