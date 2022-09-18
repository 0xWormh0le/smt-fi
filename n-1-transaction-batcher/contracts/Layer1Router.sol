// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.4;

import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "hardhat/console.sol";
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

    address internal rootChainManager;
    
    address internal predicate;

    /// @dev layer2 contract address to which send tokens
    address internal l2;

    /// @dev hash to TunnelData
    mapping(bytes32 => TunnelData) internal batches;

    uint internal constant myriad = 10000;

    event Minted(uint id, uint[] minted);

    event Redeemed(uint id, uint[] redeemed);

    event MessageSent(bytes message);

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
        address _l2,
        address _rootChainManager,
        address _predicate
    )
        virtual
        public
        onlyOwner
    {
        if (_l2 != address(0)) {
            l2 = _l2;
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
        require(value != address(0), "Router: Invalid protocol contract address");
        protocols.push(value);
        protocolNames.push(name);
    }

    /// @dev Update protocol contract
    /// @param index Index of protocol
    /// @param name Name of the protocol
    /// @param value Address of protocol contract, which generally resides in contracts/protocols directory
    function updateProtocol(uint index, string memory name, address value)
        virtual
        public
        onlyOwner
    {
        require(index < protocols.length, "Router: Invalid protocol index");

        if (keccak256(bytes(name)) != keccak256(bytes(""))) {
            protocolNames[index] = name;
        }

        if (value != address(0)) {
            protocols[index] = value;
        }
    }

    /// @dev Set token weights specified by `weights` for `detf`
    /// @param detf DETF index
    /// @param weights Array of token weights for `detf`
    function setTokenWeights(uint detf, uint[] memory weights)
        virtual
        public
        onlyOwner
    {
        require(detf < detfs.length, "Router: Invalid detf index");
        require(weights.length == protocols.length, "Router: Invalid weights length");

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

        require(l2 != address(0), "Router: L2 contract not set");
        require(batch.amounts.length == detfs.length, "Router: Invalid DETF length");
        require(getBatchHash(batch) == hashValue, "Router: nvalid message");

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
            uint assetRequired = 0;
            address token = IProtocolContract(protocols[i]).token();
            address assetToken = IProtocolContract(protocols[i]).assetToken();

            // calculates total token amount to mint based on token weights and asset token deposits for per DETF
            // batch.amounts is an array of deposit sum for per DETF
            for (uint j = 0; j < detfs.length; j++) {
                response.tokenWeights[j][i] = tokenWeights[j][i];
                assetRequired += batch.amounts[j] * tokenWeights[j][i] / myriad;
            }

            require(IERC20(assetToken).balanceOf(address(this)) >= assetRequired, "Router: Not enough asset to mint token");
            require(IERC20(assetToken).transfer(protocols[i], assetRequired), "Router: Failed to transfer asset token to protocol contract");

            // interacts with protocol contract to mint token
            uint minted = IProtocolContract(protocols[i]).mint(assetRequired);
            response.amounts[i] = minted;

            // sends token to L2
            IERC20(token).approve(predicate, minted);
            IRootChainManager(rootChainManager).depositFor(l2, token, abi.encode(minted));
        }

        // notifies layer2 that the batch was processed
        sendMessageToChild(response);

        emit Minted(batch.id, response.amounts);
    }

    /// @dev Handle sell request, redeem tokens, send asset token to layer2
    /// It gets hashed value of batch and handles a batch for the hash
    /// @param message Hashed value of batch
    function sell(bytes memory message)
        public
        virtual
    {
        bytes32 hashValue = abi.decode(message, (bytes32));
        TunnelData memory batch = batches[hashValue];
        TunnelData memory response;

        require(l2 != address(0), "Router: L2 contract not set");
        require(batch.amounts.length == protocols.length, "Router: Invalid token length");
        require(getBatchHash(batch) == hashValue, "Router: Invalid message");

        // initializes response
        response.id = batch.id;
        response.batchType = BatchType.SellToken;
        response.amounts = new uint[](protocols.length);
        response.tokenWeights = new uint[][](detfs.length);

        // redeems tokens iterating protocols
        // batch.amounts is an array of redeem amount sum for per token
        for (uint i = 0; i < protocols.length; i++) {
            address token = IProtocolContract(protocols[i]).token();
            address assetToken = IProtocolContract(protocols[i]).assetToken();

            require(IERC20(token).balanceOf(address(this)) >= batch.amounts[i], "Router: Not enough token to redeem");
            require(IERC20(token).transfer(protocols[i], batch.amounts[i]), "Router: Failed to transfer token to protocol contract");

            // redeemed is asset token amount returned by redeeming token
            uint redeemed = IProtocolContract(protocols[i]).redeem(batch.amounts[i]);
            response.amounts[i] = redeemed;

            // send asset tokens to L2
            IERC20(assetToken).approve(predicate, redeemed);
            IRootChainManager(rootChainManager).depositFor(l2, assetToken, abi.encode(redeemed));
        }

        // notifies layer2 that the batch was processed
        sendMessageToChild(response);

        emit Redeemed(batch.id, response.amounts);
    }

    function sendMessageToChild(TunnelData memory data)
        internal
        virtual
    {
        bytes memory message = abi.encode(data);
        _sendMessageToChild(message);
        emit MessageSent(message);
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

    /// @dev For test purpose only
    function mockProcessMessageFromChild(bytes memory message) public {
        _processMessageFromChild(message);
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
        return keccak256(abi.encodePacked(batch.id, uint(batch.batchType)));
    }
}
