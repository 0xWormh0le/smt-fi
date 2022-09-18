// SPDX-License-Identifier: ISC

pragma solidity ^0.8.4;

abstract contract Context {
    function msgSender() internal virtual returns (address) {
        return msg.sender;
    }
}

contract Exit is Context {}
