// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.4;

import "../interface/IRootChainManager.sol";

contract RootChainManager is IRootChainManager {

    function registerPredicate(bytes32 tokenType, address predicateAddress) external override
    { }

    function mapToken(
        address rootToken,
        address childToken,
        bytes32 tokenType
    ) external override
    { }

    function cleanMapToken(address rootToken, address childToken) external override
    { }

    function remapToken(
        address rootToken,
        address childToken,
        bytes32 tokenType
    ) external override
    { }

    function depositEtherFor(address user) external override payable
    { }

    function depositFor(
        address user,
        address rootToken,
        bytes calldata depositData
    ) external override
    { }

    function exit(bytes calldata inputData) external override
    { }
}
