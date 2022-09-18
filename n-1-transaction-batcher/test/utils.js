const { ethers } = require('hardhat')

module.exports.DETFType = {
  Conservative: 0,
  Balanced: 1,
  Growth: 2,
  Aggressive: 3
}

module.exports.BatchLifeCycle = {
  None: 0,
  Fired: 1,
  Processed: 2,
  Over: 3
}

module.exports.BatchType = {
  Deposit: 0,
  SellToken: 1
}

module.exports.getEventArgs = (contract, event) => {
  const waitForEvent = e =>
    new Promise(resolve =>
      contract.on(
        e,
        (...args) => resolve(args)
      )
    )

  if (Array.isArray(event)) {
    return event.map(waitForEvent)
  } else {
    return waitForEvent(event)
  }
}
  

module.exports.getERC20Token = ({ address, name }) => ([address, name])
