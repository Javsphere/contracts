const { expect } = require("chai");
const { ethers } = require("hardhat");
const { parseUnits } = ethers;
const helpers = require("@nomicfoundation/hardhat-toolbox/network-helpers");
const { deployTokenFixture, deployTermsAndConditionsFixture } = require("./common/mocks");
const { ADMIN_ERROR, OWNER_ERROR, MAX_UINT256 } = require("./common/constanst");
const { Wallet } = require("ethers");

describe("XVault contract", () => {
    const PRECISION_18 = parseUnits("1", 18);
    const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";

    const MAX_SUPPLY_INCREASE_DAILY_P = ethers.parseEther("50");
    const COMMENCEMENT_TIMESTAMP = 1742947200;
    const EPOCH_DURATION = 86400;
    const WITHDRAW_EPOCHS_LOCK = 3;
    const MAX_DAILY_ACC_PNL_DELTA = parseUnits("1", 17);

    const DEPOSIT_AMOUNT = parseUnits("50", 18);
    const WITHDRAW_AMOUNT = parseUnits("10", 18);
    const BASE_AMOUNT = parseUnits("50", 18);

    const USD_THRESHOLDS = [10, 30, 50];
    const BASE_FEES = [300, 500, 1000];
    const JAV_THRESHOLDS = [100, 500, 1000];
    const REDUCTION_FACTORS = [1000, 3000, 5000];
    const SELL_FEES = [500, 500, 500];

    const DEPOSIT_FEE_P = 500n; //1e4
    const WITHDRAW_FEE_P = 500n; //1e4
    const TOTAL_SUPPLY_INCREASE_P = 15000n; //1e4

    const ADDRESS_ZERO_ERROR = "AddressZero";
    const ABOVE_MAX_ERROR = "AboveMax";
    const INVALID_INPUT_LENGTH_ERROR = "InvalidInputLength";
    const ASSETS_OR_SHARES_ZERO_ERROR = "ValueZero";
    const AGREE_TO_TERMS_ERROR = "OnlyAgreedToTerms";
    const EXCEEDED_MAX_DEPOSIT_ERROR = "ERC4626ExceededMaxDeposit";
    const EXCEEDED_MAX_WITHDRAW_ERROR = "ERC4626ExceededMaxWithdraw";
    const NOT_ALLOWED_USER_WITHDRAW_REQUEST_ERROR = "NotAllowed";
    const MORE_THAN_POSSESS_WITHDRAW_REQUEST_ERROR = "AboveMax";
    const ONLY_TRADING_PNL_HANDLER_ALLOWED_ERROR = "OnlyTradingPnlHandler";
    const NOT_ENOUGH_ASSETS_ERROR = "NotEnoughAssets";
    const MAX_DAILY_PNL_ERROR = "MaxDailyPnl";
    const WILLING_TRANSFER_AMOUNT_IS_PENDING_ERROR = "PendingWithdrawal";
    const FUTURE_EPOCH_WITHDRAWAL_ERROR = "WrongIndex";
    const ZERO_SHARES_WITHDRAW_ERROR = "ZeroValue";

    let owner;
    let randomUser;
    let interactionUser1;
    let interactionUser2;
    let interactionUser3;
    let nonZeroAddress;
    let pnlHandler;
    let currentEpoch;

    let hhJavInfoAggregator;
    let javToken;
    let termsAndConditions;

    let hhXVault;

    let currentEpochDuration;
    let lastUpdateEpoch;

    async function deployJavInfoAggregator() {
        const javInfoAggregatorContractFactory = await ethers.getContractFactory(
            "JavInfoAggregatorMock",
        );
        const javInfoAggregator = await javInfoAggregatorContractFactory.deploy();
        await javInfoAggregator.waitForDeployment();
        return javInfoAggregator;
    }

    async function mintApproveJav(amount, user) {
        await javToken.mint(user, amount);
        await javToken.connect(user).approve(hhXVault.target, amount);
    }

    async function userDeposit(amount, user) {
        await mintApproveJav(amount, user);
        if (!(await termsAndConditions.hasAgreed(user))) {
            await termsAndConditions.connect(user).agreeToTerms();
        }
        await hhXVault.connect(user).deposit(amount, user.address);
    }

    async function makeWithdrawRequest(amount, user) {
        await userDeposit(amount, user);
        await hhXVault.connect(user).makeWithdrawRequest(amount, user.address);
    }

    async function makeWithDrawRequestWithFees(amount, user) {
        await userDeposit(amount, user);

        const precision = parseUnits("1", 4);
        await hhXVault
            .connect(user)
            .makeWithdrawRequest((amount * (10_000n - DEPOSIT_FEE_P)) / precision, user.address);
    }

    async function distributeRewards(amount, user) {
        await mintApproveJav(amount, user);
        await hhXVault.connect(user).distributeReward(0, amount);
    }

    async function resetFees() {
        await hhXVault.setBuyConfiguration([], []);
        await hhXVault.setJavAmountConfiguration([], []);
        await hhXVault.setSellFees([]);
    }

    async function updateEpochDuration(duration) {
        lastUpdateEpoch = getCurrentEpoch();
        currentEpochDuration = duration;
        await hhXVault.connect(owner).updateEpochDuration(duration);
    }

    async function skipEpochsDays(num) {
        await network.provider.send("evm_increaseTime", [num * 86400]);
        await network.provider.send("evm_mine");
    }

    async function skipEpochsHours(num) {
        await network.provider.send("evm_increaseTime", [num * 3600]);
        await network.provider.send("evm_mine");
    }

    function getCurrentEpoch() {
        const now = Math.floor(Date.now() / 1000);
        return lastUpdateEpoch + Math.floor((now - COMMENCEMENT_TIMESTAMP) / currentEpochDuration);
    }

    function getInitArgs() {
        return [
            {
                name: "LeverageX JAV",
                symbol: "xJAV",
            },
            {
                asset: javToken.target,
                pnlHandler: pnlHandler.address,
            },
            MAX_DAILY_ACC_PNL_DELTA,
            MAX_SUPPLY_INCREASE_DAILY_P,
            COMMENCEMENT_TIMESTAMP,
            EPOCH_DURATION,
            WITHDRAW_EPOCHS_LOCK,
        ];
    }

    beforeEach(async () => {
        [
            owner,
            randomUser,
            interactionUser1,
            interactionUser2,
            interactionUser3,
            pnlHandler,
            ...addrs
        ] = await ethers.getSigners();

        nonZeroAddress = Wallet.createRandom().address;

        currentEpochDuration = EPOCH_DURATION;
        lastUpdateEpoch = 0;
        currentEpoch = getCurrentEpoch();

        termsAndConditions = await helpers.loadFixture(deployTermsAndConditionsFixture);
        javToken = await helpers.loadFixture(deployTokenFixture);
        hhJavInfoAggregator = await helpers.loadFixture(deployJavInfoAggregator);

        const xVaultFactory = await ethers.getContractFactory("XVault", owner);
        hhXVault = await upgrades.deployProxy(xVaultFactory, getInitArgs(), {
            initializer: "initialize",
            kind: "uups",
            redeployImplementation: "always",
        });
        await hhXVault.waitForDeployment();

        await hhXVault.setTermsAndConditionsAddress(termsAndConditions.target);
        await hhXVault.setJavInfoAggregator(hhJavInfoAggregator.target);
        await hhXVault.setBuyConfiguration(BASE_FEES, USD_THRESHOLDS);
        await hhXVault.setJavAmountConfiguration(JAV_THRESHOLDS, REDUCTION_FACTORS);
        await hhXVault.setSellFees(SELL_FEES);
    });

    describe("Deployment", () => {
        it("Should set the right deployment params", async () => {
            expect(await hhXVault.pnlHandler()).to.be.eq(pnlHandler.address);
            expect(await hhXVault.maxDailyAccPnlDelta()).to.be.eq(MAX_DAILY_ACC_PNL_DELTA);
            expect(await hhXVault.maxSupplyIncreaseDailyP()).to.be.eq(MAX_SUPPLY_INCREASE_DAILY_P);
            expect(await hhXVault.commencementTimestamp()).to.be.eq(COMMENCEMENT_TIMESTAMP);
            expect(await hhXVault.epochDuration()).to.be.eq(EPOCH_DURATION);
            expect(await hhXVault.shareToAssetsPrice()).to.be.eq(PRECISION_18);
            expect(await hhXVault.withdrawEpochsLock()).to.be.eq(WITHDRAW_EPOCHS_LOCK);

            const [precision, precisionDelta] = await hhXVault.collateralConfig();
            expect(precision).to.be.eq(PRECISION_18);
            expect(precisionDelta).to.be.eq(1n);
        });
    });

    describe("Non-admin management interactions", () => {
        it("Should revert when updatePnlHandler", async () => {
            await expect(
                hhXVault.connect(randomUser).updatePnlHandler(nonZeroAddress),
            ).to.be.revertedWithCustomError(hhXVault, OWNER_ERROR);
        });

        it("Should revert when updateWithdrawEpochsLock", async () => {
            await expect(
                hhXVault.connect(randomUser).updateWithdrawEpochsLock(WITHDRAW_EPOCHS_LOCK),
            ).to.be.revertedWithCustomError(hhXVault, OWNER_ERROR);
        });

        it("Should revert when updateEpochDuration", async () => {
            await expect(
                hhXVault.connect(randomUser).updateEpochDuration(EPOCH_DURATION),
            ).to.be.revertedWithCustomError(hhXVault, OWNER_ERROR);
        });

        it("Should revert when updateMaxSupplyIncreaseDailyP", async () => {
            await expect(
                hhXVault
                    .connect(randomUser)
                    .updateMaxSupplyIncreaseDailyP(MAX_SUPPLY_INCREASE_DAILY_P),
            ).to.be.revertedWith(ADMIN_ERROR);
        });

        it("Should revert when setTermsAndConditionsAddress", async () => {
            await expect(
                hhXVault.connect(randomUser).setTermsAndConditionsAddress(nonZeroAddress),
            ).to.be.revertedWith(ADMIN_ERROR);
        });

        it("Should revert when setJavInfoAggregator", async () => {
            await expect(
                hhXVault.connect(randomUser).setJavInfoAggregator(nonZeroAddress),
            ).to.be.revertedWith(ADMIN_ERROR);
        });

        it("Should revert when setBuyConfiguration", async () => {
            await expect(
                hhXVault.connect(randomUser).setBuyConfiguration([], []),
            ).to.be.revertedWith(ADMIN_ERROR);
        });

        it("Should revert when setJavAmountConfiguration", async () => {
            await expect(
                hhXVault.connect(randomUser).setJavAmountConfiguration([], []),
            ).to.be.revertedWith(ADMIN_ERROR);
        });

        it("Should revert when setSellFees", async () => {
            await expect(hhXVault.connect(randomUser).setSellFees([])).to.be.revertedWith(
                ADMIN_ERROR,
            );
        });
    });

    describe("Admin incorrect input management interactions", () => {
        it("Should revert when updatePnlHandler with zero address", async () => {
            await expect(
                hhXVault.connect(owner).updatePnlHandler(ZERO_ADDRESS),
            ).to.be.revertedWithCustomError(hhXVault, ADDRESS_ZERO_ERROR);
        });

        it("Should revert when updateMaxSupplyIncreaseDailyP above max", async () => {
            await expect(
                hhXVault
                    .connect(owner)
                    .updateMaxSupplyIncreaseDailyP(MAX_SUPPLY_INCREASE_DAILY_P + 1n),
            ).to.be.revertedWithCustomError(hhXVault, ABOVE_MAX_ERROR);
        });

        it("Should revert when setTermsAndConditionsAddress with zero address", async () => {
            await expect(
                hhXVault.connect(owner).setTermsAndConditionsAddress(ZERO_ADDRESS),
            ).to.be.revertedWithCustomError(hhXVault, ADDRESS_ZERO_ERROR);
        });

        it("Should revert when setJavInfoAggregator with zero address", async () => {
            await expect(
                hhXVault.connect(owner).setJavInfoAggregator(ZERO_ADDRESS),
            ).to.be.revertedWithCustomError(hhXVault, ADDRESS_ZERO_ERROR);
        });

        it("Should revert when setBuyConfiguration with invalid input length", async () => {
            await expect(
                hhXVault.connect(owner).setBuyConfiguration([1], []),
            ).to.be.revertedWithCustomError(hhXVault, INVALID_INPUT_LENGTH_ERROR);
        });

        it("Should revert when setJavAmountConfiguration with invalid input length", async () => {
            await expect(
                hhXVault.connect(owner).setJavAmountConfiguration([1], []),
            ).to.be.revertedWithCustomError(hhXVault, INVALID_INPUT_LENGTH_ERROR);
        });

        it("Should revert when setSellFees with invalid input length", async () => {
            await hhXVault.connect(owner).setJavAmountConfiguration([1], [1]);

            await expect(hhXVault.connect(owner).setSellFees([])).to.be.revertedWithCustomError(
                hhXVault,
                INVALID_INPUT_LENGTH_ERROR,
            );
        });
    });

    describe("Admin management interactions", () => {
        it("Should updatePnlHandler and emit PnlHandlerUpdated", async () => {
            const newPnlHandlerAddress = Wallet.createRandom().address;

            await expect(hhXVault.connect(owner).updatePnlHandler(newPnlHandlerAddress))
                .to.emit(hhXVault, "PnlHandlerUpdated")
                .withArgs(newPnlHandlerAddress);

            expect(await hhXVault.pnlHandler()).to.be.eq(newPnlHandlerAddress);
        });

        it("Should updateWithdrawEpochsLock and emit UpdateWithdrawEpochsLock", async () => {
            const newWithdrawEpochsLock = 2;

            await expect(hhXVault.connect(owner).updateWithdrawEpochsLock(newWithdrawEpochsLock))
                .to.emit(hhXVault, "UpdateWithdrawEpochsLock")
                .withArgs(newWithdrawEpochsLock);

            expect(await hhXVault.withdrawEpochsLock()).to.be.eq(newWithdrawEpochsLock);
        });

        it("Should updateEpochDuration and emit UpdateEpochDuration", async () => {
            const newEpochDurationFirstUpdate = EPOCH_DURATION * 2; //2d

            lastUpdateEpoch = getCurrentEpoch();
            currentEpochDuration = newEpochDurationFirstUpdate;

            await expect(hhXVault.connect(owner).updateEpochDuration(newEpochDurationFirstUpdate))
                .to.emit(hhXVault, "UpdateEpochDuration")
                .withArgs(newEpochDurationFirstUpdate);

            expect(await hhXVault.lastUpdateEpoch()).to.be.eq(lastUpdateEpoch);
            expect(await hhXVault.epochDuration()).to.be.eq(currentEpochDuration);
            expect(await hhXVault.getCurrentEpoch()).to.be.eq(getCurrentEpoch());

            const newEpochDurationSecondUpdate = EPOCH_DURATION / 24; //1h

            lastUpdateEpoch = getCurrentEpoch();
            currentEpochDuration = newEpochDurationSecondUpdate;

            await expect(hhXVault.connect(owner).updateEpochDuration(newEpochDurationSecondUpdate))
                .to.emit(hhXVault, "UpdateEpochDuration")
                .withArgs(newEpochDurationSecondUpdate);

            expect(await hhXVault.lastUpdateEpoch()).to.be.eq(lastUpdateEpoch);
            expect(await hhXVault.epochDuration()).to.be.eq(currentEpochDuration);
            expect(await hhXVault.getCurrentEpoch()).to.be.eq(getCurrentEpoch());
        });

        it("Should updateMaxSupplyIncreaseDailyP and emit MaxSupplyIncreaseDailyPUpdated", async () => {
            const newMaxSupplyIncreaseDailyP = parseUnits("49", 18);

            await expect(
                hhXVault.connect(owner).updateMaxSupplyIncreaseDailyP(newMaxSupplyIncreaseDailyP),
            )
                .to.emit(hhXVault, "MaxSupplyIncreaseDailyPUpdated")
                .withArgs(newMaxSupplyIncreaseDailyP);

            expect(await hhXVault.maxSupplyIncreaseDailyP()).to.be.eq(newMaxSupplyIncreaseDailyP);
        });

        it("Should setTermsAndConditionsAddress and emit SetTermsAndConditionsAddress", async () => {
            const termsAndConditionsAddress = termsAndConditions.target;

            await expect(
                hhXVault.connect(owner).setTermsAndConditionsAddress(termsAndConditionsAddress),
            )
                .to.emit(hhXVault, "SetTermsAndConditionsAddress")
                .withArgs(termsAndConditionsAddress);

            expect(await hhXVault.termsAndConditionsAddress()).to.be.eq(termsAndConditionsAddress);
        });

        it("Should setJavInfoAggregator and emit SetJavInfoAggregator", async () => {
            await expect(hhXVault.connect(owner).setJavInfoAggregator(nonZeroAddress))
                .to.emit(hhXVault, "SetJavInfoAggregator")
                .withArgs(nonZeroAddress);

            expect(await hhXVault.javInfoAggregator()).to.be.eq(nonZeroAddress);
        });

        it("Should setBuyConfiguration and emit SetBuyConfiguration", async () => {
            const baseFees = [1n, 5n, 10n];
            const usdThresholds = [100n, 500n, 1000n];

            await expect(hhXVault.connect(owner).setBuyConfiguration(baseFees, usdThresholds))
                .to.emit(hhXVault, "SetBuyConfiguration")
                .withArgs(baseFees, usdThresholds);
        });

        it("Should setJavAmountConfiguration and emit SetJavAmountConfiguration", async () => {
            const javThresholds = [1000n, 5000n, 10000n];
            const reductionFactors = [1n, 5n, 10n];

            await expect(
                hhXVault.connect(owner).setJavAmountConfiguration(javThresholds, reductionFactors),
            )
                .to.emit(hhXVault, "SetJavAmountConfiguration")
                .withArgs(javThresholds, reductionFactors);
        });

        it("Should setSellFees and emit SetSellFees", async () => {
            const javThresholds = [1000n, 5000n, 10000n];
            const reductionFactors = [1n, 5n, 10n];

            const sellFees = [2n, 3n, 5n];

            await hhXVault
                .connect(owner)
                .setJavAmountConfiguration(javThresholds, reductionFactors);

            await expect(hhXVault.connect(owner).setSellFees(sellFees))
                .to.emit(hhXVault, "SetSellFees")
                .withArgs(sellFees);
        });
    });

    describe("Helper functions", () => {
        it("Should tryUpdateCurrentMaxSupply and emit CurrentMaxSupplyUpdated", async () => {
            const updatedMaxSupply = (DEPOSIT_AMOUNT * TOTAL_SUPPLY_INCREASE_P) / 10_000n; // 150%
            await resetFees();
            await userDeposit(DEPOSIT_AMOUNT, interactionUser1);
            await expect(hhXVault.tryUpdateCurrentMaxSupply())
                .to.emit(hhXVault, "CurrentMaxSupplyUpdated")
                .withArgs(updatedMaxSupply);

            await expect(hhXVault.tryUpdateCurrentMaxSupply()).to.not.emit(
                hhXVault,
                "CurrentMaxSupplyUpdated",
            );
        });

        it("Shoud tryResetDailyAccPnlDelta and emit DailyAccPnlDeltaReset", async () => {
            await expect(hhXVault.tryResetDailyAccPnlDelta()).to.emit(
                hhXVault,
                "DailyAccPnlDeltaReset",
            );
            await expect(hhXVault.tryResetDailyAccPnlDelta()).to.not.emit(
                hhXVault,
                "DailyAccPnlDeltaReset",
            );
        });

        it("Should scale variables correctly when accPnlPerToken > 0", async () => {
            await resetFees();
            await userDeposit(DEPOSIT_AMOUNT, interactionUser1);
            //100% volume of daily transfer available
            const sendAssetsAmount = (DEPOSIT_AMOUNT * MAX_DAILY_ACC_PNL_DELTA) / PRECISION_18;
            await hhXVault.connect(pnlHandler).sendAssets(0, sendAssetsAmount, interactionUser1);
            const totalLiabilityFirstSend = sendAssetsAmount;
            expect(await hhXVault.totalLiability()).to.be.eq(totalLiabilityFirstSend);

            let totalSupply = await hhXVault.totalSupply();
            await makeWithdrawRequest(DEPOSIT_AMOUNT / 2n, interactionUser1); //maxSupply constraint

            const totalLiabilityFirstDeposit =
                totalLiabilityFirstSend +
                ((DEPOSIT_AMOUNT / 2n) * totalLiabilityFirstSend) / totalSupply;

            expect(await hhXVault.totalLiability()).to.be.eq(totalLiabilityFirstDeposit);
            expect(await hhXVault.totalDeposited()).to.be.eq(DEPOSIT_AMOUNT + DEPOSIT_AMOUNT / 2n);

            const currentEpoch = getCurrentEpoch();
            const unlockEpoch = currentEpoch + WITHDRAW_EPOCHS_LOCK;

            await skipEpochsDays(WITHDRAW_EPOCHS_LOCK);

            totalSupply = await hhXVault.totalSupply();

            await hhXVault
                .connect(interactionUser1)
                .withdraw(unlockEpoch, interactionUser1, interactionUser1);

            const totalLiabilityFirstWithdraw =
                totalLiabilityFirstDeposit -
                ((DEPOSIT_AMOUNT / 2n) * totalLiabilityFirstDeposit) / totalSupply;

            expect(await hhXVault.totalLiability()).to.be.eq(totalLiabilityFirstWithdraw);
            expect(await hhXVault.totalDeposited()).to.be.eq(DEPOSIT_AMOUNT);
        });

        it("Should scale variables correctly when accPnlPerToken < 0", async () => {
            await resetFees();
            await userDeposit(DEPOSIT_AMOUNT, interactionUser1);
            const receiveAssetsAmount = (DEPOSIT_AMOUNT * MAX_DAILY_ACC_PNL_DELTA) / PRECISION_18;
            await mintApproveJav(BASE_AMOUNT, interactionUser2);

            await hhXVault
                .connect(interactionUser2)
                .receiveAssets(0, receiveAssetsAmount, interactionUser2);

            let currentAccPnl = await hhXVault.accPnlPerToken();

            let totalSupply = await hhXVault.totalSupply();
            await makeWithdrawRequest(DEPOSIT_AMOUNT / 2n, interactionUser1); //maxSupply constraint

            const accPnlFirstDeposit =
                (currentAccPnl * totalSupply) / (totalSupply + DEPOSIT_AMOUNT / 2n);

            expect(await hhXVault.accPnlPerToken()).to.be.eq(accPnlFirstDeposit);
            expect(await hhXVault.totalDeposited()).to.be.eq(DEPOSIT_AMOUNT + DEPOSIT_AMOUNT / 2n);

            const currentEpoch = getCurrentEpoch();
            const unlockEpoch = currentEpoch + WITHDRAW_EPOCHS_LOCK;

            await skipEpochsDays(WITHDRAW_EPOCHS_LOCK);

            totalSupply = await hhXVault.totalSupply();

            await hhXVault
                .connect(interactionUser1)
                .withdraw(unlockEpoch, interactionUser1, interactionUser1);

            const accPnlFirstWithdraw =
                (accPnlFirstDeposit * totalSupply) / (totalSupply - DEPOSIT_AMOUNT / 2n);

            expect(await hhXVault.accPnlPerToken()).to.be.eq(accPnlFirstWithdraw);
            expect(await hhXVault.totalDeposited()).to.be.eq(DEPOSIT_AMOUNT);
        });
    });

    describe("User deposit interactions", () => {
        it("Should revert when zero input for deposit", async () => {
            await expect(
                hhXVault.connect(interactionUser1).deposit(0, interactionUser1),
            ).to.be.revertedWithCustomError(hhXVault, ASSETS_OR_SHARES_ZERO_ERROR);
        });

        it("Should revert when has not agreed to terms", async () => {
            await expect(
                hhXVault.connect(interactionUser1).deposit(5, interactionUser1.address),
            ).to.be.revertedWithCustomError(hhXVault, AGREE_TO_TERMS_ERROR);
        });

        it("Should revert when maxDeposit exceeded", async () => {
            await resetFees();
            await userDeposit(DEPOSIT_AMOUNT, interactionUser1);
            await hhXVault.tryUpdateCurrentMaxSupply();
            await expect(userDeposit(DEPOSIT_AMOUNT, interactionUser1))
                .to.be.revertedWithCustomError(hhXVault, EXCEEDED_MAX_DEPOSIT_ERROR)
                .withArgs(
                    interactionUser1.address,
                    (DEPOSIT_AMOUNT * TOTAL_SUPPLY_INCREASE_P) / 10_000n - DEPOSIT_AMOUNT,
                    DEPOSIT_AMOUNT,
                );
        });

        it("Should deposit and emit Deposit", async () => {
            const precision = parseUnits("1", 4);
            await mintApproveJav(DEPOSIT_AMOUNT, interactionUser1);

            await termsAndConditions.connect(interactionUser1).agreeToTerms();
            await expect(
                hhXVault
                    .connect(interactionUser1)
                    .deposit(DEPOSIT_AMOUNT, interactionUser1.address),
            )
                .to.emit(hhXVault, "Deposit")
                .withArgs(
                    interactionUser1.address,
                    interactionUser1.address,
                    (DEPOSIT_AMOUNT * (10_000n - DEPOSIT_FEE_P)) / precision,
                    (DEPOSIT_AMOUNT * (10_000n - DEPOSIT_FEE_P)) / precision,
                );

            expect(await hhXVault.balanceOf(interactionUser1.address)).to.be.eq(
                (DEPOSIT_AMOUNT * (10_000n - DEPOSIT_FEE_P)) / precision,
            );

            expect(await hhXVault.totalAssets()).to.be.eq(
                (DEPOSIT_AMOUNT * (10_000n - DEPOSIT_FEE_P)) / precision,
            );

            expect(await javToken.balanceOf(interactionUser1)).to.be.eq(0);
        });

        it("Should deposit and emit Deposit with fees shift", async () => {
            //amount 30->29.55
            //base fees 500
            //3000*500 150 1,5 %
            const customBaseFees = [300, 500, 1000];
            const customUsdThresholds = [10, 30, 50];
            const customJavThresholds = [100, 500, 1500];
            const customReductionFactors = [1000, 3000, 5000];
            const feeP = 150n;
            const customDepositAmount = parseUnits("30", 18);
            const feeAmount = (customDepositAmount * feeP) / 10_000n;

            await hhXVault.setBuyConfiguration(customBaseFees, customUsdThresholds);
            await hhXVault.setJavAmountConfiguration(customJavThresholds, customReductionFactors);

            await mintApproveJav(customDepositAmount, interactionUser1);

            await termsAndConditions.connect(interactionUser1).agreeToTerms();
            await expect(
                hhXVault.connect(interactionUser1).deposit(customDepositAmount, interactionUser1),
            )
                .to.emit(hhXVault, "Deposit")
                .withArgs(
                    interactionUser1,
                    interactionUser1,
                    customDepositAmount - feeAmount,
                    customDepositAmount - feeAmount,
                );

            expect(await hhXVault.balanceOf(interactionUser1)).to.be.eq(
                customDepositAmount - feeAmount,
            );

            expect(await hhXVault.totalAssets()).to.be.eq(customDepositAmount - feeAmount);

            expect(await javToken.balanceOf(interactionUser1)).to.be.eq(0);
        });
    });

    describe("Withdraw requests interactions", () => {
        it("Should revert when makeWithdrawRequest with not allowed user", async () => {
            await resetFees();
            await userDeposit(DEPOSIT_AMOUNT, interactionUser1);
            await hhXVault.tryUpdateCurrentMaxSupply();

            await expect(
                hhXVault
                    .connect(interactionUser2)
                    .makeWithdrawRequest(WITHDRAW_AMOUNT, interactionUser1.address),
            ).to.be.revertedWithCustomError(hhXVault, NOT_ALLOWED_USER_WITHDRAW_REQUEST_ERROR);

            await hhXVault
                .connect(interactionUser1)
                .approve(interactionUser2, WITHDRAW_AMOUNT / 2n);

            await expect(
                hhXVault
                    .connect(interactionUser2)
                    .makeWithdrawRequest(WITHDRAW_AMOUNT, interactionUser1.address),
            ).to.be.revertedWithCustomError(hhXVault, NOT_ALLOWED_USER_WITHDRAW_REQUEST_ERROR);
        });

        it("Should revert when makeWithdrawRequest when withdraw value in pending", async () => {
            await resetFees();
            await userDeposit(DEPOSIT_AMOUNT, interactionUser1);
            await userDeposit(DEPOSIT_AMOUNT, interactionUser1);
            await hhXVault.tryUpdateCurrentMaxSupply();

            await hhXVault
                .connect(interactionUser1)
                .makeWithdrawRequest(DEPOSIT_AMOUNT, interactionUser1.address);

            await expect(
                hhXVault
                    .connect(interactionUser1)
                    .makeWithdrawRequest(2n * DEPOSIT_AMOUNT, interactionUser1.address),
            ).to.be.revertedWithCustomError(hhXVault, MORE_THAN_POSSESS_WITHDRAW_REQUEST_ERROR);
        });

        it("Should revert when makeWithdrawRequest when withdraw more than possess", async () => {
            await resetFees();
            await userDeposit(DEPOSIT_AMOUNT, interactionUser1);
            await userDeposit(DEPOSIT_AMOUNT, interactionUser2);
            await hhXVault.tryUpdateCurrentMaxSupply();

            await expect(
                hhXVault
                    .connect(interactionUser1)
                    .makeWithdrawRequest(
                        DEPOSIT_AMOUNT + 1n * PRECISION_18,
                        interactionUser1.address,
                    ),
            ).to.be.revertedWithCustomError(hhXVault, EXCEEDED_MAX_WITHDRAW_ERROR);
        });

        it("Should makeWithdrawRequest and emit WithdrawRequested", async () => {
            await userDeposit(DEPOSIT_AMOUNT, interactionUser1);
            await hhXVault.tryUpdateCurrentMaxSupply();

            await expect(
                hhXVault
                    .connect(interactionUser1)
                    .makeWithdrawRequest(WITHDRAW_AMOUNT, interactionUser1.address),
            )
                .to.emit(hhXVault, "WithdrawRequested")
                .withArgs(
                    interactionUser1.address,
                    interactionUser1.address,
                    WITHDRAW_AMOUNT,
                    currentEpoch,
                    currentEpoch + WITHDRAW_EPOCHS_LOCK,
                );

            expect(
                await hhXVault.withdrawRequests(
                    interactionUser1.address,
                    currentEpoch + WITHDRAW_EPOCHS_LOCK,
                ),
            ).to.be.eq(WITHDRAW_AMOUNT);
        });

        it("Should revert when cancelWithdrawRequest with 0 shares pending", async () => {
            await resetFees();

            await expect(
                hhXVault
                    .connect(interactionUser2)
                    .cancelWithdrawRequest(
                        interactionUser1.address,
                        currentEpoch + WITHDRAW_EPOCHS_LOCK,
                    ), //
            ).to.be.revertedWithCustomError(hhXVault, ZERO_SHARES_WITHDRAW_ERROR);
        });

        it("Should revert when cancelWithdrawRequest with not allowed user", async () => {
            await resetFees();
            await makeWithdrawRequest(WITHDRAW_AMOUNT, interactionUser1);
            await hhXVault.tryUpdateCurrentMaxSupply();

            await expect(
                hhXVault
                    .connect(interactionUser2)
                    .cancelWithdrawRequest(
                        interactionUser1.address,
                        currentEpoch + WITHDRAW_EPOCHS_LOCK,
                    ),
            ).to.be.revertedWithCustomError(hhXVault, NOT_ALLOWED_USER_WITHDRAW_REQUEST_ERROR);
        });

        it("Should revert when cancelWithdrawRequest with not enough allowances user", async () => {
            await resetFees();
            await makeWithdrawRequest(WITHDRAW_AMOUNT, interactionUser1);

            await hhXVault
                .connect(interactionUser1)
                .approve(interactionUser2, WITHDRAW_AMOUNT / 2n);

            await expect(
                hhXVault
                    .connect(interactionUser2)
                    .cancelWithdrawRequest(
                        interactionUser1.address,
                        currentEpoch + WITHDRAW_EPOCHS_LOCK,
                    ),
            ).to.be.revertedWithCustomError(hhXVault, NOT_ALLOWED_USER_WITHDRAW_REQUEST_ERROR);
        });

        it("Should cancelWithdrawRequest and emit WithdrawCanceled", async () => {
            await resetFees();
            await makeWithdrawRequest(WITHDRAW_AMOUNT, interactionUser1);

            await expect(
                hhXVault
                    .connect(interactionUser1)
                    .cancelWithdrawRequest(
                        interactionUser1.address,
                        currentEpoch + WITHDRAW_EPOCHS_LOCK,
                    ),
            )
                .to.emit(hhXVault, "WithdrawCanceled")
                .withArgs(
                    interactionUser1.address,
                    interactionUser1.address,
                    WITHDRAW_AMOUNT,
                    currentEpoch,
                    currentEpoch + WITHDRAW_EPOCHS_LOCK,
                );

            expect(
                await hhXVault.withdrawRequests(
                    interactionUser1.address,
                    currentEpoch + WITHDRAW_EPOCHS_LOCK,
                ),
            ).to.be.eq(0);
        });
    });

    describe("User withdraw interactions", () => {
        it("Should revert when has not agreed to terms", async () => {
            await expect(
                hhXVault
                    .connect(interactionUser1)
                    .withdraw(5, interactionUser1.address, interactionUser1.address),
            ).to.be.revertedWithCustomError(hhXVault, AGREE_TO_TERMS_ERROR);
        });

        it("Should revert when future epoch", async () => {
            await resetFees();
            await makeWithdrawRequest(DEPOSIT_AMOUNT, interactionUser1);
            await hhXVault.tryUpdateCurrentMaxSupply();
            await expect(
                hhXVault
                    .connect(interactionUser1)
                    .withdraw(
                        getCurrentEpoch() + WITHDRAW_EPOCHS_LOCK,
                        interactionUser1.address,
                        interactionUser1.address,
                    ),
            ).to.be.revertedWithCustomError(hhXVault, FUTURE_EPOCH_WITHDRAWAL_ERROR);
        });

        it("Should revert when zero shares", async () => {
            await termsAndConditions.connect(interactionUser1).agreeToTerms();
            await expect(
                hhXVault
                    .connect(interactionUser1)
                    .withdraw(
                        getCurrentEpoch(),
                        interactionUser1.address,
                        interactionUser1.address,
                    ),
            ).to.be.revertedWithCustomError(hhXVault, ZERO_SHARES_WITHDRAW_ERROR);
        });

        it("Should withdraw and emit Withdraw", async () => {
            const precision = parseUnits("1", 4);
            const assetsAfterDepositFees = (DEPOSIT_AMOUNT * (10_000n - DEPOSIT_FEE_P)) / precision;
            const assetsAfterWithdrawFees =
                (assetsAfterDepositFees * (10_000n - WITHDRAW_FEE_P)) / precision;
            const currentEpoch = getCurrentEpoch();

            await makeWithDrawRequestWithFees(DEPOSIT_AMOUNT, interactionUser1);

            await skipEpochsDays(WITHDRAW_EPOCHS_LOCK);

            await expect(
                hhXVault
                    .connect(interactionUser1)
                    .withdraw(
                        currentEpoch + WITHDRAW_EPOCHS_LOCK,
                        interactionUser1.address,
                        interactionUser1.address,
                    ),
            )
                .to.emit(hhXVault, "Withdraw")
                .withArgs(
                    interactionUser1.address,
                    interactionUser1.address,
                    interactionUser1.address,
                    assetsAfterWithdrawFees,
                    assetsAfterDepositFees, //shares 1:1
                );

            expect(
                await hhXVault.withdrawRequests(
                    interactionUser1.address,
                    currentEpoch + WITHDRAW_EPOCHS_LOCK,
                ),
            ).to.be.eq(0);

            expect(await hhXVault.balanceOf(interactionUser1.address)).to.be.eq(0);

            expect(await hhXVault.totalAssets()).to.be.eq(0);

            expect(await javToken.balanceOf(interactionUser1.address)).to.be.eq(
                assetsAfterWithdrawFees,
            );
        });

        it("Should withdraw and emit Withdraw with fees shift", async () => {
            const currentEpoch = getCurrentEpoch();

            await resetFees();
            await makeWithdrawRequest(DEPOSIT_AMOUNT, interactionUser1);

            await skipEpochsDays(WITHDRAW_EPOCHS_LOCK);

            const customJavThresholds = [100, 500, 1500];
            const customReductionFactors = [1000, 3000, 5000];
            const customSellFees = [250, 500, 1000];

            await hhXVault.setJavAmountConfiguration(customJavThresholds, customReductionFactors);
            await hhXVault.setSellFees(customSellFees);

            const feeP = 500n;
            const feeAmount = (DEPOSIT_AMOUNT * feeP) / 10_000n;

            const assetsWithdrawnWithFees = DEPOSIT_AMOUNT - feeAmount;

            await expect(
                hhXVault
                    .connect(interactionUser1)
                    .withdraw(
                        currentEpoch + WITHDRAW_EPOCHS_LOCK,
                        interactionUser1,
                        interactionUser1,
                    ),
            )
                .to.emit(hhXVault, "Withdraw")
                .withArgs(
                    interactionUser1,
                    interactionUser1,
                    interactionUser1,
                    assetsWithdrawnWithFees,
                    DEPOSIT_AMOUNT,
                );

            expect(
                await hhXVault.withdrawRequests(
                    interactionUser1.address,
                    currentEpoch + WITHDRAW_EPOCHS_LOCK,
                ),
            ).to.be.eq(0);

            expect(await hhXVault.balanceOf(interactionUser1.address)).to.be.eq(0);

            expect(await hhXVault.totalAssets()).to.be.eq(0);

            expect(await javToken.balanceOf(interactionUser1)).to.be.eq(assetsWithdrawnWithFees);
        });
    });
    //10% of vault volume is operable per day
    describe("Assets handling interactions", () => {
        it("Should revert when sendAssets caller not pnlHandler", async () => {
            await expect(
                hhXVault
                    .connect(interactionUser2)
                    .sendAssets(0, BASE_AMOUNT, interactionUser2.address),
            ).to.be.revertedWithCustomError(hhXVault, ONLY_TRADING_PNL_HANDLER_ALLOWED_ERROR);
        });

        it("Should revert when sendAssets with not enough assets ", async () => {
            await userDeposit(DEPOSIT_AMOUNT, interactionUser1);

            await expect(
                hhXVault.connect(pnlHandler).sendAssets(0, BASE_AMOUNT, interactionUser2.address),
            ).to.be.revertedWithCustomError(hhXVault, NOT_ENOUGH_ASSETS_ERROR);
        });

        it("Should revert when sendAssets amount above max daily acc pnl", async () => {
            await resetFees();
            await userDeposit(DEPOSIT_AMOUNT, interactionUser1);

            //10% of vault assets + something
            const amountToExceedMaxDailyAccPnlDelta =
                (DEPOSIT_AMOUNT * MAX_DAILY_ACC_PNL_DELTA) / PRECISION_18 + 1n * 10n ** 17n;

            await expect(
                hhXVault
                    .connect(pnlHandler)
                    .sendAssets(0, amountToExceedMaxDailyAccPnlDelta, interactionUser2.address),
            ).to.be.revertedWithCustomError(hhXVault, MAX_DAILY_PNL_ERROR);
        });

        it("Should AssetsSent and emit AssetsSent", async () => {
            await resetFees();
            await userDeposit(DEPOSIT_AMOUNT, interactionUser1);

            const sendAssetsAmount = (DEPOSIT_AMOUNT * MAX_DAILY_ACC_PNL_DELTA) / PRECISION_18;

            await expect(
                hhXVault.connect(pnlHandler).sendAssets(0, sendAssetsAmount, interactionUser2),
            )
                .to.emit(hhXVault, "AssetsSent")
                .withArgs(pnlHandler, interactionUser2, sendAssetsAmount);

            expect(await hhXVault.totalLiability()).to.be.eq(sendAssetsAmount);
            expect(await hhXVault.totalClosedPnl()).to.be.eq(sendAssetsAmount);
            expect(await hhXVault.currentMaxSupply()).to.be.eq(
                (DEPOSIT_AMOUNT * TOTAL_SUPPLY_INCREASE_P) / 10_000n,
            );
            expect(await hhXVault.totalSupply()).to.be.eq(DEPOSIT_AMOUNT);
            expect(await hhXVault.totalAssets()).to.be.eq(DEPOSIT_AMOUNT - sendAssetsAmount);
            expect(await javToken.balanceOf(interactionUser2)).to.be.eq(sendAssetsAmount);
        });

        it("Should receiveAssets and emit AssetsReceived", async () => {
            const expectedPnl = parseUnits("-1", 18);

            await resetFees();
            await userDeposit(DEPOSIT_AMOUNT, interactionUser1);
            await mintApproveJav(BASE_AMOUNT, interactionUser2);

            await expect(
                hhXVault.connect(interactionUser2).receiveAssets(0, BASE_AMOUNT, ZERO_ADDRESS),
            )
                .to.emit(hhXVault, "AssetsReceived")
                .withArgs(interactionUser2, ZERO_ADDRESS, BASE_AMOUNT, BASE_AMOUNT);

            expect(await hhXVault.totalAssets()).to.be.eq(DEPOSIT_AMOUNT + BASE_AMOUNT);
            expect(await javToken.balanceOf(interactionUser2)).to.be.eq(0);
            expect(await hhXVault.accPnlPerToken()).to.be.eq(expectedPnl);
            expect(await hhXVault.dailyAccPnlDelta()).to.be.eq(expectedPnl);
            expect(await hhXVault.totalLiability()).to.be.eq(-BASE_AMOUNT);
            expect(await hhXVault.totalClosedPnl()).to.be.eq(-BASE_AMOUNT);
            expect(await hhXVault.currentMaxSupply()).to.be.eq(
                (DEPOSIT_AMOUNT * TOTAL_SUPPLY_INCREASE_P) / 10_000n,
            );
        });
    });
    describe("Rewards interactions", () => {
        it("Should distributeReward and emit RewardDistributed", async () => {
            await resetFees();
            await mintApproveJav(BASE_AMOUNT, interactionUser2);
            await userDeposit(DEPOSIT_AMOUNT, interactionUser1);

            await expect(hhXVault.connect(interactionUser2).distributeReward(0, BASE_AMOUNT))
                .to.emit(hhXVault, "RewardDistributed")
                .withArgs(interactionUser2, BASE_AMOUNT);

            expect(await hhXVault.totalAssets()).to.be.eq(BASE_AMOUNT + DEPOSIT_AMOUNT);
            expect(await hhXVault.shareToAssetsPrice()).to.be.eq(2n * PRECISION_18);
            expect(await hhXVault.totalRewards()).to.be.eq(BASE_AMOUNT);
            expect(await hhXVault.totalDeposited()).to.be.eq(BASE_AMOUNT + DEPOSIT_AMOUNT);
        });

        it("Should withdraw and emit Withdraw with redistribution amount", async () => {
            await resetFees();
            await makeWithdrawRequest(2n * DEPOSIT_AMOUNT, interactionUser1);
            await makeWithdrawRequest(DEPOSIT_AMOUNT, interactionUser2);

            //2:1
            await distributeRewards(3n * DEPOSIT_AMOUNT, interactionUser3);

            expect(await hhXVault.totalAssets()).to.be.eq(6n * DEPOSIT_AMOUNT);

            expect(await hhXVault.totalSupply()).to.be.eq(3n * DEPOSIT_AMOUNT);

            const currentEpoch = getCurrentEpoch();

            await skipEpochsDays(WITHDRAW_EPOCHS_LOCK);

            await expect(
                hhXVault
                    .connect(interactionUser1)
                    .withdraw(
                        currentEpoch + WITHDRAW_EPOCHS_LOCK,
                        interactionUser1,
                        interactionUser1,
                    ),
            )
                .to.emit(hhXVault, "Withdraw")
                .withArgs(
                    interactionUser1,
                    interactionUser1,
                    interactionUser1,
                    4n * DEPOSIT_AMOUNT,
                    2n * DEPOSIT_AMOUNT,
                );

            await expect(
                hhXVault
                    .connect(interactionUser2)
                    .withdraw(
                        currentEpoch + WITHDRAW_EPOCHS_LOCK,
                        interactionUser2,
                        interactionUser2,
                    ),
            )
                .to.emit(hhXVault, "Withdraw")
                .withArgs(
                    interactionUser2,
                    interactionUser2,
                    interactionUser2,
                    2n * DEPOSIT_AMOUNT,
                    DEPOSIT_AMOUNT,
                );

            expect(
                await hhXVault.withdrawRequests(
                    interactionUser1,
                    currentEpoch + WITHDRAW_EPOCHS_LOCK,
                ),
            ).to.be.eq(0);

            expect(
                await hhXVault.withdrawRequests(
                    interactionUser2,
                    currentEpoch + WITHDRAW_EPOCHS_LOCK,
                ),
            ).to.be.eq(0);

            expect(await javToken.balanceOf(interactionUser1)).to.be.eq(4n * DEPOSIT_AMOUNT);
            expect(await javToken.balanceOf(interactionUser2)).to.be.eq(2n * DEPOSIT_AMOUNT);
            expect(await hhXVault.totalAssets()).to.be.eq(0);
            expect(await hhXVault.totalSupply()).to.be.eq(0);
        });
    });

    describe("View functions and ERC override", () => {
        it("Should calculate correct tvl", async () => {
            await resetFees();
            await userDeposit(DEPOSIT_AMOUNT, interactionUser1);
            // PRECISION_18 (%)
            expect(await hhXVault.tvl()).to.be.eq(DEPOSIT_AMOUNT);
        });

        it("Should return correct precision", async () => {
            expect(await hhXVault.decimals()).to.be.eq(18);
        });

        it("Should revert when transfer pending withdrawal share", async () => {
            await resetFees();
            await userDeposit(DEPOSIT_AMOUNT, interactionUser1);
            await makeWithdrawRequest(BASE_AMOUNT, interactionUser1);
            await expect(
                hhXVault
                    .connect(interactionUser1)
                    .transfer(interactionUser2, DEPOSIT_AMOUNT + BASE_AMOUNT),
            ).to.be.revertedWithCustomError(hhXVault, WILLING_TRANSFER_AMOUNT_IS_PENDING_ERROR);
        });

        it("Should transfer", async () => {
            await resetFees();
            await userDeposit(DEPOSIT_AMOUNT, interactionUser1);
            await makeWithdrawRequest(BASE_AMOUNT, interactionUser1);
            await hhXVault.connect(interactionUser1).transfer(interactionUser2, DEPOSIT_AMOUNT);

            expect(await hhXVault.balanceOf(interactionUser1)).to.be.eq(BASE_AMOUNT);
            expect(await hhXVault.balanceOf(interactionUser2)).to.be.eq(DEPOSIT_AMOUNT);
        });

        it("Should revert when transferFrom pending withdrawal share", async () => {
            await resetFees();
            await userDeposit(DEPOSIT_AMOUNT, interactionUser1);
            await makeWithdrawRequest(BASE_AMOUNT, interactionUser1);
            await expect(
                hhXVault.transferFrom(
                    interactionUser1,
                    interactionUser2,
                    DEPOSIT_AMOUNT + BASE_AMOUNT,
                ),
            ).to.be.revertedWithCustomError(hhXVault, WILLING_TRANSFER_AMOUNT_IS_PENDING_ERROR);
        });

        it("Should transferFrom", async () => {
            await resetFees();
            await userDeposit(DEPOSIT_AMOUNT, interactionUser1);
            await makeWithdrawRequest(BASE_AMOUNT, interactionUser1);

            await hhXVault.connect(interactionUser1).approve(interactionUser1, DEPOSIT_AMOUNT);
            await hhXVault
                .connect(interactionUser1)
                .transferFrom(interactionUser1, interactionUser2, DEPOSIT_AMOUNT);

            expect(await hhXVault.balanceOf(interactionUser1)).to.be.eq(BASE_AMOUNT);
            expect(await hhXVault.balanceOf(interactionUser2)).to.be.eq(DEPOSIT_AMOUNT);
        });
    });

    describe("Dynamic epochs changes withdraw interactions", () => {
        it("Should withdraw immediatly after days->hours epoch duration update", async () => {
            const hourDuration = 3600;
            await resetFees();
            await makeWithdrawRequest(DEPOSIT_AMOUNT, interactionUser1);

            await skipEpochsDays(1);

            const currentEpoch = getCurrentEpoch();
            const unlockEpoch = currentEpoch + WITHDRAW_EPOCHS_LOCK;

            await expect(
                hhXVault
                    .connect(interactionUser1)
                    .withdraw(unlockEpoch, interactionUser1, interactionUser1),
            ).to.be.revertedWithCustomError(hhXVault, FUTURE_EPOCH_WITHDRAWAL_ERROR);

            await updateEpochDuration(hourDuration);

            await expect(
                hhXVault
                    .connect(interactionUser1)
                    .withdraw(unlockEpoch, interactionUser1, interactionUser1),
            )
                .to.emit(hhXVault, "Withdraw")
                .withArgs(
                    interactionUser1.address,
                    interactionUser1.address,
                    interactionUser1.address,
                    DEPOSIT_AMOUNT,
                    DEPOSIT_AMOUNT, //shares 1:1
                );
        });

        it("Should withdraw immediatly after hours->days epoch duration update", async () => {
            const hourDuration = 3600;
            const dayDuration = 86400;

            await updateEpochDuration(hourDuration);

            await resetFees();
            await makeWithdrawRequest(DEPOSIT_AMOUNT, interactionUser1);

            await skipEpochsHours(2);

            const currentEpoch = getCurrentEpoch();
            const unlockEpoch = currentEpoch + WITHDRAW_EPOCHS_LOCK;

            await expect(
                hhXVault
                    .connect(interactionUser1)
                    .withdraw(unlockEpoch, interactionUser1, interactionUser1),
            ).to.be.revertedWithCustomError(hhXVault, FUTURE_EPOCH_WITHDRAWAL_ERROR);

            await updateEpochDuration(dayDuration);

            await expect(
                hhXVault
                    .connect(interactionUser1)
                    .withdraw(unlockEpoch, interactionUser1, interactionUser1),
            )
                .to.emit(hhXVault, "Withdraw")
                .withArgs(
                    interactionUser1.address,
                    interactionUser1.address,
                    interactionUser1.address,
                    DEPOSIT_AMOUNT,
                    DEPOSIT_AMOUNT, //shares 1:1
                );
        });
    });
});
