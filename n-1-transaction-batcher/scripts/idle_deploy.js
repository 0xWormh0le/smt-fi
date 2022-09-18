async function main() {
    const IdleTokenV3 = await ethers.getContractFactory("IdleTokenV3", "0x0B27c5F47B7bF03ff3e9843bC5552E46D2528Da2", "0xaB90d6b05E9efef5f634a22Af81e793C133A3a4e");
    const idle = await IdleTokenV3.deploy();
  
    console.log("Idle contract deployed to:", idle.address);
  }
  
  main()
    .then(() => process.exit(0))
    .catch(error => {
      console.error(error);
      process.exit(1);
    });