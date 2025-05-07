const { expect } = require("chai");
const { ethers, upgrades } = require("hardhat");
const { parseUnits } = ethers;
const helpers = require("@nomicfoundation/hardhat-toolbox/network-helpers");
const { MANAGER_ERROR, ADMIN_ERROR } = require("./common/constanst");

const { deployTokenFixture, deployToken2Fixture } = require("./common/mocks");
describe("JavEscrow contract", () => {
    const INDEX_ERROR = "WrongIndex";
    const WRONG_PARAMS_ERROR = "WrongParams";
    const NOT_ALLOWED_ERROR = "NotAllowed";
    const INVALID_ADDRESSES_ERROR = "InvalidAddresses";
    const DOES_NOT_EXIST_ERROR = "DoesntExist";

    const INIT_PLACE_ORDER_FEE = 1n * 10n ** 4n;
    const UPDATED_PLACE_ORDER_FEE = 1n * 10n ** 3n; //10%
    const PLACE_ORDER_FEE_PRECISION = 1n * 10n ** 4n;

    const TOKEN_INITIAL_SUPPLY = parseUnits("100", 18);
    const TOKEN_TO_MARKET = parseUnits("25", 18);

    let hhJavEscrow;
    let admin;
    let randomUser;
    let seller;
    let buyer;
    let claimer;
    let erc20token0;
    let erc20token1;

    async function deployJavEscrow() {
        const javEscrowFactory = await ethers.getContractFactory("JavEscrow");
        [admin, ...addrs] = await ethers.getSigners();

        const escrow = await upgrades.deployProxy(
            javEscrowFactory,
            [[erc20token0.target], INIT_PLACE_ORDER_FEE],
            {
                initializer: "initialize",
            },
        );

        return escrow;
    }

    before(async () => {
        [admin, seller, buyer, claimer, randomUser, ...addrs] = await ethers.getSigners();

        erc20token0 = await helpers.loadFixture(deployTokenFixture);
        erc20token1 = await helpers.loadFixture(deployToken2Fixture);
        hhJavEscrow = await helpers.loadFixture(deployJavEscrow);

        await erc20token0.mint(seller.address, TOKEN_INITIAL_SUPPLY);
        await erc20token1.mint(buyer.address, TOKEN_INITIAL_SUPPLY);
        await erc20token0.connect(seller).approve(hhJavEscrow.target, TOKEN_INITIAL_SUPPLY);
        await erc20token1.connect(buyer).approve(hhJavEscrow.target, TOKEN_INITIAL_SUPPLY);
    });

    describe("Deployment", () => {
        it("Should set the right deployment params", async () => {
            const availableTokens = await hhJavEscrow.getAvailableTokens();
            expect(availableTokens.length).to.be.equal(1);
            expect(availableTokens[0]).to.be.equal(erc20token0.target);

            const placeOrderFee = await hhJavEscrow.placeOrderFee();
            expect(placeOrderFee).to.be.equal(INIT_PLACE_ORDER_FEE);
        });
    });

    describe("Non-admin interactions", () => {
        it("Should revert when add token", async () => {
            await expect(
                hhJavEscrow.connect(randomUser).addAvailableToken(erc20token1.target),
            ).to.be.revertedWith(ADMIN_ERROR);
        });

        it("Should revert when remove token", async () => {
            await expect(
                hhJavEscrow.connect(randomUser).removeAvailableToken(erc20token0.target),
            ).to.be.revertedWith(ADMIN_ERROR);
        });

        it("Should revert when set place order fee", async () => {
            await expect(
                hhJavEscrow.connect(randomUser).setPlaceOrderFee(UPDATED_PLACE_ORDER_FEE),
            ).to.be.revertedWith(ADMIN_ERROR);
        });

        it("Should revert when claim fee", async () => {
            await expect(
                hhJavEscrow.connect(randomUser).claimFee(erc20token0.target, admin),
            ).to.be.revertedWith(ADMIN_ERROR);
        });
    });

    describe("Admin interactions", () => {
        it("Should emit RemoveAvailableToken and removeAvailableToken", async () => {
            const availableTokens = await hhJavEscrow.getAvailableTokens();
            expect(availableTokens.length).to.be.equal(1);

            await expect(hhJavEscrow.connect(admin).removeAvailableToken(erc20token0.target))
                .to.emit(hhJavEscrow, "RemoveAvailableToken")
                .withArgs(erc20token0.target);

            const updatedAvailableTokens = await hhJavEscrow.getAvailableTokens();
            expect(updatedAvailableTokens.length).to.be.equal(0);
        });

        it("Should emit AddAvailableToken and addAvailableToken", async () => {
            const availableTokens = await hhJavEscrow.getAvailableTokens();
            expect(availableTokens.length).to.be.equal(0);

            await expect(hhJavEscrow.connect(admin).addAvailableToken(erc20token0.target))
                .to.emit(hhJavEscrow, "AddAvailableToken")
                .withArgs(erc20token0.target);

            const updatedAvailableTokens = await hhJavEscrow.getAvailableTokens();
            expect(updatedAvailableTokens.length).to.be.equal(1);
        });

        it("Should emit SetPlaceOrderFee and setPlaceOrderFee", async () => {
            const placeOrderFee = await hhJavEscrow.placeOrderFee();
            expect(placeOrderFee).to.be.equal(INIT_PLACE_ORDER_FEE);

            await expect(hhJavEscrow.connect(admin).setPlaceOrderFee(UPDATED_PLACE_ORDER_FEE))
                .to.emit(hhJavEscrow, "SetPlaceOrderFee")
                .withArgs(UPDATED_PLACE_ORDER_FEE);

            const updatedPlaceOrderFee = await hhJavEscrow.placeOrderFee();
            expect(updatedPlaceOrderFee).to.be.equal(UPDATED_PLACE_ORDER_FEE);
        });

        it("Should emit ClaimFee and claimFee 0", async () => {
            await expect(hhJavEscrow.connect(admin).claimFee(erc20token0.target, admin))
                .to.emit(hhJavEscrow, "ClaimFee")
                .withArgs(admin, 0);
        });
    });

    describe("Order interactions", () => {
        it("Should revert when incorrect orderId", async () => {
            const order = {
                orderId: 1,
                token0: erc20token0.target,
                token1: erc20token1.target,
                seller: seller.address,
                token0Amount: TOKEN_TO_MARKET,
                token1Amount: TOKEN_TO_MARKET,
                isActive: true,
            };
            await expect(
                hhJavEscrow.connect(seller).placeOrder(order),
            ).to.be.revertedWithCustomError(hhJavEscrow, INDEX_ERROR);
        });

        it("Should revert when incorrect isActive", async () => {
            const order = {
                orderId: 0,
                token0: erc20token0.target,
                token1: erc20token1.target,
                seller: seller.address,
                token0Amount: TOKEN_TO_MARKET,
                token1Amount: TOKEN_TO_MARKET,
                isActive: false,
            };
            await expect(
                hhJavEscrow.connect(seller).placeOrder(order),
            ).to.be.revertedWithCustomError(hhJavEscrow, WRONG_PARAMS_ERROR);
        });

        it("Should revert when incorrect seller", async () => {
            const order = {
                orderId: 0,
                token0: erc20token0.target,
                token1: erc20token1.target,
                seller: seller.address,
                token0Amount: TOKEN_TO_MARKET,
                token1Amount: TOKEN_TO_MARKET,
                isActive: true,
            };
            await expect(
                hhJavEscrow.connect(randomUser).placeOrder(order),
            ).to.be.revertedWithCustomError(hhJavEscrow, NOT_ALLOWED_ERROR);
        });

        it("Should revert when incorrect token addresses", async () => {
            const order = {
                orderId: 0,
                token0: erc20token0.target,
                token1: erc20token1.target,
                seller: seller.address,
                token0Amount: TOKEN_TO_MARKET,
                token1Amount: TOKEN_TO_MARKET,
                isActive: true,
            };
            await expect(
                hhJavEscrow.connect(seller).placeOrder(order),
            ).to.be.revertedWithCustomError(hhJavEscrow, INVALID_ADDRESSES_ERROR);
        });

        it("Should placeOrder, emit OrderPlaced and update fee", async () => {
            await hhJavEscrow.connect(admin).addAvailableToken(erc20token1.target);

            const currentScBalance = await erc20token0.balanceOf(hhJavEscrow.target);
            const currentSellerBalance = await erc20token0.balanceOf(seller.address);

            expect(currentScBalance).to.be.equal(0);
            expect(currentSellerBalance).to.be.equal(TOKEN_INITIAL_SUPPLY);

            const order = {
                orderId: 0,
                token0: erc20token0.target,
                token1: erc20token1.target,
                seller: seller.address,
                token0Amount: TOKEN_TO_MARKET,
                token1Amount: TOKEN_TO_MARKET,
                isActive: true,
            };

            await expect(hhJavEscrow.connect(seller).placeOrder(order)).to.emit(
                hhJavEscrow,
                "OrderPlaced",
            );

            const actualLastOrderId = await hhJavEscrow.lastOrderId();
            const storedOrder = await hhJavEscrow.orders(actualLastOrderId - 1n);
            const actualFeeAmount = await hhJavEscrow.fees(order.token0);

            const predictedLastOrderId = 1;
            const predictedFeeAmount =
                (TOKEN_TO_MARKET * UPDATED_PLACE_ORDER_FEE) / PLACE_ORDER_FEE_PRECISION; //10%

            expect(actualLastOrderId).to.be.equal(predictedLastOrderId);
            expect(actualFeeAmount).to.be.equal(predictedFeeAmount);
            expect(storedOrder.seller).not.to.be.equal(
                "0x0000000000000000000000000000000000000000",
            );

            const updatedScBalance = await erc20token0.balanceOf(hhJavEscrow.target);
            const updatedSellerBalance = await erc20token0.balanceOf(seller.address);

            expect(updatedScBalance).to.be.equal(TOKEN_TO_MARKET + actualFeeAmount);
            expect(updatedSellerBalance).to.be.equal(
                TOKEN_INITIAL_SUPPLY - TOKEN_TO_MARKET - actualFeeAmount,
            );
        });

        it("Should revert when incorrect sender cancels", async () => {
            const orderId = 0;

            await expect(
                hhJavEscrow.connect(randomUser).cancelOrder(orderId),
            ).to.be.revertedWithCustomError(hhJavEscrow, NOT_ALLOWED_ERROR);
        });

        it("Should emit CancelOrder and cancelOrder", async () => {
            const orderId = 0;
            const feeAmount =
                (TOKEN_TO_MARKET * UPDATED_PLACE_ORDER_FEE) / PLACE_ORDER_FEE_PRECISION;

            const currentScBalance = await erc20token0.balanceOf(hhJavEscrow.target);
            const currentSellerBalance = await erc20token0.balanceOf(seller.address);
            expect(currentScBalance).to.be.equal(TOKEN_TO_MARKET + feeAmount);
            expect(currentSellerBalance).to.be.equal(
                TOKEN_INITIAL_SUPPLY - TOKEN_TO_MARKET - feeAmount,
            );

            await expect(hhJavEscrow.connect(seller).cancelOrder(orderId)).to.emit(
                hhJavEscrow,
                "CancelOrder",
            );

            const updatedOrded = await hhJavEscrow.orders(orderId);
            const predictedOrderStatus = false;

            const updatedScBalance = await erc20token0.balanceOf(hhJavEscrow.target);
            const predictedScBalance = feeAmount;

            const updatedSellerBalance = await erc20token0.balanceOf(seller.address);
            const predictedSellerBalance = TOKEN_INITIAL_SUPPLY - feeAmount;

            expect(updatedOrded.isActive).to.be.equal(predictedOrderStatus);
            expect(updatedScBalance).to.be.equal(predictedScBalance);
            expect(updatedSellerBalance).to.be.equal(predictedSellerBalance);
        });
        //2nd order init, same context
        it("Should emit AcceptOrder and acceptOrder", async () => {
            const feeAmount =
                (TOKEN_TO_MARKET * UPDATED_PLACE_ORDER_FEE) / PLACE_ORDER_FEE_PRECISION;

            const currentScBalanceToken0 = await erc20token0.balanceOf(hhJavEscrow.target);
            const currentScBalanceToken1 = await erc20token1.balanceOf(hhJavEscrow.target);
            const currentSellerBalanceToken0 = await erc20token0.balanceOf(seller.address);
            const currentSellerBalanceToken1 = await erc20token1.balanceOf(seller.address);
            const currentBuyerBalanceToken0 = await erc20token0.balanceOf(buyer.address);
            const currentBuyerBalanceToken1 = await erc20token1.balanceOf(buyer.address);

            expect(currentScBalanceToken0).to.be.equal(feeAmount);
            expect(currentScBalanceToken1).to.be.equal(0);

            expect(currentSellerBalanceToken0).to.be.equal(TOKEN_INITIAL_SUPPLY - feeAmount); //after cancelation of 1st order
            expect(currentSellerBalanceToken1).to.be.equal(0);

            expect(currentBuyerBalanceToken0).to.be.equal(0);
            expect(currentBuyerBalanceToken1).to.be.equal(TOKEN_INITIAL_SUPPLY);

            const order = {
                orderId: 1,
                token0: erc20token0.target,
                token1: erc20token1.target,
                seller: seller.address,
                token0Amount: TOKEN_TO_MARKET,
                token1Amount: TOKEN_TO_MARKET,
                isActive: true,
            };

            await expect(hhJavEscrow.connect(seller).placeOrder(order)).to.emit(
                hhJavEscrow,
                "OrderPlaced",
            );

            const updatedScBalanceToken0 = await erc20token0.balanceOf(hhJavEscrow.target);
            const updatedSellerBalanceToken0 = await erc20token0.balanceOf(seller.address);
            expect(updatedScBalanceToken0).to.be.equal(2n * feeAmount + TOKEN_TO_MARKET); //2nd order after 1st cancelation
            expect(updatedSellerBalanceToken0).to.be.equal(
                TOKEN_INITIAL_SUPPLY - TOKEN_TO_MARKET - 2n * feeAmount,
            );

            const orderId = 1;

            await expect(hhJavEscrow.connect(buyer).acceptOrder(orderId)).to.emit(
                hhJavEscrow,
                "AcceptOrder",
            );

            const expectedScBalanceToken0 = 2n * feeAmount;
            const expectedScBalanceToken1 = 0;
            const expectedBuyerBalanceToken0 = TOKEN_TO_MARKET;
            const expectedBuyerBalanceToken1 = TOKEN_INITIAL_SUPPLY - TOKEN_TO_MARKET;
            const expectedSellerBalanceToken0 =
                TOKEN_INITIAL_SUPPLY - TOKEN_TO_MARKET - 2n * feeAmount; //2nd order, 1st got cancelled
            const expectedSellerBalanceToken1 = TOKEN_TO_MARKET;

            const finalizedScBalanceToken0 = await erc20token0.balanceOf(hhJavEscrow.target);
            const finalizedScBalanceToken1 = await erc20token1.balanceOf(hhJavEscrow.target);
            const finalizedBuyerBalanceToken0 = await erc20token0.balanceOf(buyer.address);
            const finalizedBuyerBalanceToken1 = await erc20token1.balanceOf(buyer.address);
            const finalizedSellerBalanceToken0 = await erc20token0.balanceOf(seller.address);
            const finalizedSellerBalanceToken1 = await erc20token1.balanceOf(seller.address);

            expect(finalizedScBalanceToken0).to.be.equal(expectedScBalanceToken0);
            expect(finalizedScBalanceToken1).to.be.equal(expectedScBalanceToken1);
            expect(finalizedBuyerBalanceToken0).to.be.equal(expectedBuyerBalanceToken0);
            expect(finalizedBuyerBalanceToken1).to.be.equal(expectedBuyerBalanceToken1);
            expect(finalizedSellerBalanceToken0).to.be.equal(expectedSellerBalanceToken0);
            expect(finalizedSellerBalanceToken1).to.be.equal(expectedSellerBalanceToken1);

            const updatedOrder = await hhJavEscrow.orders(orderId);
            const expectedOrderStatus = false;
            expect(updatedOrder.isActive).to.be.equal(expectedOrderStatus);
        });

        it("Should revert when inactive order cancels", async () => {
            const orderId = 1;

            await expect(
                hhJavEscrow.connect(buyer).cancelOrder(orderId),
            ).to.be.revertedWithCustomError(hhJavEscrow, DOES_NOT_EXIST_ERROR);
        });

        it("Should revert when inactive order accepts", async () => {
            const orderId = 1;

            await expect(
                hhJavEscrow.connect(buyer).acceptOrder(orderId),
            ).to.be.revertedWithCustomError(hhJavEscrow, DOES_NOT_EXIST_ERROR);
        });
    });

    describe("Claims", () => {
        it("Should claim", async () => {
            const feeAmount =
                (TOKEN_TO_MARKET * UPDATED_PLACE_ORDER_FEE) / PLACE_ORDER_FEE_PRECISION;

            const currentClaimerBalanceToken0 = await erc20token0.balanceOf(claimer.address);
            const currentScBalanceToken0 = await erc20token0.balanceOf(hhJavEscrow.target);
            const expectedClaimerBalanceToken0 = 0;
            const expectedScBalanceToken0 = 2n * feeAmount;
            expect(currentClaimerBalanceToken0).to.be.equal(expectedClaimerBalanceToken0);
            expect(currentScBalanceToken0).to.be.equal(expectedScBalanceToken0); //2 places occured

            await expect(hhJavEscrow.connect(admin).claimFee(erc20token0.target, claimer.address))
                .to.emit(hhJavEscrow, "ClaimFee")
                .withArgs(claimer.address, 2n * feeAmount);

            const token0FeesValue = await hhJavEscrow.fees(erc20token0.target);
            expect(token0FeesValue).to.be.equal(0);

            const updatedClaimerBalanceToken0 = await erc20token0.balanceOf(claimer.address);
            const updatedScBalanceToken0 = await erc20token0.balanceOf(hhJavEscrow.target);
            expect(updatedClaimerBalanceToken0).to.be.equal(2n * feeAmount);
            expect(updatedScBalanceToken0).to.be.equal(0);
        });
    });
});
