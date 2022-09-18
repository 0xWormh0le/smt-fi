// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.4;

import '../interface/IStateSender.sol';

contract StateSenderMock is IStateSender {
    constructor() {}

    function syncState(address receiver, bytes calldata data) public override { }
}
