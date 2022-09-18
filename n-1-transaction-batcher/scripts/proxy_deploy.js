async function main() {
    const Proxy = await ethers.getContractFactory("UnstructuredProxy");
    const proxy = await Proxy.deploy();
  
    console.log("Proxy contract deployed to:", proxy.address);
  }
  
  main()
    .then(() => process.exit(0))
    .catch(error => {
      console.error(error);
      process.exit(1);
    });