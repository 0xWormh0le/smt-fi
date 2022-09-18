const chai = require("chai")
const { solidity } = require("ethereum-waffle")
const { artifacts, ethers } = require("hardhat");

chai.use(solidity)

describe("Proxy", function () {
  it("works", async function () {
    const Proxy = await ethers.getContractFactory("UnstructuredProxy")
    const LogicV1 = await ethers.getContractFactory("LogicV1")
    const LogicV2 = await ethers.getContractFactory("LogicV2")
    const [alice, bob, carl] = await ethers.getSigners()

    const proxy = await Proxy.deploy()
    const logicV1 = await LogicV1.deploy()
    const logicV2 = await LogicV2.deploy()

    await proxy.deployed()
    await logicV1.deployed()
    await logicV2.deployed()
    
    await proxy.upgradeTo(logicV1.address)
    expect(await proxy.implementation())
      .to.equal(logicV1.address)
    
    const { abi: abiV1 } = await artifacts.readArtifact("LogicV1")
    const { abi: abiV2 } = await artifacts.readArtifact("LogicV2")

    let ProxyUpgraded = new ethers.Contract(proxy.address, abiV1, ethers.getDefaultProvider());
    let proxyUpgraded = await ProxyUpgraded.connect(alice)

    // check first logic contract
    await proxyUpgraded.set(3);
    await logicV2.setAnotherData(5);

    expect(await proxyUpgraded.data()).to.equal(3);

    // check transferProxyOwnership()
    await proxy.transferProxyOwnership(bob.address)
    await expect(proxy.upgradeTo(logicV2.address))
      .to.be.revertedWith("Not Proxy owner")

    // switch to new proxy owner bob
    const proxyWithBob = await proxy.connect(bob)
    await proxyWithBob.upgradeTo(logicV2.address)

    // connect second version of logic contract
    ProxyUpgraded = new ethers.Contract(proxy.address, abiV2, ethers.getDefaultProvider());
    proxyUpgraded = await ProxyUpgraded.connect(alice)
    proxyUpgraded.initialize()
    
    // check ownable
    const proxyUpgradedWithBob = await ProxyUpgraded.connect(bob)
    await expect(proxyUpgradedWithBob.setAnotherData(3))
      .to.be.revertedWith("Ownable: caller is not the owner")
    proxyUpgraded.setAnotherData(3)

    // check transfer ownership of logic contract

    const proxyUpgradedWithCarl = await ProxyUpgraded.connect(carl)
    await proxyUpgraded.transferOwnership(carl.address)
    await proxyUpgradedWithCarl.setAnotherData(3);

    // check renounce ownership
    await proxyUpgradedWithCarl.renounceOwnership()
    await expect(proxyUpgradedWithCarl.setAnotherData(3))
      .to.be.revertedWith('Ownable: caller is not the owner')

    // check if storage is kept after upgrade

    expect(await proxyUpgraded.data()).to.equal(3);

    // check new work flow in the upgraded contract
    
    await proxyUpgraded.set(4);
    expect(await proxyUpgraded.data()).to.equal(4 * 4);
  })
})
