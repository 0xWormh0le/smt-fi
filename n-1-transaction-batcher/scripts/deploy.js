// async function main() {
//     const EthToMatic = await ethers.getContractFactory("InterLayerComm");
//     const transBlockChain = await EthToMatic.deploy(
//         "0x655f2166b0709cd575202630952d71e2bb0d61af",
//         "0xBbD7cBFA79faee899Eaf900F13C9065bF03B1A74",
//         "0xdD6596F2029e6233DEFfaCa316e6A95217d4Dc34"
//     );
  
//     console.log("Contract deployed to:", transBlockChain.address);
//   }
  
//   main()
//     .then(() => process.exit(0))
//     .catch(error => {
//       console.error(error);
//       process.exit(1);
//     });