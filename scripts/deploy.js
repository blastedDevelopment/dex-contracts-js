const { ethers } = require("hardhat");
const {
  setBalance,
  time,
} = require("@nomicfoundation/hardhat-network-helpers");
const utils = ethers.utils;
const provider = ethers.provider;
require("dotenv").config();
let tx, receipt; //transactions
let blastedFactory, blastedRouter, BlastToken;
let deployer, caller, user, randomUser;
const WETH = '0x4200000000000000000000000000000000000023';
const LiquidityAllocation = utils.parseEther("0.1");

const RebaseABI = require('./rebase.json');
const { factory } = require("typescript");

const WETHContract = new ethers.Contract(
  WETH,
  RebaseABI,
  provider
);


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
  blastedFactory = await BlastedFactory.deploy(deployer.address, deployer.address, deployer.address, deployer.address);
  await blastedFactory.deployed();
  console.log(`blastedFactory deployed to ${blastedFactory.address}`);

  const BlastedRouter = await ethers.getContractFactory(
    "BlastedRouter",
    deployer
  );
  blastedRouter = await BlastedRouter.deploy(blastedFactory.address, WETH);
  await blastedRouter.deployed();
  console.log(`blastedRouter deployed to ${blastedRouter.address}`);

  const BLAST = await ethers.getContractFactory(
    "BLAST",
    deployer
  );
  BlastToken = await BLAST.deploy();
  await BlastToken.deployed();
  console.log(`BlastToken deployed to ${BlastToken.address}`);
};


const setFeeTo = async () => {
  console.log("\n*** SETTING FEE ADDRESS ***");
  tx = await blastedFactory.setFeeTo(deployer.address);
  receipt = await tx.wait();
  console.log(`FEE RECIEVER SET`);
};
const addLiquidity = async () => {
  console.log('\n*** ADDING LIQUIDITY ***');
  const balanceBefore = await BlastToken.balanceOf(deployer.address);
  console.log("balanceBefore = ", balanceBefore)
  tx = await BlastToken.approve(blastedRouter.address, ethers.constants.MaxUint256);
  receipt = await tx.wait();
  console.log("approved called")

  tx = await blastedRouter.addLiquidityETH(
    BlastToken.address,
    balanceBefore,
    0,
    LiquidityAllocation,
    deployer.address,
    Math.floor(Date.now() / 1000 + 86400),
    { value: LiquidityAllocation
    }
  );
  receipt = await tx.wait();

  const balanceAfter = await BlastToken.balanceOf(deployer.address);
  console.log("balanceAfter = ", balanceAfter)
  console.log('\n*** LIQUIDITY ADDED ***');
};

const fetchInitCodePairHash = async () => {
  console.log("\n*** FETCHING INIT_CODE_PAIR_HASH ***");
  const initCodePairHash = await blastedFactory.INIT_CODE_PAIR_HASH();
  console.log(`INIT_CODE_PAIR_HASH: ${initCodePairHash}`);
};

const getClaimable = async () => {
  console.log('\n*** CHECKING CLAIMABLE AMOUNT ***');
  try {
    const pairAddress = await blastedFactory.getPair(BlastToken.address, WETH);
    console.log(`Pair Address: ${pairAddress}`);

    if (pairAddress !== ethers.constants.AddressZero) {
      const pairBalance = await BlastToken.balanceOf(pairAddress);
      console.log("Balance in Pair: ", pairBalance.toString());
      const configuration = await WETHContract.connect(deployer).getConfiguration(pairAddress);
      console.log("Pair WETH configuration.", configuration);
      const claimableBalance = await WETHContract.connect(deployer).getClaimableAmount(pairAddress);
      console.log("Claimable Balance: ", claimableBalance.toString());
    } else {
      console.log("No pair exists for the given tokens.");
    }
  } catch (error) {
    console.error("Error in getClaimable:", error);
  }
};


const main = async () => {
  await setAddresses();
  await deployContracts();
  await fetchInitCodePairHash();
  await setFeeTo();
  await addLiquidity();
  // await time.increase(31556926);
  // console.log("TIME INCREASED A YEAR")
  await getClaimable();


 
};

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });