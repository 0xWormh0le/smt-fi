// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.4;

import "../type/Tunnel.sol";

interface ISell {
    
    function setTokenCount(uint) external;

    function setDetfCount(uint) external;

    function sell(uint[] memory sellPercentage, address[] memory tokens, address user)
        external returns(uint[] memory);

    function tunnelData(uint detfCount, uint tokenCount)
        external returns(TunnelData memory, uint);

    function retrieve(uint batchId, address usdc)
        external returns(uint[] memory, address[] memory);

    function processMessageFromRoot(TunnelData memory data) external;
}
