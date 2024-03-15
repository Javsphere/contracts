const { ethers } = require("hardhat");
const UniswapV2FactoryArtifact = require("@uniswap/v2-core/build/UniswapV2Factory.json");
const UniswapV2PairArtifact = require("@uniswap/v2-core/build/UniswapV2Pair.json");
const UniswapV2Router02Artifact = require("@uniswap/v2-periphery/build/UniswapV2Router02.json");
const WETH9Artifact = require("@uniswap/v2-periphery/build/WETH9.json");

async function deployTokenFixture() {
    const erc20ContractFactory = await ethers.getContractFactory("ERC20Mock");
    const erc20Token = await erc20ContractFactory.deploy("MockERC20", "MOCK");
    await erc20Token.waitForDeployment();
    return erc20Token;
}

async function deployToken2Fixture() {
    const erc20ContractFactory = await ethers.getContractFactory("ERC20Mock");
    const erc20Token = await erc20ContractFactory.deploy("Mock2ERC20", "MOCK2");
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

async function deployUniswapFixture() {
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

async function deployStateRelayerFixture() {
    const stateRelayerFactory = await ethers.getContractFactory("StateRelayer");
    const stateRelayer = await stateRelayerFactory.deploy();
    await stateRelayer.waitForDeployment();
    return stateRelayer;
}

module.exports = {
    deployTokenFixture,
    deployToken2Fixture,
    deployUniswapFixture,
    deployStateRelayerFixture,
};
