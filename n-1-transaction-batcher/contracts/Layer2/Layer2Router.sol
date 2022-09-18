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
import "../interface/ISell.sol";
import "../tunnel/BaseChildTunnel.sol";
import "../utils/Ownable.sol";
import "../type/Tunnel.sol";
import "../type/L2.sol";

contract Layer2Batcher is BaseChildTunnel, Ownable, Initializable {

    mapping(address => uint) public depositPerUser;

    /// @dev usdc on L2
    address public usdc;

    /// @dev deposit and sell contract on L2
    address public depositContract;
    address public sellContract;

    /// @dev erc20 tokens on L2
    address[] internal tokens;
    string[] internal tokenNames;

    /// @dev array of detf name
    string[] internal detfs;

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

    /// @dev Set deposit and sell contract
    function setChildContracts(address deposit_, address sell_)
        public
        onlyOwner
    {
        if (deposit_ != address(0)) {
            depositContract = deposit_;
        }
        if (sell_ != address(0)) {
            sellContract = sell_;
        }
    }

    /// @dev Set usdc address on L2
    function setUsdc(address usdc_)
        public
        virtual
        onlyOwner
    {
        usdc = usdc_;
    }

    /// @dev Add token address on L2 (RA, BY, etc)
    function addToken(string memory name, address token)
        virtual
        public
        onlyOwner
    {
        tokens.push(token);
        tokenNames.push(name);
        IDeposit(depositContract).setTokenCount(tokens.length);
        ISell(sellContract).setTokenCount(tokens.length);
    }

    /// @dev Add DETF name
    function addDETF(string memory name)
        virtual
        public
        onlyOwner
    {
        detfs.push(name);
        IDeposit(depositContract).setDetfCount(detfs.length);
        ISell(sellContract).setDetfCount(detfs.length);
    }

    /**
     *  @dev Get token list
     *  @return tokens_
     *  @return names_
     */
    function getTokenList()
        virtual
        public
        view
        returns(address[] memory tokens_, string[] memory names_)
    {
        return (tokens, tokenNames);
    }

    /// @dev Get DETF list
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
        
        IDeposit(depositContract).deposit(amount, detf, msg.sender);
        depositPerUser[msg.sender] += amount;

        emit Deposit(amount, detf, msg.sender);
    }

    /**
     *  @dev Put tx that sells `sellPercentage` percentage of tokens in `batch`.
     *  Token sell is a tx that user retreives tokens and gets USDC back.
     *  Redeeming tokens will be done on L1.
     *  @param sellPercentage token percentages
     */
    function sell(uint[] memory sellPercentage) virtual public {
        require(tokens.length == sellPercentage.length, "Invalid token length");
        uint[] memory amounts = ISell(sellContract).sell(sellPercentage, tokens, msg.sender);

        emit Sell(amounts, msg.sender);
    }

    /**
     *  @dev Burn USDC and send deposit batch to L1
     */
    function executeDepositBatch() virtual public {
        (uint depositSum, TunnelData memory tunnelData, uint batchId) =
            IDeposit(depositContract).tunnelData(detfs.length, tokens.length);
        
        // Burn USDC
        IERC20L2(usdc).withdraw(depositSum);

        // Send batch to L1 via tunnel
        _sendMessageToRoot(abi.encode(tunnelData));
        emit DepositBatch(batchId, tunnelData.amounts);
    }

    /**
     *  @dev Burn tokens and send sell batch to L1
     */
    function executeSellBatch() virtual public {
        (TunnelData memory tunnelData, uint batchId) =
            ISell(sellContract).tunnelData(detfs.length, tokens.length);

        // Gets selling amount sum per token and batch data to be used in event
        for (uint i = 0; i < tokens.length; i++) {
            // Burn token
            IERC20L2(tokens[i]).withdraw(tunnelData.amounts[i]);
        }

        // Send data to L1 via tunnel
        _sendMessageToRoot(abi.encode(tunnelData));
        emit SellTokenBatch(batchId, tunnelData.amounts);
    }

    /**
     *  @dev Process deposit batch specified by `batchId` and distribute tokens to users in the batch.
     *  This function will be called after the batch is processed in L1 and L1 returns minted tokens.
     *  @param batchId id of batch to process
     */
    function distribute(uint batchId) virtual public {
        IDeposit(depositContract).distribute(batchId, tokens);
    }

    /**
     *  @dev Process sell batch specified by `batchId` and send USDC back to users in the batch.
     *  This function will be called after the batch is processed in L1 and L1 returns redeemed USDC.
     *  @param batchId id of batch to process
     */
    function retrieve(uint batchId) virtual public {
        (uint[] memory amounts, address[] memory users) =
            ISell(sellContract).retrieve(batchId, usdc);

        for (uint i = 0; i < amounts.length; i++) {
            depositPerUser[users[i]] -= amounts[i];
        }
    }

    /**
     *  @dev Dispatch message to child contract
     */
    function __processMessageFromRoot(TunnelData memory data) virtual internal {
        require(tokens.length == data.amounts.length, "Invalid token amount length");        
        
        if (data.batchType == BatchType.Deposit) {
            IDeposit(depositContract).processMessageFromRoot(data);
        } else {
            ISell(sellContract).processMessageFromRoot(data);
        }
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
