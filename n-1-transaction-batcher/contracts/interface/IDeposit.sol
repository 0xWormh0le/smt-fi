// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.4;

import "../type/Tunnel.sol";

interface IDeposit {
    
    function setTokenCount(uint) external;

    function setDetfCount(uint) external;

    function deposit(uint amount, uint detf, address user) external;

    function tunnelData(uint detfCount, uint tokenCount)
        external returns(uint, TunnelData memory, uint);

    function distribute(uint batchId, address[] memory tokens) external;

    function processMessageFromRoot(TunnelData memory data) external;
}
