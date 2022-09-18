/**
 * @type import('hardhat/config').HardhatUserConfig
 */
 require("@nomiclabs/hardhat-ethers");
 require("@nomiclabs/hardhat-truffle5");
 require("@nomiclabs/hardhat-etherscan");
 require('@openzeppelin/hardhat-upgrades');
 require("solidity-coverage");
 require('dotenv').config()
 
 module.exports = {
   solidity: {
    version: "0.8.4",
    settings: {
      optimizer: {
        enabled: true
      }
    }
   },
   networks: {
     goerli: {
       url: `https://goerli.infura.io/v3/${process.env.INFURA_KEY}`,
       accounts: [`0x${process.env.PRIVATE_KEY}`]
     },
     mumbai: {
       url: `https://rpc-mumbai.maticvigil.com`,
       accounts: [`0x${process.env.PRIVATE_KEY}`]
     }
   },
   etherscan: {
     apiKey: process.env.ETHERSCAN_KEY
   },
 };
 