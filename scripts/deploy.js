const { ethers } = require("hardhat");
const {
  setBalance,
  time,
} = require("@nomicfoundation/hardhat-network-helpers");
const utils = ethers.utils;
const provider = ethers.provider;
require("dotenv").config();
let tx, receipt; //transactions
let blastedFactory, blastedRouter;
let deployer, caller, user, randomUser;
const WETH = '0x4200000000000000000000000000000000000023';

const setAddresses = async () => {
  console.log("\n*** SETTING ADDRESSES ***");
   [deployer] = await ethers.getSigners();
  // deployer = await ethers.getImpersonatedSigner(
  //   "0xD8a566C83616BBF2B3762439B1C30bCBa10ee885"
  // );
  console.log(`Deployer: ${deployer.address}`);
};

const deployContracts = async () => {
  console.log("\n*** DEPLOYING CONTRACTS ***");
  const BlastedFactory = await ethers.getContractFactory(
    "BlastedFactory",
    deployer
  );
  blastedFactory = await BlastedFactory.deploy(deployer.address);
  await blastedFactory.deployed();
  console.log(`blastedFactory deployed to ${blastedFactory.address}`);

  const BlastedRouter = await ethers.getContractFactory(
    "BlastedRouter",
    deployer
  );
  blastedRouter = await BlastedRouter.deploy(blastedFactory.address, WETH);
  await blastedRouter.deployed();
  console.log(`blastedRouter deployed to ${blastedRouter.address}`);
};

const fetchInitCodePairHash = async () => {
  console.log("\n*** FETCHING INIT_CODE_PAIR_HASH ***");
  const initCodePairHash = await blastedFactory.INIT_CODE_PAIR_HASH();
  console.log(`INIT_CODE_PAIR_HASH: ${initCodePairHash}`);
};


const main = async () => {
  await setAddresses();
  await deployContracts();
  await fetchInitCodePairHash();
 
};

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });