const {expect} = require("chai");
const {ethers} = require("hardhat")


describe("MultiSignature contract", () => {
    let hhMultiSign;
    let owner;
    let addr1;
    let addr2;
    let signer1;
    let signer2;
    let signer3;


    before(async () => {
        const multiSign = await ethers.getContractFactory("MultiSignMock");
        [owner, addr1, addr2, signer1, signer2, signer3, ...addrs] = await ethers.getSigners();
        const nonZeroAddress = ethers.Wallet.createRandom().address;

        hhMultiSign = await multiSign.deploy();
        await hhMultiSign.initialize(2, [signer1.address, signer2.address, signer3.address]);


    });

    describe("Deployment", () => {
        it("Should set the right owner address", async () => {

            await expect(await hhMultiSign.owner()).to.equal(owner.address);
        });

        it("Should set the right minimumSignatures", async () => {
            await expect(await hhMultiSign.minimumSignatures()).to.equal(2);
        });

        it("Should set the right role for signers addresses", async () => {

            await expect(await hhMultiSign.hasRole(ethers.encodeBytes32String(""), signer1.address)).to.equal(true);
            await expect(await hhMultiSign.hasRole(ethers.encodeBytes32String(""), signer2.address)).to.equal(true);
            await expect(await hhMultiSign.hasRole(ethers.encodeBytes32String(""), signer3.address)).to.equal(true);
        });


    });

    describe("Transactions", () => {
        it("Should revert when signAction without necessary role", async () => {
            await expect(hhMultiSign.connect(addr1).signAction(ethers.encodeBytes32String(""))).to.be.reverted;

        });

        it("Should signAction ", async () => {
            const action = await hhMultiSign.INC_MIN_SIGN();
            const actionId = await hhMultiSign.actionId(action);

            await hhMultiSign.connect(signer1).signAction(action);

            await expect(await hhMultiSign.signatureUsedByAction(signer1.address, action, actionId)).to.equal(true);
            await expect(await hhMultiSign.signatures(action, actionId)).to.equal(1);
        });

        it("Should revert when already signAction", async () => {
            const action = await hhMultiSign.INC_MIN_SIGN();
            await expect(hhMultiSign.connect(signer1).signAction(action)).to.be.revertedWith(
                "MultiSignatureUpgradeable: No signatures left in this wallet."
            );

        });

        it("Should revert when increaseMinimumSignatures and < minimumSignatures", async () => {
            const action = await hhMultiSign.INC_MIN_SIGN();
            await expect(hhMultiSign.connect(signer1).signAction(action)).to.be.revertedWith(
                "MultiSignatureUpgradeable: No signatures left in this wallet."
            );

        });

        it("Should increaseMinimumSignatures", async () => {
            const action = await hhMultiSign.INC_MIN_SIGN();
            const actionId = await hhMultiSign.actionId(action);
            const minimumSignatures = await hhMultiSign.minimumSignatures();

            await hhMultiSign.connect(signer2).signAction(action);

            await hhMultiSign.connect(signer2).increaseMinimumSignatures();

            const newActionId = await hhMultiSign.actionId(action);

            await expect(await hhMultiSign.minimumSignatures()).to.be.equal(minimumSignatures + BigInt(1));
            await expect(newActionId).to.be.equal(actionId + BigInt(1));
            await expect(await hhMultiSign.signatures(action, newActionId)).to.be.equal(0);
            await expect(await hhMultiSign.signatureUsedByAction(signer2.address, action, newActionId)).to.be.equal(false);

        });

        it("Should grantRole", async () => {
            const action = await hhMultiSign.GRANT_ROLE();

            await hhMultiSign.connect(signer1).signAction(action);
            await hhMultiSign.connect(signer2).signAction(action);
            await hhMultiSign.connect(signer3).signAction(action);

            await hhMultiSign.connect(signer2).grantRole(ethers.encodeBytes32String(""), owner.address);


            await expect(await hhMultiSign.hasRole(ethers.encodeBytes32String(""), owner.address)).to.equal(true);
        });

        it("Should revokeRole", async () => {
            const action = await hhMultiSign.REVOKE_ROLE();

            await hhMultiSign.connect(signer1).signAction(action);
            await hhMultiSign.connect(signer2).signAction(action);
            await hhMultiSign.connect(signer3).signAction(action);

            await hhMultiSign.connect(signer2).revokeRole(ethers.encodeBytes32String(""), owner.address);


            await expect(await hhMultiSign.hasRole(ethers.encodeBytes32String(""), owner.address)).to.equal(false);
        });


    });
});