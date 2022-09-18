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

import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "hardhat/console.sol";
import "../interface/IERC20L2.sol";
import "../interface/IDeposit.sol";
import "../utils/Ownable.sol";
import "../type/Tunnel.sol";
import "../type/L2.sol";

contract Deposit is IDeposit, Ownable, Initializable {

    /// @dev id => batch
    mapping(uint => Batch) public batches;

    /// @dev current deposit batch id. it will get increased after the each batch call
    uint public batchId;

    /// @dev router address
    address public parent;

    uint internal constant myriad = 10000;

    modifier onlyParent() {
        require(msg.sender == parent);
        _;
    }

    constructor()
        Ownable()
    { }

    function initialize()
        public
        override(Ownable)
        initializer
    {
        Ownable.initialize();
    }

    function setParent(address value)
        public
        onlyOwner
    {
        parent = value;
    }

    function setTokenCount(uint count)
        public
        override
        onlyParent
    {
        batches[batchId].tokenCount = count;
    }

    function setDetfCount(uint count)
        public
        override
        onlyParent
    {
        batches[batchId].detfCount = count;
    }

    /**
     *  @dev Deposit `amount` of USDC for DETF specified by `detf`, and put the tx in `batch`.
     *  Deposit is a tx that user deposits USDC and distribute tokens minted using the USDC to users.
     *  Token mint will be done on L1.
     *  @param amount USDC amount
     *  @param detf DETF index
     *  @param user user address
     */
    function deposit(uint amount, uint detf, address user)
        virtual
        override
        onlyParent
        public
    {
        Batch storage batch = batches[batchId];
        
        batch.amounts[user][detf] += amount;
        batch.amountsL2[detf] += amount;

        if (!batch.hasUser[user]) {
            batch.users.push(user);
        }

        batch.hasUser[user] = true;
    }

    /**
     *  @dev Return tunnel data and initiate next batch
     *  @param detfCount detf count
     *  @param tokenCount token count
     *  @return deopsitSum
     *  @return tunnelData
     *  @return batchId
     */
    function tunnelData(uint detfCount, uint tokenCount)
        virtual
        override
        public
        onlyParent
        returns(uint, TunnelData memory, uint)
    {
        TunnelData memory tunnelData_;
        Batch storage batch = batches[batchId];
        uint depositSum = 0;

        batch.status = BatchLifeCycle.Fired;
        tunnelData_.batchType = BatchType.Deposit;
        tunnelData_.id = batchId;
        tunnelData_.amounts = new uint[](detfCount);

        // Gets deposit sum per detf and batch data to be used in event
        for (uint i = 0; i < detfCount; i++) {
            tunnelData_.amounts[i] = batch.amountsL2[i];
            depositSum += batch.amountsL2[i];
        }

        // Initialize new batch for the next one
        batchId += 1;
        Batch storage newBatch = batches[batchId];
        newBatch.detfCount = detfCount;
        newBatch.tokenCount = tokenCount;

        return (depositSum, tunnelData_, batchId - 1);
    }

    /**
     *  @dev Process deposit batch specified by `batchId` and distribute tokens to users in the batch.
     *  This function will be called after the batch is processed in L1 and L1 returns minted tokens.
     *  @param batchId_ id of batch to process
     *  @param tokens array of tokens
     */
    function distribute(uint batchId_, address[] memory tokens)
        virtual
        override
        onlyParent
        public
    {
        Batch storage batch = batches[batchId_];
        uint[] memory totalTokenFactor = new uint[](batch.tokenCount);

        require(batch.status == BatchLifeCycle.Processed, "Can not distribute before batch is processed in L1");

        // Calculate token distribution amount
        for (uint i = 0; i < batch.tokenCount; i++) {
            for (uint j = 0; j < batch.detfCount; j++) {
                totalTokenFactor[i] += batch.amountsL2[j] * batch.tokenWeights[j][i] / myriad;
            }
        }

        for (uint i = 0; i < batch.users.length; i++) {
            address user = batch.users[i];

            for (uint j = 0; j < batch.tokenCount; j++) {
                uint userTokenFactor = 0;

                for (uint k = 0; k < batch.detfCount; k++) {
                    userTokenFactor += batch.amounts[user][k] * batch.tokenWeights[k][j] / myriad;
                }

                // Transfer token to user
                uint amount = batch.amountsL1[j] * userTokenFactor / totalTokenFactor[j];
                IERC20L2(tokens[j]).transferFrom(msg.sender, user, amount);
            }
        }

        batch.status = BatchLifeCycle.Over;
    }

    /**
     *  @dev Process deposit message sent from router bridge
     *  @param data tunnel data
     */
    function processMessageFromRoot(TunnelData memory data)
        virtual
        override
        onlyParent
        public
    {
        Batch storage batch = batches[data.id];

        require(batch.status == BatchLifeCycle.Fired, "Batch not fired");

        // amountsL1 is amounts of minted token when desposit, usdc after redeeming tokens when sell token
        for (uint i = 0; i < data.amounts.length; i++) {
            batch.amountsL1.push(data.amounts[i]);
        }

        // Stores token weights (token share per DETF) sent from L1
        // and they will be used for calculating the distribution amount of tokens / usdc
        for (uint i = 0; i < data.tokenWeights.length; i++) {
            uint tokenCount = data.tokenWeights[i].length;
            batch.tokenWeights.push(new uint[](tokenCount));

            for (uint j = 0; j < tokenCount; j++) {
                batch.tokenWeights[i][j] = data.tokenWeights[i][j];
            }
        }

        batch.status = BatchLifeCycle.Processed;
    }
}
