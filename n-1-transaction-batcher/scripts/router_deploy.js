async function main() {
    const Layer1Router = await ethers.getContractFactory("Layer1Router");
    const router = await Layer1Router.deploy();
  
    console.log("Router contract deployed to:", router.address);
  }
  
  main()
    .then(() => process.exit(0))
    .catch(error => {
      console.error(error);
      process.exit(1);
    });