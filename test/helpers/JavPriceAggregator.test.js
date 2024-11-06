const { expect } = require("chai");
const { ethers, upgrades } = require("hardhat");
const helpers = require("@nomicfoundation/hardhat-toolbox/network-helpers");

const { ADMIN_ERROR, MANAGER_ERROR } = require("../common/constanst");

describe("JavPriceAggregator contract", () => {
    let hhJavPriceAggregator;
    let owner;
    let bot;
    let addr2;
    let addr3;

    before(async () => {
        const JavPriceAggregator = await ethers.getContractFactory(
            "contracts/helpers/JavPriceAggregator.sol:JavPriceAggregator",
        );
        [owner, bot, addr2, addr3, ...addrs] = await ethers.getSigners();

        hhJavPriceAggregator = await upgrades.deployProxy(
            JavPriceAggregator,
            [
                1, // _priceUpdateFee,
                [owner.address], // _allowedSigners_
            ],
            {
                initializer: "initialize",
            },
        );
    });

    describe("Deployment", () => {
        it("Should set the right owner address", async () => {
            await expect(await hhJavPriceAggregator.owner()).to.equal(owner.address);
        });

        it("Should set the right admin address", async () => {
            await expect(await hhJavPriceAggregator.adminAddress()).to.equal(owner.address);
        });

        it("Should set the _paused status", async () => {
            await expect(await hhJavPriceAggregator.paused()).to.equal(false);
        });
    });

    describe("Transactions", () => {
        it("Should revert when set pause", async () => {
            await expect(hhJavPriceAggregator.connect(bot).pause()).to.be.revertedWith(
                MANAGER_ERROR,
            );
        });

        it("Should set pause", async () => {
            await hhJavPriceAggregator.pause();

            await expect(await hhJavPriceAggregator.paused()).to.equal(true);
        });

        it("Should revert when set unpause", async () => {
            await expect(hhJavPriceAggregator.connect(bot).unpause()).to.be.revertedWith(
                MANAGER_ERROR,
            );
        });

        it("Should set unpause", async () => {
            await hhJavPriceAggregator.unpause();

            await expect(await hhJavPriceAggregator.paused()).to.equal(false);
        });

        it("Should revert when set the admin address", async () => {
            await expect(
                hhJavPriceAggregator.connect(bot).setAdminAddress(owner.address),
            ).to.be.revertedWith(ADMIN_ERROR);
        });

        it("Should set the admin address", async () => {
            await hhJavPriceAggregator.setAdminAddress(owner.address);

            await expect(await hhJavPriceAggregator.adminAddress()).to.equal(owner.address);
        });

        it("Should revert when addAllowedSigner", async () => {
            await expect(
                hhJavPriceAggregator.connect(bot).addAllowedSigner(owner.address),
            ).to.be.revertedWith(ADMIN_ERROR);
        });

        it("Should addAllowedSigner", async () => {
            await hhJavPriceAggregator.addAllowedSigner(
                "0x0000000000000000000000000000000000000000",
            );
        });

        it("Should revert when removeAllowedSigner", async () => {
            await expect(
                hhJavPriceAggregator.connect(bot).removeAllowedSigner(owner.address),
            ).to.be.revertedWith(ADMIN_ERROR);
        });

        it("Should removeAllowedSigner", async () => {
            await hhJavPriceAggregator.removeAllowedSigner(
                "0x0000000000000000000000000000000000000000",
            );
        });

        it("Should revert when setPriceUpdateFee", async () => {
            await expect(hhJavPriceAggregator.connect(bot).setPriceUpdateFee(1)).to.be.revertedWith(
                ADMIN_ERROR,
            );
        });

        it("Should setPriceUpdateFee", async () => {
            const fee = 2;
            await hhJavPriceAggregator.setPriceUpdateFee(fee);

            await expect(await hhJavPriceAggregator.priceUpdateFee()).to.equal(fee);
        });

        it("Should revert when updatePriceFeeds - invalid data length", async () => {
            const data = ethers.hexlify(ethers.toUtf8Bytes("Example data"));
            await expect(
                hhJavPriceAggregator.connect(bot).updatePriceFeeds([data], {
                    value: 5,
                }),
            ).to.be.revertedWith("JavPriceAggregator: invalid data length");
        });

        it("Should revert when updatePriceFeeds - invalid signature", async () => {
            const id = "0x49f6b65cb1de6b10eaf75e7c03ca029c306d0357e91b5311b175084a5ad55688";
            const price = 1000;
            const conf = 500;
            const expo = -2;
            const publishTime = 123456;

            const AbiCoder = new ethers.AbiCoder();
            const updatePriceInfo = AbiCoder.encode(
                ["bytes32", "int64", "uint64", "int32", "uint64"],
                [id, price, conf, expo, publishTime],
            );
            const messageHash = ethers.keccak256(updatePriceInfo);
            const signature = await bot.signMessage(ethers.getBytes(messageHash));
            const signedData = ethers.concat([signature, updatePriceInfo]);
            await expect(
                hhJavPriceAggregator.connect(bot).updatePriceFeeds([signedData], {
                    value: 5,
                }),
            ).to.be.revertedWith("JavPriceAggregator: Invalid signature");
        });

        it("Should updatePriceFeeds", async () => {
            const id = "0x49f6b65cb1de6b10eaf75e7c03ca029c306d0357e91b5311b175084a5ad55688";
            const price = 1000;
            const conf = 500;
            const expo = -2;
            const publishTime = 123456;

            const AbiCoder = new ethers.AbiCoder();
            const updatePriceInfo = AbiCoder.encode(
                ["bytes32", "int64", "uint64", "int32", "uint64"],
                [id, price, conf, expo, publishTime],
            );
            const messageHash = ethers.keccak256(updatePriceInfo);
            const signature = await owner.signMessage(ethers.getBytes(messageHash));
            const signedData = ethers.concat([signature, updatePriceInfo]);
            await hhJavPriceAggregator.connect(bot).updatePriceFeeds([signedData], { value: 5 });

            const priceInfo = await hhJavPriceAggregator.getPrice(id);

            await expect(priceInfo.price).to.equal(price);
            await expect(priceInfo.conf).to.equal(conf);
            await expect(priceInfo.expo).to.equal(expo);
            await expect(priceInfo.publishTime).to.equal(publishTime);
        });
    });
});
