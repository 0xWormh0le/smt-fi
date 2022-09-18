[![Coverage Status](https://coveralls.io/repos/github/SmartDeFi/safe-relay-service/badge.svg?branch=eugene/layer2-contract)](https://coveralls.io/github/SmartDeFi/safe-relay-service?branch=eugene/layer2-contract)


## Introduction

This repository keeps contracts which handle deposit / withdraw transactions in a batch minting IDLE tokens, L1 Router and proxy.

## How to run the project

* Compile contracts by `yarn compile` or `npm run compile`
* Show test coverage rate by `yarn coverage` or `npm run coverage`
* Update coverage rate badge in `README.md` by `yarn coverage-badge` or `npm run coverage-badge`
* Run tests by `yarn test`

## How it works

1. User deposits USDC in Layer2Batcher in order to get DETF.
This will include USDC amount and DETF type they want and Layer2Batcher will accumulate the transactions without executing them till the trigger from Node scheudler in the next step. There are currently 4 types of DETF each of which has different weights of IDLE tokens (Risk Adjusted and Best Yield).

2. Node scheduler app calls `executeDepositBatch` function of Layer1Batcher every X hours.
Layer1Batcher will look into the transactions accumulated and process them in a batch following below steps.
   * Burns USDC deposited.
   * Groups transactions for per DETF in a batch, hence all transactions in a batch will have the same DETF.
   * Sends a batch data to L1 via [data tunnel](https://docs.matic.network/docs/develop/l1-l2-communication/data-tunnel/) and emits an event with the batch data for Node scheduler.
3. The Node scheduler will catch the event from L2, submit hash of batch to L1 once it crosses the check point.
4. L1 verifies the hash from Node scheduler with that of message from L1, ensure everything is safe.
5. L1 interacts with DeFi procotols ([Idle Finance](https://idle.finance/)) to mint tokens and send message to Layer2Batcher via data tunnel.
   * Layer1Router dispatches batch to proper child contract specific to DETF according to the DETF of the batch.
   * Child contract interacts with DeFi protocols and mints Idle tokens.
   * Child contract sends a message of minted amount of each tokens that compose DETF to Layer1Router via data tunnel between Layer1Router and Layer2Batcher.
6. Layer2Batcher distributes tokens proportionally to the user deposits.

## Data Structure

### How is `TX[]` converted to `Batch`

We use different batch for per DETF.

Say

* user A deposited 20 for Conservative and 30 for Growth

* user B deposited 40 for Conservative and 50 for Growth

There will be two batches:

* One for Conservative batch

```
[
    user A deposit 20 for Conservative,
    user B deposit 40 for Conservative
]
```

* Another for Growth batch

```
[
    user A deposit 30 for Growth,
    user B deposit 50 for Growth
]
```

### L2

#### TX

```
struct TX {
    address user;
    uint amount;
}
```

#### BatchLifeCycle

```
enum BatchLifeCycle {
    None,
    Fired,      // after execution
    Processed,  // processed on L1 and has been notified of token mint / usdc amount when withdraw / sell token via tunnel
    Over        // after `distribute` or `retrieve` function
}
```

#### Batch

```
struct Batch {
    bytes32 id;
    TX[] data;
    BatchLifeCycle status;
    uint[] tokenAmountL1;
    // array of each ERC20 token mint amount when `depositBatchPool`,
    // array of each ERC20 token amount to be burnt when `sellBatchPool`
    uint detfType; // index of `erc20Tokens` array of `Layer2Batcher`
    uint dataAmountSum; // `amount` sum of data array
    uint amount;
    // DETF amount when `depositBatchPool`
    // USDC amount when `sellBatchPool`
}
```

### L1

#### BatchRouter

```
struct BatchRouter {
    bytes32 id;
    uint[] amounts;
    uint detfType;
}
```

#### BatchDETF

```
struct BatchDETF {
    bytes32 id;
    uint timestamp;
    uint usdc; // usdc amount
    uint detf; // detf amount
    uint[] tokenAmounts; // mint amount for per token when `Withdraw`, burn amount for per token when `SellToken`
    TunnelDataType dataType; // `Withdraw` or `SellToken`
}

```

### Tunnel

#### TunnelDataToRoot

```
struct TunnelDataToRoot {
    bytes32 batchId;
    uint amount; // deposit amount when `Withdraw`, DETF amount when `SellToken`
    uint detfType;
    TunnelDataType dataType;
}
```

#### TunnelDataFromRoot

```
struct TunnelDataFromRoot {
    bytes32 batchId;
    uint[] tokenAmount;
    // token mint amount when dataType is `Withdraw`, token burn amount when dataType is `SellToken`
    // This value will be put into `amountL1` of batch specified by `batchId`
    TunnelDataType dataType; // indicates the tunnel is used for `Withdraw` or `SellToken`
    uint amount;
    // DETF amount when `Withdraw`
    // USDC amount when `SellToken`
}
```

#### TunnelDataType

```
enum TunnelDataType {
    Withdraw,   // to deposit usdc and get rewarded tokens
    SellToken   // to sell rewarded tokens and retrieve usdc
}
```

## Contracts

* Layer2Batcher - User deposits some amount of DETF, executes them in a batch, ask L1 to mint IDLE tokens
* Layer1Router - Delegate calls to child contract for per DETF type, and returns minted IDLE tokens to Layer2Batcher
* Proxy - Unstructured upgradable proxy. Will be applied to both Layer2Batcher and Layer1Router

### Proxy

#### How to upgrade a contract

1. Make a new version of implementation contract (logic contract) by inheriting the previous version of contract. This way we guarantee data in the previous version of contract will consist in the new version.
2. Deploy the new version of implementation contract.
3. Call `upgradeTo` function of proxy contract passing implementation contract address to its arg.
4. Call `initialize` function from proxy contract to set initial values since data initialized from implementation contract's constructor won't take effect when calling from proxy.

#### How to make a contract upgradable

1. Inherit from the previous version of contract and Openzeppelin's `Initializable`.
2. Define `initialize` function and do the same thing as `constructor`. You can attach `initializer` modifier defined from Openzeppelin to this function to protect it from being invoked twice.
3. Since it is likely to access data or upgrade workflow of function from the previous version in the new version, it is a good practice to make data `internal` or `public` and make function `virtual` to ensure they will be used in the future version. Making them `private` won't make a future version be able to access them.
4. If you want to apply `Ownable` in the implementation contract that may need an upgrade in the future, you can inherit from `utils/Ownable.sol` which has `initialize` function in it. 

```
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";

contract NewVersion is Initializable, PrevVersion, SomeOtherContractIfNeeded {
    uint internal newlyAddedData;

    constructor() {
        // data initialized here won't take effect when the contract is called from proxy
    }

    function initialize()
        public
        virtual
        override
        initializer
    {
        // copy code from constructor to some initialization
    }

    function sellToken(uint _tokenId) virtual override {
        // updated sell token code here
    }

    function newFeature(uint _tokenId) virtual {
        // new feature that may be overrode in the future version
    }
}
```

#### Features

* Get proxy owner

`function proxyOwner() public view returns (address owner)`

Tells the address of the owner.

* Get implementation contract address

`function implementation() external view returns (address)`

Returns address of logic contract.

* Upgrade implementation contract

`function upgradeTo(address _impl)`

Allows the proxy owner to upgrade the implementation.

* Transfer proxy ownership

`function transferProxyOwnership(address _newOwner)`

Allows the current owner to transfer ownership
