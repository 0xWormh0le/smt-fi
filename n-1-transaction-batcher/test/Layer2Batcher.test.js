const chai = require("chai")
const { solidity } = require("ethereum-waffle")
const { ethers } = require("hardhat")
const { BigNumber } = require("ethers")
const { DETFType, BatchType, BatchLifeCycle, getEventArgs, getERC20Token } = require("./utils")
const { decode: decodeTunnelData, encode: encodeTunnelData } = require('./abiEncoder/TunnelData')
const { expect } = chai

chai.use(solidity)

describe("Layer2Batcher", function () {
  before(async function () {
    const L2 = await ethers.getContractFactory("Layer2Batcher")
    const ERC20 = await ethers.getContractFactory("Erc20Mock")
    
    this.usdc = await ERC20.deploy("USDC", "USDC")
    this.idleRA = await ERC20.deploy("IDLE-RA", "IDLE-RA")
    this.idleBY = await ERC20.deploy("IDLE-BY", "IDLE-BY")
    this.l2 = await L2.deploy(this.usdc.address)
    this.erc20Tokens = [
      [this.idleRA.address, 'Risk Adjusted'],
      [this.idleBY.address, 'Best Yield']
    ]

    await Promise.all([
      this.usdc.deployed(),
      this.idleRA.deployed(),
      this.idleBY.deployed(),
      this.l2.deployed(),
    ])

    const users = await ethers.getSigners()
    this.owner = users[0]
    this.nodeApp = users[1]
    this.users = users.slice(2)

    // mint usdc, RA, BY and approve
    const [alice, bob, carl] = this.users
    
    const aliceUsdc = this.usdc.connect(alice)
    const aliceRA = this.idleRA.connect(alice)
    const aliceBY = this.idleBY.connect(alice)

    const bobUsdc = this.usdc.connect(bob)
    const bobRA = this.idleRA.connect(bob)
    const bobBY = this.idleBY.connect(bob)

    const carlUsdc = this.usdc.connect(carl)
    const ownerRA = this.idleRA.connect(this.owner)
    const ownerBY = this.idleBY.connect(this.owner)
    const ownerUsdc = this.usdc.connect(this.owner)

    await Promise.all([
      aliceUsdc.mint(999),
      bobUsdc.mint(999),
      carlUsdc.mint(999),
      ownerRA.mint(999),
      ownerBY.mint(999),
      ownerUsdc.mint(999),
      aliceUsdc.approve(this.l2.address, 999),
      bobUsdc.approve(this.l2.address, 999),
      carlUsdc.approve(this.l2.address, 999),
      aliceRA.approve(this.l2.address, 999),
      aliceBY.approve(this.l2.address, 999),
      bobRA.approve(this.l2.address, 999),
      bobBY.approve(this.l2.address, 999)
    ])

    // initialize layer2 balance
    await Promise.all([
      ownerRA.transfer(this.l2.address, 999),
      ownerBY.transfer(this.l2.address, 999),
      ownerUsdc.transfer(this.l2.address, 999)
    ])

    this.tokenWeights = [
      [1000, 2000],
      [2000, 5000],
      [1000, 3000]
    ]
  })

  it('Initialization works', async function () {
    const ownerL2 = this.l2.connect(this.owner)
    const aliceL2 = this.l2.connect(this.users[0])

    await ownerL2.addDETF('Conservative')
    await ownerL2.addDETF('Balanced')
    await ownerL2.addDETF('Growth')

    await ownerL2.addToken('Idle RA', this.idleRA.address)
    await ownerL2.addToken('Idle BY', this.idleBY.address)

    expect(await ownerL2.getDetfList()).to.eql([
      'Conservative',
      'Balanced',
      'Growth'
    ])

    expect(await ownerL2.getTokenList()).to.eql([
      getERC20Token({ address: this.idleRA.address, name: 'Idle RA' }),
      getERC20Token({ address: this.idleBY.address, name: 'Idle BY' }),
    ])

    await expect(aliceL2.addDETF('Aggressive'))
      .to.revertedWith('Ownable: caller is not the owner')
    await expect(aliceL2.addToken('Another', this.idleRA.address))
      .to.revertedWith('Ownable: caller is not the owner')
  })

  describe('Deposit', function () {
    let balance

    before(async function () {
      const [alice, bob, carl] = this.users
      const aliceL2 = this.l2.connect(alice)
      const bobL2 = this.l2.connect(bob)
      const carlL2 = this.l2.connect(carl)
      const usdc = this.usdc.connect(alice)
      
      balance = await usdc.balanceOf(this.l2.address)
      await Promise.all([
        aliceL2.deposit(100, DETFType.Conservative),
        aliceL2.deposit(200, DETFType.Balanced),
        aliceL2.deposit(300, DETFType.Growth),
        bobL2.deposit(200, DETFType.Conservative),
        bobL2.deposit(300, DETFType.Balanced),
        carlL2.deposit(100, DETFType.Conservative),
        carlL2.deposit(200, DETFType.Balanced),
        carlL2.deposit(300, DETFType.Growth),
        // more deposits
        bobL2.deposit(100, DETFType.Balanced),
        carlL2.deposit(300, DETFType.Balanced),
      ])
    })

    it('Check depositPerUser is increased', async function () {
      const [alice, bob, carl] = this.users
      const l2 = this.l2.connect(alice)

      expect(await l2.depositPerUser(alice.address))
        .to.equal(BigNumber.from(100 + 200 + 300))
      expect(await l2.depositPerUser(bob.address))
        .to.equal(BigNumber.from(200 + 400))
      expect(await l2.depositPerUser(carl.address))
        .to.equal(BigNumber.from(100 + 500 + 300))
    })

    it('USDC is transferred to layer2 from depositors', async function () {
      const usdc = this.usdc.connect(this.users[0])
      expect(await usdc.balanceOf(this.l2.address)).to.equal(balance.add(2100))
    })
  })

  describe('Execute deposit batch', function () {
    let executedBatchId, balance, tunnelArg, depositBatchArg

    before(async function () {
      const nodeApp = this.l2.connect(this.nodeApp)
      const usdc = this.usdc.connect(this.users[0])
      const events = getEventArgs(nodeApp, ['MessageSent', 'DepositBatch'])

      executedBatchId = await nodeApp.depositBatchId()
      balance = await usdc.balanceOf(this.l2.address)

      nodeApp.executeDepositBatch()
      const args = await Promise.all(events)

      tunnelArg = args[0]
      depositBatchArg = args[1]
    })

    it('Check tunnel data', async function () {
      const [tunnelMessage] = tunnelArg
      const tunnelData = decodeTunnelData(tunnelMessage)

      expect(tunnelData.batchType).to.equal(BatchType.Deposit)
      expect(tunnelData.id).to.equal(executedBatchId)
      expect(tunnelData.tokenWeights).to.eql([])
      expect(tunnelData.amounts).to.eql([
        BigNumber.from(100 + 200 + 100),
        BigNumber.from(200 + 400 + 500),
        BigNumber.from(300 + 300),
      ])
    })

    it('Check depositBatch event', async function () {
      const [id, amounts] = depositBatchArg

      expect(id).to.equal(BigNumber.from(0))
      expect(amounts).to.eql([
        BigNumber.from(100 + 200 + 100),
        BigNumber.from(200 + 400 + 500),
        BigNumber.from(300 + 300)
      ])
    })

    it('Batch status is "Fired"', async function () {
      const nodeApp = this.l2.connect(this.nodeApp)
      const executedBatch = await nodeApp.depositBatches(executedBatchId)
      expect(executedBatch.status).to.equal(BatchLifeCycle.Fired)
    })

    it('Usdc is burnt', async function () {
      const usdc = this.usdc.connect(this.users[0])
      expect(await usdc.balanceOf(this.l2.address))
        .to.equal(balance.sub(2100))
    })

    it('Batch id is increased', async function () {
      const nodeApp = this.l2.connect(this.nodeApp)
      expect(await nodeApp.depositBatchId())
        .to.equal(executedBatchId + 1)
    })
  })

  describe('Layer2 gets deposit message via data tunnel', function () {
    let executedBatchId, currentBatchId, message

    before(async function () {
      const nodeApp = this.l2.connect(this.nodeApp)
      currentBatchId = Number((await nodeApp.depositBatchId())._hex)
      executedBatchId = currentBatchId - 1;

      message = encodeTunnelData({
        batchType: BatchType.Deposit,
        id: executedBatchId,
        tokenWeights: this.tokenWeights,
        amounts: [50, 80]
      })

      await nodeApp.mockProcessMessageFromRoot(message)
    })

    it('Batch gets updated from tunnel message', async function () {
      const nodeApp = this.l2.connect(this.nodeApp)
      const executedBatch = await nodeApp.depositBatches(executedBatchId)
      expect(executedBatch.status).to.equal(BatchLifeCycle.Processed)
    })

    it('Layer2 rejects invalid tunnel message', async function () {
      const nodeApp = this.l2.connect(this.nodeApp)
      const messageNotFired = encodeTunnelData({
        batchType: BatchType.Deposit,
        id: currentBatchId,
        tokenWeights: this.tokenWeights,
        amounts: [0, 0]
      })

      // rejects if sent twice
      await expect(nodeApp.mockProcessMessageFromRoot(message))
        .to.revertedWith('Batch not fired')

      // rejects if batch is not fired
      await expect(nodeApp.mockProcessMessageFromRoot(messageNotFired))
        .to.revertedWith('Batch not fired')
    })
  })

  describe('Distribute', function () {
    let executedBatchId, currentBatchId

    before(async function () {
      const nodeApp = this.l2.connect(this.nodeApp)
      currentBatchId = Number((await nodeApp.depositBatchId())._hex)
      executedBatchId = currentBatchId - 1
      await nodeApp.distribute(executedBatchId)
    })

    it('Check user token balance', async function () {
      const [alice, bob, carl] = this.users
      const idleRA = this.idleRA.connect(alice)
      const idleBY = this.idleBY.connect(alice)
      const depositSumPerDetf = [100 + 200 + 100, 200 + 400 + 500, 300 + 0 + 300]
      const ra = (depositSumPerDetf[0] * 0.1 + depositSumPerDetf[1] * 0.2 + depositSumPerDetf[2] * 0.1)
      const by = (depositSumPerDetf[0] * 0.2 + depositSumPerDetf[1] * 0.5 + depositSumPerDetf[2] * 0.3)

      expect(await idleRA.balanceOf(alice.address))
        .to.equal(BigNumber.from(Math.floor(50 * (100 * 0.1 + 200 * 0.2 + 300 * 0.1) / ra)))
      expect(await idleBY.balanceOf(alice.address))
        .to.equal(BigNumber.from(Math.floor(80 * (100 * 0.2 + 200 * 0.5 + 300 * 0.3) / by)))

      expect(await idleRA.balanceOf(bob.address))
        .to.equal(BigNumber.from(Math.floor(50 * (200 * 0.1 + 400 * 0.2) / ra)))
      expect(await idleBY.balanceOf(bob.address))
        .to.equal(BigNumber.from(Math.floor(80 * (200 * 0.2 + 400 * 0.5) / by)))

      expect(await idleRA.balanceOf(carl.address))
        .to.equal(BigNumber.from(Math.floor(50 * (100 * 0.1 + 500 * 0.2 + 300 * 0.1) / ra)))
      expect(await idleBY.balanceOf(carl.address))
        .to.equal(BigNumber.from(Math.floor(80 * (100 * 0.2 + 500 * 0.5 + 300 * 0.3) / by)))
    })

    it('Distribute rejects for invalid batch', async function () {
      const nodeApp = this.l2.connect(this.nodeApp)

      await expect(nodeApp.distribute(currentBatchId))
        .to.revertedWith('Can not distribute before batch is processed in L1')
      await expect(nodeApp.distribute(executedBatchId))
        .to.revertedWith('Can not distribute before batch is processed in L1')
    })
  })

  const tokenSellAmounts = {}

  describe('Sell token', function () {
    let balanceAliceRA, balanceAliceBY, balanceBobRA, balanceBobBY

    before(async function () {
      const [alice, bob] = this.users
      const aliceL2 = this.l2.connect(alice)
      const bobL2 = this.l2.connect(bob)
      const idleRA = this.idleRA.connect(alice)
      const idleBY = this.idleBY.connect(alice)
      
      balanceAliceRA = await idleRA.balanceOf(alice.address)
      balanceAliceBY = await idleBY.balanceOf(alice.address)
      balanceBobRA = await idleRA.balanceOf(bob.address)
      balanceBobBY = await idleBY.balanceOf(bob.address)

      await Promise.all([
        aliceL2.sell([2000, 0]),
        bobL2.sell([1000, 3000]),
        // more sell
        aliceL2.sell([0, 4000])
      ])
    })

    it('Tokens are transferred to sellers from layer 2', async function () {
      const [alice, bob] = this.users
      const idleRA = this.idleRA.connect(alice)
      const idleBY = this.idleBY.connect(alice)

      tokenSellAmounts.alice = {
        idleRA: Math.floor(Number(balanceAliceRA._hex) * 0.2),
        idleBY: Math.floor(Number(balanceAliceBY._hex) * 0.4)
      }
      tokenSellAmounts.bob = {
        idleRA: Math.floor(Number(balanceBobRA._hex) * 0.1),
        idleBY: Math.floor(Number(balanceBobBY._hex) * 0.3)
      }

      expect(await idleRA.balanceOf(alice.address))
        .to.equal(balanceAliceRA.sub(tokenSellAmounts.alice.idleRA))
      expect(await idleBY.balanceOf(alice.address))
        .to.equal(balanceAliceBY.sub(tokenSellAmounts.alice.idleBY))

      expect(await idleRA.balanceOf(bob.address))
        .to.equal(balanceBobRA.sub(tokenSellAmounts.bob.idleRA))
      expect(await idleBY.balanceOf(bob.address))
        .to.equal(balanceBobBY.sub(tokenSellAmounts.bob.idleBY))
    })

    it('Selling token with amount above balance is rejected', async function () {
      const alice = this.l2.connect(this.users[0])
      await expect(alice.sell([12000, 0]))
        .to.revertedWith('Sell percentage too large')
    })
  })

  describe('Execute sell batch', function () {
    let executedBatchId, balanceRA, balanceBY, tunnelArg, depositBatchArg

    before(async function () {
      const nodeApp = this.l2.connect(this.nodeApp)
      const idleRA = this.idleRA.connect(this.nodeApp)
      const idleBY = this.idleBY.connect(this.nodeApp)
      const events = getEventArgs(nodeApp, ['MessageSent', 'SellTokenBatch'])

      executedBatchId = await nodeApp.sellBatchId()
      balanceRA = await idleRA.balanceOf(this.l2.address)
      balanceBY = await idleBY.balanceOf(this.l2.address)

      nodeApp.executeSellBatch()
      const args = await Promise.all(events)

      tunnelArg = args[0]
      depositBatchArg = args[1]
    })

    it('Check tunnel data', async function () {
      const [tunnelMessage] = tunnelArg
      const tunnelData = decodeTunnelData(tunnelMessage)

      expect(tunnelData.batchType).to.equal(BatchType.SellToken)
      expect(tunnelData.id).to.equal(executedBatchId)
      expect(tunnelData.tokenWeights).to.eql([])
      expect(tunnelData.amounts).to.eql([
        BigNumber.from(tokenSellAmounts.alice.idleRA + tokenSellAmounts.bob.idleRA),
        BigNumber.from(tokenSellAmounts.alice.idleBY + tokenSellAmounts.bob.idleBY)
      ])
    })

    it('Check SellTokenBatch event', async function () {
      const [id, data] = depositBatchArg

      expect(id).to.equal(BigNumber.from(0))
      expect(data).to.eql([
        BigNumber.from(tokenSellAmounts.alice.idleRA + tokenSellAmounts.bob.idleRA),
        BigNumber.from(tokenSellAmounts.alice.idleBY + tokenSellAmounts.bob.idleBY)
      ])
    })

    it('Batch status is "Fired"', async function () {
      const nodeApp = this.l2.connect(this.nodeApp)
      const executedBatch = await nodeApp.sellBatches(executedBatchId)
      expect(executedBatch.status).to.equal(BatchLifeCycle.Fired)
    })

    it('Tokens are burnt', async function () {
      const idleRA = this.idleRA.connect(this.users[0])
      const idleBY = this.idleBY.connect(this.users[0])

      expect(await idleRA.balanceOf(this.l2.address))
        .to.equal(balanceRA.sub(tokenSellAmounts.alice.idleRA + tokenSellAmounts.bob.idleRA))
      expect(await idleBY.balanceOf(this.l2.address))
        .to.equal(balanceBY.sub(tokenSellAmounts.alice.idleBY + tokenSellAmounts.bob.idleBY))
    })

    it('Batch id is increased', async function () {
      const nodeApp = this.l2.connect(this.nodeApp)
      expect(await nodeApp.sellBatchId())
        .to.equal(executedBatchId + 1)
    })
  })

  describe('Layer2 gets sell message via data tunnel', function () {
    let executedBatchId, currentBatchId, message

    before(async function () {
      const nodeApp = this.l2.connect(this.nodeApp)
      currentBatchId = Number((await nodeApp.sellBatchId())._hex)
      executedBatchId = currentBatchId - 1;

      message = encodeTunnelData({
        batchType: BatchType.SellToken,
        id: executedBatchId,
        tokenWeights: [],
        amounts: [300, 200]
      })

      await nodeApp.mockProcessMessageFromRoot(message)
    })

    it('Batch gets updated from tunnel message', async function () {
      const nodeApp = this.l2.connect(this.nodeApp)
      const executedBatch = await nodeApp.sellBatches(executedBatchId)
      expect(executedBatch.status).to.equal(BatchLifeCycle.Processed)
    })
  })

  describe('Retrieve', function () {
    let executedBatchId, currentBatchId
    let aliceBalance, bobBalance, carlBalance
    let aliceDeposit, bobDeposit, carlDeposit

    before(async function () {
      const [alice, bob, carl] = this.users
      const nodeApp = this.l2.connect(this.nodeApp)
      const usdc = this.usdc.connect(alice)

      currentBatchId = Number((await nodeApp.sellBatchId())._hex)
      executedBatchId = currentBatchId - 1

      aliceBalance = await usdc.balanceOf(alice.address)
      bobBalance = await usdc.balanceOf(bob.address)
      carlBalance = await usdc.balanceOf(carl.address)

      aliceDeposit = await nodeApp.depositPerUser(alice.address)
      bobDeposit = await nodeApp.depositPerUser(bob.address)
      carlDeposit = await nodeApp.depositPerUser(carl.address)

      const sellAmountRA = tokenSellAmounts.alice.idleRA + tokenSellAmounts.bob.idleRA
      const sellAmountBY = tokenSellAmounts.alice.idleBY + tokenSellAmounts.bob.idleBY

      aliceRetrieved =
        Math.floor(300 * tokenSellAmounts.alice.idleRA / sellAmountRA) +
        Math.floor(200 * tokenSellAmounts.alice.idleBY / sellAmountBY)
      bobRetrieved =
        Math.floor(300 * tokenSellAmounts.bob.idleRA / sellAmountRA) +
        Math.floor(200 * tokenSellAmounts.bob.idleBY / sellAmountBY)

      await nodeApp.retrieve(executedBatchId)
    })

    it('Check user usdc balance', async function () {
      const [alice, bob, carl] = this.users
      const idle = this.usdc.connect(alice)

      expect(await idle.balanceOf(alice.address))
        .to.equal(aliceBalance.add(aliceRetrieved))
      expect(await idle.balanceOf(bob.address))
        .to.equal(bobBalance.add(bobRetrieved))
      expect(await idle.balanceOf(carl.address))
        .to.equal(carlBalance)
    })

    it('Check depositPerUser', async function () {
      const [alice, bob, carl] = this.users
      const l2 = this.l2.connect(alice)

      expect(await l2.depositPerUser(alice.address))
        .to.equal(aliceDeposit.sub(aliceRetrieved))
      expect(await l2.depositPerUser(bob.address))
        .to.equal(bobDeposit.sub(bobRetrieved))
      expect(await l2.depositPerUser(carl.address))
        .to.equal(carlDeposit)
    })

    it('Retrieve rejects for invalid batch', async function () {
      const nodeApp = this.l2.connect(this.nodeApp)
      await expect(nodeApp.retrieve(currentBatchId))
        .to.revertedWith('Can not retrieve usdc before batch is processed in L1')
      await expect(nodeApp.retrieve(executedBatchId))
        .to.revertedWith('Can not retrieve usdc before batch is processed in L1')
    })
  })
})
