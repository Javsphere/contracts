const { expect } = require("chai");
const { ethers, upgrades } = require("hardhat");
const helpers = require("@nomicfoundation/hardhat-toolbox/network-helpers");
const { deployTokenFixture } = require("../../common/mocks");

describe("MultiSigWallet contract", () => {
    let hhMultiSigWallet;
    let owner;
    let addr1;
    let addr2;
    let addr3;
    let erc20Token;
    let owners;
    let required;

    before(async () => {
        const multiSigWallet = await ethers.getContractFactory("MultiSigWallet");
        [owner, addr1, addr2, addr3, ...addrs] = await ethers.getSigners();
        erc20Token = await helpers.loadFixture(deployTokenFixture);

        owners = [addr1.address, addr2.address];
        required = 2;
        hhMultiSigWallet = await multiSigWallet.deploy(owners, required);
        await owner.sendTransaction({
            to: hhMultiSigWallet.target,
            value: ethers.parseEther("5"),
        });
    });

    describe("Deployment", () => {
        it("Should set the right owners", async () => {
            await expect(await hhMultiSigWallet.owners(0)).to.equal(owners[0]);
            await expect(await hhMultiSigWallet.owners(1)).to.equal(owners[1]);
        });

        it("Should set the right required", async () => {
            await expect(await hhMultiSigWallet.required()).to.equal(required);
        });
    });

    describe("Transactions", () => {
        it("Should revert when submitTransaction not owner", async () => {
            const to = erc20Token.target;
            const value = ethers.parseEther("0.0005");
            const data = ethers.encodeBytes32String("test_bytes");

            await expect(
                hhMultiSigWallet.connect(addr3).submitTransaction(to, value, data),
            ).to.be.revertedWith("MultiSigWallet: owner does not exist");
        });

        it("Should submitTransaction", async () => {
            const amount = ethers.parseEther("3");
            const to = erc20Token.target;
            const value = BigInt(0);
            const data = erc20Token.interface.encodeFunctionData("mint", [addr1.address, amount]);
            const trxId = await hhMultiSigWallet.transactionCount();

            await hhMultiSigWallet.connect(addr1).submitTransaction(to, value, data);

            const trx = await hhMultiSigWallet.transactions(trxId);

            await expect(await hhMultiSigWallet.transactionCount()).to.be.equal(trxId + BigInt(1));
            await expect(trx.to).to.be.equal(to);
            await expect(trx.value).to.be.equal(value);
            await expect(trx.data).to.be.equal(data);
            await expect(trx.executed).to.be.equal(false);
            await expect(await hhMultiSigWallet.getConfirmationCount(trxId)).to.be.equal(1);
        });

        it("Should getConfirmationCount", async () => {
            const trxId = (await hhMultiSigWallet.transactionCount()) - BigInt(1);

            await expect(await hhMultiSigWallet.getConfirmationCount(trxId)).to.be.equal(1);
        });

        it("Should revert when confirmTransaction not owner", async () => {
            const trxId = (await hhMultiSigWallet.transactionCount()) - BigInt(1);

            await expect(
                hhMultiSigWallet.connect(addr3).confirmTransaction(trxId),
            ).to.be.revertedWith("MultiSigWallet: owner does not exist");
        });

        it("Should revert when confirmTransaction trx not exist", async () => {
            await expect(hhMultiSigWallet.connect(addr1).confirmTransaction(5)).to.be.revertedWith(
                "MultiSigWallet: transaction does not exist",
            );
        });

        it("Should revert when confirmTransaction already confirmed", async () => {
            const trxId = (await hhMultiSigWallet.transactionCount()) - BigInt(1);

            await expect(
                hhMultiSigWallet.connect(addr1).confirmTransaction(trxId),
            ).to.be.revertedWith("MultiSigWallet: transaction already confirmed");
        });

        it("Should revert when executeTransaction transaction not confirmed", async () => {
            const trxId = (await hhMultiSigWallet.transactionCount()) - BigInt(1);

            await expect(
                hhMultiSigWallet.connect(addr1).executeTransaction(trxId),
            ).to.be.revertedWith("MultiSigWallet: transaction not confirmed");
        });

        it("Should confirmTransaction", async () => {
            const trxId = (await hhMultiSigWallet.transactionCount()) - BigInt(1);
            const prevConfirmations = await hhMultiSigWallet.getConfirmationCount(trxId);

            await hhMultiSigWallet.connect(addr2).confirmTransaction(trxId);

            await expect(await hhMultiSigWallet.getConfirmationCount(trxId)).to.be.equal(
                prevConfirmations + BigInt(1),
            );
        });

        it("Should revert when executeTransaction not owner", async () => {
            const trxId = (await hhMultiSigWallet.transactionCount()) - BigInt(1);

            await expect(
                hhMultiSigWallet.connect(addr3).executeTransaction(trxId),
            ).to.be.revertedWith("MultiSigWallet: owner does not exist");
        });

        it("Should executeTransaction", async () => {
            const trxId = (await hhMultiSigWallet.transactionCount()) - BigInt(1);
            const addr1BalanceBefore = await erc20Token.balanceOf(addr1.address);
            const amount = ethers.parseEther("3");

            await hhMultiSigWallet.connect(addr1).executeTransaction(trxId);

            const trx = await hhMultiSigWallet.transactions(trxId);

            await expect(trx.executed).to.be.equal(true);
            await expect(await erc20Token.balanceOf(addr1.address)).to.be.equal(
                addr1BalanceBefore + amount,
            );
        });

        it("Should revokeConfirmation", async () => {
            const data = erc20Token.interface.encodeFunctionData("mint", [
                addr1.address,
                ethers.parseEther("3"),
            ]);
            await hhMultiSigWallet.connect(addr1).submitTransaction(erc20Token.target, 0, data);
            const trxId = (await hhMultiSigWallet.transactionCount()) - BigInt(1);
            await hhMultiSigWallet.connect(addr2).confirmTransaction(trxId);
            const prevConfirmations = await hhMultiSigWallet.getConfirmationCount(trxId);

            await hhMultiSigWallet.connect(addr2).revokeConfirmation(trxId);

            await expect(await hhMultiSigWallet.getConfirmationCount(trxId)).to.be.equal(
                prevConfirmations - BigInt(1),
            );
        });

        it("Should getTransactionIds with executed", async () => {
            const ids = await hhMultiSigWallet.getTransactionIds(0, 2, true, true);
            await expect(ids.length).to.be.equal(2);
        });

        it("Should getTransactionIds without executed", async () => {
            const ids = await hhMultiSigWallet.getTransactionIds(0, 2, true, false);
            await expect(ids.length).to.be.equal(2);
        });

        it("Should getTransactionCount with executed", async () => {
            await expect(await hhMultiSigWallet.getTransactionCount(true, true)).to.be.equal(2);
        });

        it("Should getTransactionCount without executed", async () => {
            await expect(await hhMultiSigWallet.getTransactionCount(true, false)).to.be.equal(1);
        });

        it("Should getConfirmations", async () => {
            const trxId = (await hhMultiSigWallet.transactionCount()) - BigInt(2);

            const confirmations = await hhMultiSigWallet.getConfirmations(trxId);

            await expect(confirmations.length).to.be.equal(2);
        });

        it("Should getOwners", async () => {
            const walletOwners = await hhMultiSigWallet.getOwners();

            await expect(walletOwners[0]).to.equal(owners[0]);
            await expect(walletOwners[1]).to.equal(owners[1]);
        });
    });
});
