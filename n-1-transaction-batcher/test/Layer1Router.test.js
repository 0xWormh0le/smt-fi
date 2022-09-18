const chai = require("chai")
const { solidity } = require("ethereum-waffle")
const { ethers } = require("hardhat")
const { BigNumber } = require("ethers")
const {
  encode: encodeTunnelData,
  decode: decodeTunnelData,
  hash: hashTunnelData } = require('./abiEncoder/TunnelData')
const { BatchType, getEventArgs } = require("./utils")

chai.use(solidity)

describe("Layer1Router", function () {
  before("works", async function () {
    const Router = await ethers.getContractFactory("Layer1Router")
    const Layer2Batcher = await ethers.getContractFactory("Layer2Batcher")
    const Usdc = await ethers.getContractFactory("Erc20Mock")
    const RootChainManager = await ethers.getContractFactory("RootChainManager")
    const Predicate = await ethers.getContractFactory("Erc20Mock") // dummy contract
    const IdleToken = await ethers.getContractFactory("IdleTokenV3Mock")
    const IdleProtocol = await ethers.getContractFactory("Idle")
    const StateSender = await ethers.getContractFactory("StateSenderMock")

    this.usdc = await Usdc.deploy('USDC', 'USDC')
    this.usdcL2 = await Usdc.deploy('USDC', 'USDC')
    this.layer2batcher = await Layer2Batcher.deploy(this.usdcL2.address)
    this.router = await Router.deploy()
    this.rootChainManager = await RootChainManager.deploy()
    this.predicate = await Predicate.deploy('Predicate', 'Predicate')
    this.idleRA = await IdleToken.deploy(this.usdc.address)
    this.idleBY = await IdleToken.deploy(this.usdc.address)
    this.idleRAProtocol = await IdleProtocol.deploy(this.idleRA.address)
    this.idleBYProtocol = await IdleProtocol.deploy(this.idleBY.address)
    this.stateSender = await StateSender.deploy()

    await Promise.all([
      this.router.deployed(),
      this.usdc.deployed(),
      this.layer2batcher.deployed(),
      this.predicate.deployed(),
      this.rootChainManager.deployed(),
      this.idleRA.deployed(),
      this.idleBY.deployed(),
      this.idleRAProtocol.deployed(),
      this.idleBYProtocol.deployed()
    ])

    this.users = await ethers.getSigners()

    const [alice] = this.users
    const router = this.router.connect(alice)
    Promise.all([
      router.init(
        this.layer2batcher.address,
        this.rootChainManager.address,
        this.predicate.address
      ),
      router.setStateSender(this.stateSender.address)
    ])

    const usdc = this.usdc.connect(alice)
    const idleRA = this.idleRA.connect(alice)
    const idleBY = this.idleBY.connect(alice)

    await Promise.all([
      usdc.mint(9999),
      idleRA.mint(9999),
      idleBY.mint(9999)
    ])

    await Promise.all([
      usdc.transfer(this.router.address, 999),
      usdc.transfer(this.idleRA.address, 999),
      usdc.transfer(this.idleBY.address, 999),
      idleRA.transfer(this.router.address, 999),
      idleBY.transfer(this.router.address, 999),
    ])
  })

  describe('Set detf, protocol and token weights', async function () {
    before(async function () {
      const alice = this.users[0]
      const router = this.router.connect(alice)

      await router.addDETF('Conservative')
      await router.addDETF('Balanced')
      await router.addDETF('Growth')

      await router.addProtocol('Idle RA', this.idleRAProtocol.address)
      await router.addProtocol('Idle BY', this.idleBYProtocol.address)
    })

    it('Set token weights', async function () {
      const alice = this.users[0]
      const router = this.router.connect(alice)

      await router.setTokenWeights(0, [1000, 2000]) // conservative
      await router.setTokenWeights(1, [2000, 5000]) // balanced
      await router.setTokenWeights(2, [1000, 3000]) // growth
    })

    it('Setting token weights fails if detf arg is invalid', async function () {
      const alice = this.users[0]
      const router = this.router.connect(alice)

      await expect(router.setTokenWeights(3, [1000, 2000]))
        .to.revertedWith('Invalid detf index')
    })

    it('Setting token weights fails if weights arg length mismatches with protocol length', async function () {
      const alice = this.users[0]
      const router = this.router.connect(alice)

      await expect(router.setTokenWeights(0, [1000, 2000, 3000]))
        .to.revertedWith('Invalid weights length')
    })
  })

  describe('Deposit', async function () {
    let tunnelArg, mintArg

    before(async function () {
      const alice = this.users[0]
      const router = this.router.connect(alice)
      const events = getEventArgs(router, ['MessageSent', 'Minted'])
      const tunnelData = {
        batchType: BatchType.Deposit,
        id: 123,
        tokenWeights: [],
        amounts: [50, 80, 60]
      }
      await router.mockProcessMessageFromChild(encodeTunnelData(tunnelData))
      router.deposit(hashTunnelData(tunnelData))

      const args = await Promise.all(events)

      tunnelArg = args[0]
      mintArg = args[1]
    })

    it('Check message sent to data tunnel', async function () {
      const [message] = tunnelArg
      const data = decodeTunnelData(message)

      expect(data.id).to.equal(123)
      expect(data.batchType).to.equal(BatchType.Deposit)
      expect(data.amounts).to.eql([
        BigNumber.from(Math.floor(50 * 0.1 + 80 * 0.2 + 60 * 0.1)),
        BigNumber.from(Math.floor(50 * 0.2 + 80 * 0.5 + 60 * 0.3))
      ])
      expect(data.tokenWeights).to.eql([
        [BigNumber.from(1000), BigNumber.from(2000)],
        [BigNumber.from(2000), BigNumber.from(5000)],
        [BigNumber.from(1000), BigNumber.from(3000)]
      ])
    })

    it('Check Minted event', async function () {
      const [id, amounts] = mintArg
      expect(id).to.equal(123)
      expect(amounts).to.eql([
        BigNumber.from(Math.floor(50 * 0.1 + 80 * 0.2 + 60 * 0.1)),
        BigNumber.from(Math.floor(50 * 0.2 + 80 * 0.5 + 60 * 0.3))
      ])
    })
  })

  describe('Sell', async function () {
    let tunnelArg, redeemArg

    before(async function () {
      const alice = this.users[0]
      const router = this.router.connect(alice)
      const events = getEventArgs(router, ['MessageSent', 'Redeemed'])
      const tunnelData = {
        batchType: BatchType.SellToken,
        id: 234,
        tokenWeights: [],
        amounts: [70, 90]
      }
      await router.mockProcessMessageFromChild(encodeTunnelData(tunnelData))
      router.sell(hashTunnelData(tunnelData))

      const args = await Promise.all(events)

      tunnelArg = args[0]
      redeemArg = args[1]
    })

    it('Check message sent to data tunnel', async function () {
      const [message] = tunnelArg
      const data = decodeTunnelData(message)

      expect(data.id).to.equal(234)
      expect(data.batchType).to.equal(BatchType.SellToken)
      expect(data.amounts).to.eql([
        BigNumber.from(70),
        BigNumber.from(90)
      ])
    })

    it('Check Redeemed event', async function () {
      const [id, amounts] = redeemArg
      expect(id).to.equal(234)
      expect(amounts).to.eql([
        BigNumber.from(70),
        BigNumber.from(90)
      ])
    })
  })
})
