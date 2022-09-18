const { ethers } = require('hardhat')

const type = ethers.utils.ParamType.from({
  "components": [
    {
      "internalType": "uint256",
      "name": "batchType",
      "type": "uint8"
    },
    {
      "internalType": "uint256",
      "name": "id",
      "type": "uint256"
    },
    {
      "internalType": "uint256[][]",
      "name": "tokenWeights",
      "type": "uint256[][]"
    },
    {
      "internalType": "uint256[]",
      "name": "amounts",
      "type": "uint256[]"
    }
  ],
  "indexed": false,
  "internalType": "struct TunnelData",
  "name": "amount",
  "type": "tuple"
})

module.exports.encode = ({ batchType, id, tokenWeights, amounts }) =>
  ethers.utils.defaultAbiCoder.encode(
    [type],
    [[ batchType, id, tokenWeights, amounts ]]
  )

module.exports.decode = data =>
  ethers.utils.defaultAbiCoder.decode([type], data).amount

module.exports.hash = data => {
  const packed = ethers.utils.defaultAbiCoder.encode(
    ['uint', 'uint'],
    [data.id, data.batchType]
  )
  return ethers.utils.keccak256(packed)
}
