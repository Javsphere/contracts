const { ethers, upgrades } = require("hardhat");
const UniswapV2FactoryArtifact = require("@uniswap/v2-core/build/UniswapV2Factory.json");
const UniswapV3FactoryArtifact = require("@uniswap/v3-core/artifacts/contracts/UniswapV3Factory.sol/UniswapV3Factory.json");
const UniswapV2PairArtifact = require("@uniswap/v2-core/build/UniswapV2Pair.json");
const UniswapV2Router02Artifact = require("@uniswap/v2-periphery/build/UniswapV2Router02.json");
const UniswapV3RouterArtifact = require("@uniswap/v3-periphery/artifacts/contracts/SwapRouter.sol/SwapRouter.json");
const UniswapV3PoolArtifact = require("@uniswap/v3-core/artifacts/contracts/UniswapV3Pool.sol/UniswapV3Pool.json");
const NonfungiblePositionManagerArtifact = require("@uniswap/v3-periphery/artifacts/contracts/NonfungiblePositionManager.sol/NonfungiblePositionManager.json");
const WETH9Artifact = require("@uniswap/v2-periphery/build/WETH9.json");

async function deployTokenFixture() {
    const erc20ContractFactory = await ethers.getContractFactory("ERC20Mock");
    const erc20Token = await erc20ContractFactory.deploy("MockERC20", "MOCK", 18);
    await erc20Token.waitForDeployment();
    return erc20Token;
}

async function deployToken2Fixture() {
    const erc20ContractFactory = await ethers.getContractFactory("ERC20Mock");
    const erc20Token = await erc20ContractFactory.deploy("Mock2ERC20", "MOCK2", 18);
    await erc20Token.waitForDeployment();
    return erc20Token;
}

async function createMockWETH() {
    // deploy mock WETH
    const WETH9 = await ethers.getContractFactory(WETH9Artifact.abi, WETH9Artifact.bytecode);

    const WETH = await WETH9.deploy();
    await WETH.waitForDeployment();
    return WETH;
}

async function createUniswapFactory() {
    const signers = await ethers.getSigners();
    const feeOwner = signers[0];
    // deploy uni factory
    const UniswapV2Factory = await ethers.getContractFactory(
        UniswapV2FactoryArtifact.abi,
        UniswapV2FactoryArtifact.bytecode,
    );
    const uniswapV2Factory = await UniswapV2Factory.deploy(feeOwner.address);
    await uniswapV2Factory.waitForDeployment();
    return uniswapV2Factory;
}

async function createUniswapV3Factory() {
    // deploy uni factory
    const Uniswap32Factory = await ethers.getContractFactory(
        UniswapV3FactoryArtifact.abi,
        UniswapV3FactoryArtifact.bytecode,
    );
    const uniswapV3Factory = await Uniswap32Factory.deploy();
    await uniswapV3Factory.waitForDeployment();
    return uniswapV3Factory;
}

async function createUniswapRouter02(uniswapV2Factory, WETH) {
    // deploy uni router
    const UniswapV2Router02 = await ethers.getContractFactory(
        UniswapV2Router02Artifact.abi,
        UniswapV2Router02Artifact.bytecode,
    );
    const uniswapV2Router02 = await UniswapV2Router02.deploy(uniswapV2Factory.target, WETH.target);
    await uniswapV2Router02.waitForDeployment();
    return uniswapV2Router02;
}

async function createUniswapV3Router(uniswapV3Factory, WETH) {
    // deploy uni router
    const UniswapV2Router02 = await ethers.getContractFactory(
        UniswapV3RouterArtifact.abi,
        UniswapV3RouterArtifact.bytecode,
    );
    const uniswapV3Router = await UniswapV2Router02.deploy(uniswapV3Factory.target, WETH.target);
    await uniswapV3Router.waitForDeployment();
    return uniswapV3Router;
}

async function createNonfungiblePositionManager(uniswapV3Factory, WETH) {
    // deploy uni nonfungiblePositionManager
    const NonfungiblePositionManager = await ethers.getContractFactory(
        NonfungiblePositionManagerArtifact.abi,
        NonfungiblePositionManagerArtifact.bytecode,
    );
    const nonfungiblePositionManager = await NonfungiblePositionManager.deploy(
        uniswapV3Factory.target,
        WETH.target,
        WETH.target,
    );
    await nonfungiblePositionManager.waitForDeployment();
    return nonfungiblePositionManager;
}

async function deployUniswapV2Fixture() {
    const WETH = await createMockWETH();
    const uniswapV2Factory = await createUniswapFactory();
    const uniswapV2Router02 = await createUniswapRouter02(uniswapV2Factory, WETH);

    // for event decoding
    const UniswapV2PairContract = await ethers.getContractFactory(
        UniswapV2PairArtifact.abi,
        UniswapV2PairArtifact.bytecode,
    );
    return [WETH, uniswapV2Factory, uniswapV2Router02, UniswapV2PairContract];
}

async function deployUniswapV3Fixture() {
    const WETH = await createMockWETH();
    const uniswapV3Factory = await createUniswapV3Factory();
    const uniswapV3Router = await createUniswapV3Router(uniswapV3Factory, WETH);
    const nonfungiblePositionManager = await createNonfungiblePositionManager(
        uniswapV3Factory,
        WETH,
    );

    const uniswapV3Pool = await ethers.getContractFactory(
        UniswapV3PoolArtifact.abi,
        UniswapV3PoolArtifact.bytecode,
    );

    return [WETH, uniswapV3Factory, uniswapV3Router, uniswapV3Pool, nonfungiblePositionManager];
}

async function deployStateRelayerFixture() {
    const stateRelayerFactory = await ethers.getContractFactory("StateRelayer");
    const stateRelayer = await stateRelayerFactory.deploy();
    await stateRelayer.waitForDeployment();
    return stateRelayer;
}

async function deployInfinityPassFixture() {
    const infinityPassContractFactory = await ethers.getContractFactory("InfinityPass");
    [owner, ...addrs] = await ethers.getSigners();
    const infinityPass = await upgrades.deployProxy(infinityPassContractFactory, [], {
        initializer: "initialize",
    });
    await infinityPass.waitForDeployment();
    return infinityPass;
}

module.exports = {
    deployTokenFixture,
    deployToken2Fixture,
    deployUniswapV2Fixture,
    deployUniswapV3Fixture,
    deployStateRelayerFixture,
    deployInfinityPassFixture,
};
