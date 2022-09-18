/**
    ======================================================
         Layer 2 Contract - To Be Deployed On MATIC
    ======================================================
 */

// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.4;

/**
 * Importing all the required dependencies
 * @Reentrancy Guard extends the required re-entrancy checks
 */

import "./security/ReentrancyGuard.sol";

interface IGenosisSafeRelay {
    /**
     * Allows users to deposit their USDC for IDLE
     */

    function deposit() external returns (bool);
}

contract GnosisSafeRelay is IGenosisSafeRelay, ReentrancyGuard {
    mapping(address => uint256) public fundsAmountPerUser;

    /**
     * usdc contract on MATIC network.
     * It reprensents a contract address.
     * used to facilitate transfer from user safes and back to user safes.
     */

    address public usdc;

    /**
     * idle contract on MATIC network
     * It represents a contract address.
     * used to facilitate the transfer of idle tokens from contract to user safes
     * and vice-versa.
     */

    address public idle;

    uint256 public totalAmount;

    constructor(address usdcAddress, address idleAddress) {
        usdc = usdcAddress;
        idle = idleAddress;
    }

    /**
     * deposit() will accept the number of tokens
     * with decimal and adds to a wait list
     */

    function deposit() public override returns (bool) {}

    /**
     * execute() will send pending tx to layer 1
     * usdc (users' safes) --> layer2 gnosis batcher
     * layer2 batcher --> layer1 batcher (not confirmed)
     * layer1 batcher --> idle finance
     * idle finance --> layer1 batcher
     * layer1 batcher --> layer2 batcher
     * idle tokens --> user safes
     */

    function execute() public payable {}
}
