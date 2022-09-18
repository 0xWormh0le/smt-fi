// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.4;

enum BatchLifeCycle {
    None,
    Fired,      // after execution
    Processed,  // processed on L1 and has been notified of token mint / usdc amount when withdraw / sell token via tunnel
    Over        // after `distribute` or `retrieve` function
}

enum BatchType {
    Deposit,   // to deposit usdc and get rewarded tokens
    SellToken   // to sell rewarded tokens and retrieve usdc
}

struct Batch {
    BatchLifeCycle status;

    // deposit: user => detf index => amount
    // sell: user => token index => amount
    mapping(address => mapping(uint => uint)) amounts;

    // detf index * token index
    uint[][] tokenWeights;

    // deposit: detf index => deposit sum per detf
    // sell: token index => sell sum per token
    mapping(uint => uint) amountsL2;

    // deposit: array of token mint amount
    // sell: array of usdc returned from buring token
    uint[] amountsL1;

    mapping(address => bool) hasUser;
    address[] users;
    uint detfCount;
    uint tokenCount;
}

// erc20 token structure for idle token and future one
struct ERC20Token {
    address tokenAddress;
    string name;
}
