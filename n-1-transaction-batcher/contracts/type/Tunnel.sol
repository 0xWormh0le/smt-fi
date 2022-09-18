// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.4;

import "./L2.sol";

struct TunnelData {
    BatchType batchType;
    uint id;
    uint[][] tokenWeights; // used only when batchType is deposit and direction is to client
    uint[] amounts;
    /**
     * when deposit:
     *   to root: deposit sum per detf
     *   to client: mint amount per token
     * when sell:
     *   to root: sell sum per token
     *   to client: usdc amount per token
     */
}
