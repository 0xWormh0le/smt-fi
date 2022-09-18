// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "../interface/IProtocolContract.sol";

abstract contract BaseProtocol is IProtocolContract {

    address internal protocol;

    function setProtocolAddress(address value) public virtual override {
        require(value != address(0), "Invalid protocol");
        protocol = value;
    }
}
