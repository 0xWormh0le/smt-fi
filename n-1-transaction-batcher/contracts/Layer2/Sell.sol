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
import "../interface/ISell.sol";
import "../utils/Ownable.sol";
import "../type/Tunnel.sol";
import "../type/L2.sol";

contract Sell is ISell, Ownable, Initializable {
    
    /// @dev id => batch
    mapping(uint => Batch) public batches;
    
    /// @dev current sell batch id. it will get increased after the each batch call
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
     *  @dev Put tx that sells `sellPercentage` percentage of tokens in `batch`.
     *  Token sell is a tx that user retreives tokens and gets USDC back.
     *  Redeeming tokens will be done on L1.
     *  @param sellPercentage token percentages
     *  @param tokens array of token addresses
     *  @param user user address
     */
    function sell(
        uint[] memory sellPercentage,
        address[] memory tokens,
        address user
    )
        virtual
        public
        override
        onlyParent
        returns(uint[] memory)
    {
        Batch storage batch = batches[batchId];
        uint[] memory amounts = new uint[](tokens.length);

        for (uint i = 0; i < tokens.length; i++) {
            uint balance = IERC20L2(tokens[i]).balanceOf(user);
            uint amount = balance * sellPercentage[i] / myriad;

            require(amount <= balance, "Sell percentage too large");
            require(IERC20L2(tokens[i]).transferFrom(
                user,
                msg.sender,
                amount
            ), "Token transfer failed");

            batch.amounts[user][i] += amount;
            batch.amountsL2[i] += amount;
            amounts[i] = batch.amounts[user][i];
        }

        if (!batch.hasUser[user]) {
            batch.users.push(user);
        }

        batch.hasUser[user] = true;

        return amounts;
    }

    /**
     *  @dev Return tunnel data and initiate next batch
     *  @param detfCount detf count
     *  @param tokenCount token count
     *  @return tunnelData
     *  @return batchId
     */
    function tunnelData(uint detfCount, uint tokenCount)
        virtual
        public
        override
        onlyParent
        returns(TunnelData memory, uint)
    {
        TunnelData memory tunnelData_;
        Batch storage batch = batches[batchId];

        batch.status = BatchLifeCycle.Fired;
        tunnelData_.batchType = BatchType.SellToken;
        tunnelData_.id = batchId;
        tunnelData_.amounts = new uint[](tokenCount);

        // Gets selling amount sum per token and batch data to be used in event
        for (uint i = 0; i < tokenCount; i++) {
            tunnelData_.amounts[i] = batch.amountsL2[i];
        }

        // Initialize new batch for the next one
        batchId += 1;
        Batch storage newBatch = batches[batchId];
        newBatch.detfCount = detfCount;
        newBatch.tokenCount = tokenCount;

        return (tunnelData_, batchId - 1);
    }

    /**
     *  @dev Process sell batch specified by `batchId` and send USDC back to users in the batch.
     *  This function will be called after the batch is processed in L1 and L1 returns redeemed USDC.
     *  @param batchId_ id of batch to process
     *  @param usdc usdc address on L2
     */
    function retrieve(uint batchId_, address usdc)
        virtual
        public
        override
        onlyParent
        returns(uint[] memory, address[] memory)
    {
        Batch storage batch = batches[batchId_];
        uint[] memory amounts = new uint[](batch.users.length);

        require(batch.status == BatchLifeCycle.Processed, "Can not retrieve usdc before batch is processed in L1");

        for (uint i = 0; i < batch.users.length; i++) {
            address user = batch.users[i];
            uint amount = 0;

            for (uint j = 0; j < batch.tokenCount; j++) {
                amount += batch.amountsL1[j] * batch.amounts[user][j] / batch.amountsL2[j];
            }

            amounts[i] = amount;

            // Send USDC back to users
            IERC20L2(usdc).transferFrom(msg.sender, user, amount);
        }

        batch.status = BatchLifeCycle.Over;
        return (amounts, batch.users);
    }

    /**
     *  @dev Process sell message sent from router bridge
     *  @param data tunnel data
     */
    function processMessageFromRoot(TunnelData memory data)
        virtual
        override
        public
        onlyParent
    {
        Batch storage batch = batches[data.id];

        require(batch.status == BatchLifeCycle.Fired, "Batch not fired");

        // amountsL1 is amounts of minted token when desposit, usdc after redeeming tokens when sell token
        for (uint i = 0; i < data.amounts.length; i++) {
            batch.amountsL1.push(data.amounts[i]);
        }

        batch.status = BatchLifeCycle.Processed;
    }
}
