const { expect } = require("chai");
const { ethers } = require("hardhat");
const helpers = require("@nomicfoundation/hardhat-toolbox/network-helpers");
const { deployTokenFixture } = require("./common/mocks");

describe("DutchAuction contract", () => {
    let hhDutchAuction;
    let owner;
    let addr1;
    let addr2;
    let admin;
    let nonZeroAddress;
    let erc20Token;
    let startDate;
    let endDate;
    let startPrice;
    let endPrice;
    let adminError;

    async function getSpentGas(tx) {
        const receipt = await tx.wait();
        return receipt.gasUsed * receipt.gasPrice;
    }

    before(async () => {
        const dutchAuction = await ethers.getContractFactory("DutchAuction");
        [owner, addr1, addr2, admin, ...addrs] = await ethers.getSigners();
        nonZeroAddress = ethers.Wallet.createRandom().address;
        erc20Token = await helpers.loadFixture(deployTokenFixture);

        startDate = (await helpers.time.latest()) + 10;
        endDate = startDate + 100000;
        startPrice = ethers.parseEther("2");
        endPrice = ethers.parseEther("0.5");

        hhDutchAuction = await dutchAuction.deploy();

        await hhDutchAuction.initDutchAuction(
            owner.address,
            erc20Token.target,
            startDate,
            endDate,
            startPrice,
            endPrice,
        );

        adminError = "DutchAuction: only admin";
    });

    describe("Deployment", () => {
        it("Should set the right admin address", async () => {
            await expect(await hhDutchAuction.adminAddress()).to.equal(owner.address);
        });

        it("Should set the right token address", async () => {
            await expect(await hhDutchAuction.auctionToken()).to.equal(erc20Token.target);
        });

        it("Should set the right startDate", async () => {
            await expect(await hhDutchAuction.startDate()).to.equal(startDate);
        });

        it("Should set the right endDate", async () => {
            await expect(await hhDutchAuction.endDate()).to.equal(endDate);
        });

        it("Should set the right startPrice", async () => {
            await expect(await hhDutchAuction.startPrice()).to.equal(startPrice);
        });

        it("Should set the right minimumPrice", async () => {
            await expect(await hhDutchAuction.minimumPrice()).to.equal(endPrice);
        });

        it("Should set the right priceDrop", async () => {
            const priceDrop = (startPrice - endPrice) / BigInt(endDate - startDate);

            await expect(await hhDutchAuction.priceDrop()).to.equal(priceDrop);
        });

        it("Should mint tokens", async () => {
            const tokenAmounts = ethers.parseEther("25");

            await erc20Token.mint(hhDutchAuction.target, tokenAmounts);
            await expect(await erc20Token.balanceOf(hhDutchAuction.target)).to.equal(tokenAmounts);
        });
    });

    describe("Transactions", () => {
        it("Should revert when initDutchAuction", async () => {
            await expect(
                hhDutchAuction
                    .connect(addr1)
                    .initDutchAuction(nonZeroAddress, nonZeroAddress, 1, 2, 4, 1),
            ).to.be.revertedWith("DutchAuction: already initialised");
        });

        it("Should revert when set total tokens", async () => {
            await expect(hhDutchAuction.connect(addr1).setTotalTokens()).to.be.revertedWith(
                adminError,
            );
        });

        it("Should set total tokens", async () => {
            await hhDutchAuction.setTotalTokens();

            await expect(await hhDutchAuction.totalTokens()).to.equal(
                await erc20Token.balanceOf(hhDutchAuction.target),
            );
        });

        it("Should revert when claim - auction not ended", async () => {
            await expect(hhDutchAuction.connect(addr1).claim()).to.be.revertedWith(
                "DutchAuction: auction not ended",
            );
        });

        it("Should get clearingPrice block.timestamp <= startDate", async () => {
            await expect(await hhDutchAuction.clearingPrice()).to.equal(startPrice);
        });

        it("Should get clearingPrice", async () => {
            await helpers.time.increase(10);

            const priceDrop = await hhDutchAuction.priceDrop();
            const blockTimestamp = await helpers.time.latest();
            const elapsed = BigInt(blockTimestamp - startDate);
            const priceDiff = elapsed * priceDrop;

            await expect(await hhDutchAuction.clearingPrice()).to.equal(startPrice - priceDiff);
        });

        it("Should get tokensClaimable = 0", async () => {
            await expect(await hhDutchAuction.tokensClaimable()).to.equal(0);
        });

        it("Should get tokensRemaining - commitmentsTotal = 0", async () => {
            const tokenAmounts = ethers.parseEther("25");

            await expect(await hhDutchAuction.tokensRemaining()).to.equal(tokenAmounts);
        });

        it("Should placeBid", async () => {
            const bidValue = ethers.parseEther("1");

            await hhDutchAuction.connect(addr1).placeBid({
                value: bidValue,
            });

            await expect(await hhDutchAuction.commitments(addr1.address)).to.equal(bidValue);
        });

        it("Should get tokensRemaining - commitmentsTotal > 0", async () => {
            const tokenAmounts = ethers.parseEther("25");
            const totalCommitted = await hhDutchAuction.commitmentsTotal();
            const clearingPrice = await hhDutchAuction.clearingPrice();
            const _totalCommitted = (totalCommitted * ethers.parseEther("1")) / clearingPrice;

            await expect(await hhDutchAuction.tokensRemaining()).to.equal(
                tokenAmounts - _totalCommitted,
            );
        });

        it("Should placeBid - commitmentsTotal = totalTokens", async () => {
            await hhDutchAuction.connect(addr2).placeBid({
                value: ethers.parseEther("50"),
            });
        });

        it("Should get tokensRemaining - commitmentsTotal = totalTokens", async () => {
            await expect(await hhDutchAuction.tokensRemaining()).to.equal(0);
        });

        it("Should get tokensClaimable > 0", async () => {
            const clearingPrice = await hhDutchAuction.clearingPrice();
            const commitments = await hhDutchAuction.commitments(addr1.address);
            const _tokensClaimable = (commitments * ethers.parseEther("1")) / clearingPrice;

            await expect(await hhDutchAuction.connect(addr1).tokensClaimable()).to.equal(
                _tokensClaimable,
            );
        });

        it("Should revert when placeBid block.timestamp > endDate", async () => {
            await helpers.time.increase(100000);

            await expect(
                hhDutchAuction.connect(addr2).placeBid({
                    value: ethers.parseEther("1"),
                }),
            ).to.be.revertedWith("DutchAuction: Outside auction hours");
        });

        it("Should revert when finaliseAuction", async () => {
            await expect(hhDutchAuction.connect(addr1).finaliseAuction()).to.be.revertedWith(
                adminError,
            );
        });

        it("Should finaliseAuction", async () => {
            await hhDutchAuction.finaliseAuction();

            await expect(await hhDutchAuction.finalised()).to.equal(true);
        });

        it("Should revert when placeBid - finalised", async () => {
            await expect(
                hhDutchAuction.connect(addr2).placeBid({
                    value: ethers.parseEther("1"),
                }),
            ).to.be.revertedWith("DutchAuction: Auction was finalised");
        });

        it("Should claim", async () => {
            const amount = await hhDutchAuction.connect(addr1).tokensClaimable();

            await hhDutchAuction.connect(addr1).claim();

            await expect(await erc20Token.balanceOf(addr1.address)).to.equal(amount);
        });

        it("Should revert when withdraw adminError", async () => {
            await expect(
                hhDutchAuction
                    .connect(addr1)
                    .withdraw(erc20Token.target, ethers.parseEther("0.0005")),
            ).to.be.revertedWith(adminError);
        });

        it("Should revert when withdraw Invalid amount", async () => {
            await expect(
                hhDutchAuction.withdraw(erc20Token.target, ethers.parseEther("100")),
            ).to.be.revertedWith("DutchAuction: Invalid amount");
        });

        it("Should withdraw", async () => {
            const amount = ethers.parseEther("0.05");

            await hhDutchAuction.withdraw(erc20Token.target, amount);

            await expect(await erc20Token.balanceOf(owner.address)).to.equal(amount);
        });

        it("Should claim  - _isAuctionSuccessful = false", async () => {
            const dutchAuction = await ethers.getContractFactory("DutchAuction");
            const hhAuction = await dutchAuction.deploy();
            const _startDate = await helpers.time.latest();
            const _endDate = _startDate + 10;

            await hhAuction.initDutchAuction(
                owner.address,
                erc20Token.target,
                _startDate,
                _endDate,
                startPrice,
                endPrice,
            );

            const tokenAmounts = ethers.parseEther("5");
            await erc20Token.mint(hhAuction.target, tokenAmounts);
            await hhAuction.setTotalTokens();
            await hhAuction.connect(addr2).placeBid({
                value: ethers.parseEther("1"),
            });
            await helpers.time.increase(100);

            const amount = await hhAuction.commitments(addr2.address);
            const balanceBefore = await ethers.provider.getBalance(addr2.address);
            const tx = await hhAuction.connect(addr2).claim();
            const spentOnGas = await getSpentGas(tx);

            await expect(await ethers.provider.getBalance(addr2.address)).to.be.equal(
                balanceBefore + amount - spentOnGas,
            );
        });
    });
});
