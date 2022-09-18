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
import "./interface/IERC20L2.sol";
import "./tunnel/BaseChildTunnel.sol";
import "./utils/Ownable.sol";
import "./type/Tunnel.sol";
import "./type/L2.sol";

contract Layer2Batcher is BaseChildTunnel, Ownable, Initializable {

    mapping(address => uint) public depositPerUser;

    /// @dev id => batch
    mapping(uint => Batch) public depositBatches;
    
    /// @dev id => batch
    mapping(uint => Batch) public sellBatches;

    /// @dev current deposit batch id. it will get increased after the each batch call
    uint public depositBatchId;
    
    /// @dev current sell batch id. it will get increased after the each batch call
    uint public sellBatchId;

    /// @dev usdc on L2
    address public usdc;

    /// @dev erc20 on L2
    ERC20Token[] internal erc20Tokens;

    string[] internal detfs;

    uint internal constant myriad = 10000;

    event DepositBatch(uint id, uint[] amounts);
    event SellTokenBatch(uint id, uint[] amounts);
    event Deposit(uint amount, uint detf, address indexed user);
    event Sell(uint[] amounts, address indexed user);

    constructor(address usdcAddress)
        BaseChildTunnel()
        Ownable()
    {
        usdc = usdcAddress;
    }

    function initialize()
        public
        override(BaseChildTunnel, Ownable)
        initializer
    {
        BaseChildTunnel.initialize();
        Ownable.initialize();
    }

    function setUsdc(address usdc_) public virtual onlyOwner {
        usdc = usdc_;
    }

    function addToken(string memory name, address token)
        virtual
        public
        onlyOwner
    {
        erc20Tokens.push(ERC20Token(token, name));
        depositBatches[depositBatchId].tokenCount += 1;
        sellBatches[sellBatchId].tokenCount += 1;
    }

    function addDETF(string memory name)
        virtual
        public
        onlyOwner
    {
        detfs.push(name);
        depositBatches[depositBatchId].detfCount += 1;
        sellBatches[sellBatchId].detfCount += 1;
    }

    function getTokenList()
        virtual
        public
        view
        returns(ERC20Token[] memory)
    {
        return erc20Tokens;
    }

    function getDetfList()
        virtual
        public
        view
        returns(string[] memory)
    {
        return detfs;
    }

    /**
     *  @dev Deposit `amount` of USDC for DETF specified by `detf`, and put the tx in `batch`.
     *  Deposit is a tx that user deposits USDC and distribute tokens minted using the USDC to users.
     *  Token mint will be done on L1.
     *  @param amount USDC amount
     *  @param detf DETF index
     */
    function deposit(uint amount, uint detf) virtual public {
        // transfer user usdc to this contract
        require(IERC20L2(usdc).transferFrom(msg.sender, address(this), amount), "USDC transfer failed");
        require(detf < detfs.length, "Invalid DETF type");

        Batch storage batch = depositBatches[depositBatchId];
        
        depositPerUser[msg.sender] += amount;
        batch.amounts[msg.sender][detf] += amount;
        batch.amountsL2[detf] += amount;

        if (!batch.hasUser[msg.sender]) {
            batch.users.push(msg.sender);
        }

        batch.hasUser[msg.sender] = true;

        emit Deposit(amount, detf, msg.sender);
    }

    /**
     *  @dev Put tx that sells `sellPercentage` percentage of tokens in `batch`.
     *  Token sell is a tx that user retreives tokens and gets USDC back.
     *  Redeeming tokens will be done on L1.
     *  @param sellPercentage token percentages
     */
    function sell(uint[] memory sellPercentage) virtual public {
        require(erc20Tokens.length == sellPercentage.length, "Invalid token length");

        Batch storage batch = sellBatches[sellBatchId];
        uint[] memory amounts = new uint[](erc20Tokens.length);

        for (uint i = 0; i < erc20Tokens.length; i++) {
            uint balance = IERC20L2(erc20Tokens[i].tokenAddress).balanceOf(msg.sender);
            uint amount = balance * sellPercentage[i] / myriad;

            require(amount <= balance, "Sell percentage too large");
            require(IERC20L2(erc20Tokens[i].tokenAddress).transferFrom(
                msg.sender,
                address(this),
                amount
            ), "Token transfer failed");

            batch.amounts[msg.sender][i] += amount;
            batch.amountsL2[i] += amount;
            amounts[i] = batch.amounts[msg.sender][i];
        }

        if (!batch.hasUser[msg.sender]) {
            batch.users.push(msg.sender);
        }

        batch.hasUser[msg.sender] = true;

        emit Sell(amounts, msg.sender);
    }

    /**
     *  @dev Burn USDC and send deposit batch to L1
     */
    function executeDepositBatch() virtual public {
        TunnelData memory tunnelData;
        Batch storage batch = depositBatches[depositBatchId];
        uint depositSum = 0;

        batch.status = BatchLifeCycle.Fired;
        tunnelData.batchType = BatchType.Deposit;
        tunnelData.id = depositBatchId;
        tunnelData.amounts = new uint[](detfs.length);

        // Gets deposit sum per detf and batch data to be used in event
        for (uint i = 0; i < detfs.length; i++) {
            tunnelData.amounts[i] = batch.amountsL2[i];
            depositSum += batch.amountsL2[i];
        }
        
        // Burn USDC
        IERC20L2(usdc).withdraw(depositSum);

        // Send batch to L1 via tunnel
        _sendMessageToRoot(abi.encode(tunnelData));
        emit DepositBatch(depositBatchId, tunnelData.amounts);

        // Initialize new batch for the next one
        depositBatchId += 1;
        Batch storage newBatch = depositBatches[depositBatchId];
        newBatch.detfCount = detfs.length;
        newBatch.tokenCount = erc20Tokens.length;
    }

    /**
     *  @dev Burn tokens and send sell batch to L1
     */
    function executeSellBatch() virtual public {
        TunnelData memory tunnelData;
        Batch storage batch = sellBatches[sellBatchId];

        batch.status = BatchLifeCycle.Fired;
        tunnelData.batchType = BatchType.SellToken;
        tunnelData.id = sellBatchId;
        tunnelData.amounts = new uint[](erc20Tokens.length);

        // Gets selling amount sum per token and batch data to be used in event
        for (uint i = 0; i < erc20Tokens.length; i++) {
            tunnelData.amounts[i] = batch.amountsL2[i];

            // Burn token
            IERC20L2(erc20Tokens[i].tokenAddress).withdraw(tunnelData.amounts[i]);
        }

        // Send data to L1 via tunnel
        _sendMessageToRoot(abi.encode(tunnelData));
        emit SellTokenBatch(sellBatchId, tunnelData.amounts);

        // Initialize new batch for the next one
        sellBatchId += 1;
        Batch storage newBatch = sellBatches[sellBatchId];
        newBatch.detfCount = detfs.length;
        newBatch.tokenCount = erc20Tokens.length;
    }

    /**
     *  @dev Process deposit batch specified by `batchId` and distribute tokens to users in the batch.
     *  This function will be called after the batch is processed in L1 and L1 returns minted tokens.
     *  @param batchId id of batch to process
     */
    function distribute(uint batchId) virtual public {
        Batch storage batch = depositBatches[batchId];
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
                IERC20L2(erc20Tokens[j].tokenAddress).transfer(user, amount);
            }
        }

        batch.status = BatchLifeCycle.Over;
    }

    /**
     *  @dev Process sell batch specified by `batchId` and send USDC back to users in the batch.
     *  This function will be called after the batch is processed in L1 and L1 returns redeemed USDC.
     *  @param batchId id of batch to process
     */
    function retrieve(uint batchId) virtual public {
        Batch storage batch = sellBatches[batchId];

        require(batch.status == BatchLifeCycle.Processed, "Can not retrieve usdc before batch is processed in L1");

        for (uint i = 0; i < batch.users.length; i++) {
            address user = batch.users[i];
            uint amount = 0;

            for (uint j = 0; j < batch.tokenCount; j++) {
                amount += batch.amountsL1[j] * batch.amounts[user][j] / batch.amountsL2[j];
            }

            depositPerUser[user] -= amount;
            // Send USDC back to users
            IERC20L2(usdc).transfer(user, amount);
        }

        batch.status = BatchLifeCycle.Over;
    }

    function __processMessageFromRoot(TunnelData memory data) virtual internal {
        Batch storage batch;

        // Get batch acoording to batch type
        if (data.batchType == BatchType.Deposit) {
            batch = depositBatches[data.id];
        } else {
            batch = sellBatches[data.id];
        }

        require(erc20Tokens.length == data.amounts.length, "Invalid token amount length");        
        require(batch.status == BatchLifeCycle.Fired, "Batch not fired");

        // amountsL1 is amounts of minted token when desposit, usdc after redeeming tokens when sell token
        for (uint i = 0; i < data.amounts.length; i++) {
            batch.amountsL1.push(data.amounts[i]);
        }

        if (data.batchType == BatchType.Deposit) {
            // Stores token weights (token share per DETF) sent from L1
            // and they will be used for calculating the distribution amount of tokens / usdc
            for (uint i = 0; i < data.tokenWeights.length; i++) {
                uint tokenCount = data.tokenWeights[i].length;
                batch.tokenWeights.push(new uint[](tokenCount));

                for (uint j = 0; j < tokenCount; j++) {
                    batch.tokenWeights[i][j] = data.tokenWeights[i][j];
                }
            }
        }

        batch.status = BatchLifeCycle.Processed;
    }

    /**
     *  @dev Data tunnel function to process message from L1
     *  @param message data sent from L1
     */
    function _processMessageFromRoot(bytes memory message) virtual internal override {
        TunnelData memory data = abi.decode(message, (TunnelData));
        __processMessageFromRoot(data);
    }

    /**
     *  @dev Used for test purpose only
     */
    function mockProcessMessageFromRoot(bytes memory message) virtual external {
        _processMessageFromRoot(message);
    }
}
