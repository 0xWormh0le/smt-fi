// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.4;

import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./utils/Ownable.sol";
import "./tunnel/BaseRootTunnel.sol";
import "./interface/IRootChainManager.sol";
import "./interface/IProtocolContract.sol";
import "./type/Tunnel.sol";


contract Layer1Router is BaseRootTunnel, Ownable, Initializable {
    string[] internal detfs;

    /// @dev address of child contract for protocol and a protocol has 1 to 1 relationship with token
    address[] internal protocols;

    string[] internal protocolNames;

    /// @dev token weight table (detf type * token type)
    mapping(uint => mapping(uint => uint)) internal tokenWeights;

    address internal assetCoin;

    address internal rootChainManager;
    
    address internal predicate;

    /// @dev layer1 contract address to which send tokens
    address internal l1;

    /// @dev hash to TunnelData
    mapping(bytes32 => TunnelData) internal batches;

    event Minted(uint id, uint[] minted);

    event Redeemed(uint id, uint[] redeemed);

    constructor()
        BaseRootTunnel()
        Ownable()
    { }

    function initialize()
        public
        virtual
        override(BaseRootTunnel, Ownable)
        initializer
    {
        BaseRootTunnel.initialize();
        Ownable.initialize();
    }

    function init(
        address _assetCoin,
        address _l1,
        address _rootChainManager,
        address _predicate
    )
        virtual
        public
        onlyOwner
    {
        if (_assetCoin != address(0)) {
            assetCoin = _assetCoin;
        }
        if (_l1 != address(0)) {
            l1 = _l1;
        }
        if (_rootChainManager != address(0)) {
            rootChainManager = _rootChainManager;
        }
        if (_predicate != address(0)) {
            predicate = _predicate;
        }
    }

    function addDETF(string memory name)
        virtual
        public
        onlyOwner
    {
        detfs.push(name);
    }

    /// @dev Add protocol contract that handles with protocol token mint / burn
    /// @param name Name of the protocol
    /// @param value Address of protocol contract, which generally resides in contracts/protocols directory
    function addProtocol(string memory name, address value)
        virtual
        public
        onlyOwner
    {
        require(value != address(0), "Invalid protocol contract address");
        protocols.push(value);
        protocolNames.push(name);
    }

    /// @dev Set token weights specified by `weights` for `detf`
    /// @param detf DETF index
    /// @param weights Array of token weights for `detf`
    function setTokenWeights(uint detf, uint[] memory weights)
        virtual
        public
        onlyOwner
    {
        require(detf < detfs.length, "Invalid detf index");
        require(weights.length == protocols.length, "Invalid weights length");

        for (uint i = 0; i < weights.length; i++) {
            tokenWeights[detf][i] = weights[i];
        }
    }

    /// @dev Handle deposit request, mint tokens, send them to layer2
    /// It gets hashed value of batch and handles a batch for the hash
    /// @param message Hashed value of batch
    function deposit(bytes memory message)
        public
        virtual
    {
        bytes32 hashValue = abi.decode(message, (bytes32));
        TunnelData memory batch = batches[hashValue];
        TunnelData memory response;

        require(l1 != address(0), "L1 contract not set");
        require(batch.amounts.length == detfs.length, "Invalid DETF length");
        require(getBatchHash(batch) == hashValue, "Invalid message");

        // initializes response
        response.id = batch.id;
        response.batchType = BatchType.Deposit;
        response.amounts = new uint[](protocols.length);
        response.tokenWeights = new uint[][](detfs.length);

        // initializes response token weights
        for (uint i = 0; i < detfs.length; i++) {
            response.tokenWeights[i] = new uint[](protocols.length);
        }

        // mints tokens iterating protocols
        for (uint i = 0; i < protocols.length; i++) {
            uint coinForToken = 0;
            address token = IProtocolContract(protocols[i]).getTokenAddress();

            // calculates total token amount to mint based on token weights and assetCoin deposits for various DETF
            // batch.amounts is an array of deposit sum for per DETF
            for (uint j = 0; j < detfs.length; j++) {
                response.tokenWeights[j][i] = tokenWeights[j][i];
                coinForToken += batch.amounts[j] * tokenWeights[j][i] / 10000;
            }

            // interacts with protocol contract to mint token
            uint minted = IProtocolContract(protocols[i]).mint(coinForToken);
            response.amounts[i] = minted;

            // sends token to L2
            IERC20(token).approve(predicate, minted);
            IRootChainManager(rootChainManager).depositFor(l1, token, abi.encode(minted));
        }

        // notifies layer2 that the batch was processed
        sendMessageToChild(response);

        emit Minted(batch.id, response.amounts);
    }

    /// @dev Handle sell request, redeem tokens, send assetCoin to layer2
    /// It gets hashed value of batch and handles a batch for the hash
    /// @param message Hashed value of batch
    function sell(bytes memory message)
        public
        virtual
    {
        bytes32 hashValue = abi.decode(message, (bytes32));
        TunnelData memory batch = batches[hashValue];
        TunnelData memory response;
        uint sumRedeemed = 0; // total assetCoin amount returned from redeeming token

        require(l1 != address(0), "L1 contract not set");
        require(batch.amounts.length == protocols.length, "Invalid token length");
        require(getBatchHash(batch) == hashValue, "Invalid message");

        // initializes response
        response.id = batch.id;
        response.batchType = BatchType.SellToken;
        response.amounts = new uint[](protocols.length);
        response.tokenWeights = new uint[][](detfs.length);

        // redeems tokens iterating protocols
        // batch.amounts is an array of redeem amount sum for per token
        for (uint i = 0; i < protocols.length; i++) {
            // redeemed is assetCoin amount returned by redeeming token
            uint redeemed = IProtocolContract(protocols[i]).redeem(batch.amounts[i]);
            response.amounts[i] = redeemed;
            sumRedeemed += redeemed;
        }

        // notifies layer2 that the batch was processed
        sendMessageToChild(response);

        // send assetCoin to L2
        IERC20(assetCoin).approve(predicate, sumRedeemed);
        IRootChainManager(rootChainManager).depositFor(l1, assetCoin, abi.encode(sumRedeemed));

        emit Redeemed(batch.id, response.amounts);
    }

    function sendMessageToChild(TunnelData memory data)
        internal
        virtual
    {
        bytes memory message = abi.encode(data);
        _sendMessageToChild(message);
    }

    /// @dev Save batch sent from layer2
    /// `deposit` and `sell` function declared above take hash of batch as an arg and
    /// proceed only when the arg matches with the hash of the batch stored in this function
    /// @param message Batch data sent from layer2 through tunnel
    function _processMessageFromChild(bytes memory message)
        override
        virtual
        internal
    {
        TunnelData memory data = abi.decode(message, (TunnelData));

        batches[getBatchHash(data)] = data;
    }

    /// @dev Return hash of the batch
    /// @param batch batch data
    /// @return hashed value
    function getBatchHash(TunnelData memory batch)
        internal
        pure
        virtual
        returns(bytes32)
    {
        return keccak256(abi.encodePacked(batch.id, batch.batchType));
    }
}
