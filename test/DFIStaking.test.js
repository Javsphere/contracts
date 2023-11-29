const {expect} = require("chai");
const {ethers, upgrades} = require("hardhat")
const helpers = require("@nomicfoundation/hardhat-toolbox/network-helpers");
const {ADMIN_ERROR} = require("./common/constanst");


describe("DFIStaking contract", () => {
    let hhDFIStaking;
    let owner;
    let addr1;
    let addr2;
    let addr3;
    let bot;
    let minDepAmount
    let erc20Token;

    async function getSpentGas(tx) {
        const receipt = await tx.wait();
        return receipt.gasUsed * receipt.gasPrice;
    }

    async function deployTokenFixture() {
        const erc20ContractFactory = await ethers.getContractFactory("JavStakingToken");
        erc20Token = await upgrades.deployProxy(
            erc20ContractFactory,
            [
            ],

            {
                initializer: "initialize",
            }
        );
        await erc20Token.waitForDeployment();
        return erc20Token
    }

    before(async () => {
        const dfiStaking = await ethers.getContractFactory("DFIStaking");
        [owner, addr1, addr2, addr3, bot, serviceSigner, ...addrs] = await ethers.getSigners();
        const nonZeroAddress = ethers.Wallet.createRandom().address;
        erc20Token = await helpers.loadFixture(deployTokenFixture);
        minDepAmount = ethers.parseEther("0.005")

        hhDFIStaking = await upgrades.deployProxy(
            dfiStaking,
            [
                erc20Token.target,
                bot.address,
                minDepAmount
            ],

            {
                initializer: "initialize",
            }
        );




    });

    describe("Deployment", () => {

        it("Should set the right owner address", async () => {

            await expect(await hhDFIStaking.owner()).to.equal(owner.address);
        });

        it("Should set the right token address", async () => {

            await expect(await hhDFIStaking.token()).to.equal(erc20Token.target);
        });

        it("Should set the right admin address", async () => {

            await expect(await hhDFIStaking.adminAddress()).to.equal(owner.address);
        });

        it("Should set the right minimumDepositAmount", async () => {

            await expect(await hhDFIStaking.minimumDepositAmount()).to.equal(minDepAmount);
        });

        it("Should set the right bot address", async () => {

            await expect(await hhDFIStaking.botAddress()).to.equal(bot.address);
        });

        it("Should set the _paused status", async () => {

            await expect(await hhDFIStaking.paused()).to.equal(false);
        });

    });

    describe("Transactions", () => {
        it("Should revert when set pause", async () => {
            await expect(
                hhDFIStaking.connect(addr1).pause()
            ).to.be.revertedWith(
                ADMIN_ERROR
            );

        });

        it("Should set pause", async () => {
            await hhDFIStaking.pause();

            await expect(await hhDFIStaking.paused()).to.equal(true);
        });

        it("Should revert when set unpause", async () => {
            await expect(
                hhDFIStaking.connect(addr1).unpause()
            ).to.be.revertedWith(
                ADMIN_ERROR
            );

        });

        it("Should set unpause", async () => {
            await hhDFIStaking.unpause();

            await expect(await hhDFIStaking.paused()).to.equal(false);
        });

        it("Should revert when set the admin address", async () => {
            await expect(
                hhDFIStaking.connect(addr1).setAdminAddress(owner.address)
            ).to.be.revertedWith(
                ADMIN_ERROR
            );

        });

        it("Should set the admin address", async () => {
            await hhDFIStaking.setAdminAddress(owner.address);

            await expect(await hhDFIStaking.adminAddress()).to.equal(owner.address);
        });

        it("Should revert when set the bot address", async () => {
            await expect(
                hhDFIStaking.connect(addr1).setBotAddress(bot.address)
            ).to.be.revertedWith(
                ADMIN_ERROR
            );

        });

        it("Should set the bot address", async () => {
            await hhDFIStaking.setBotAddress(bot.address);

            await expect(await hhDFIStaking.botAddress()).to.equal(bot.address);
        });

        it("Should revert when set the token address", async () => {
            await expect(
                hhDFIStaking.connect(addr1).setTokenAddress(bot.address)
            ).to.be.revertedWith(
                ADMIN_ERROR
            );

        });

        it("Should set the token address", async () => {
            await hhDFIStaking.setTokenAddress(erc20Token.target);

            await expect(await hhDFIStaking.token()).to.equal(erc20Token.target);
        });

        it("Should revert when set minimum deposit amount", async () => {
            await expect(
                hhDFIStaking.connect(addr1).setMinimumDepositAmount(minDepAmount)
            ).to.be.revertedWith(
                ADMIN_ERROR
            );

        });

        it("Should set minimum deposit amount", async () => {
            await hhDFIStaking.setMinimumDepositAmount(minDepAmount);

            await expect(await hhDFIStaking.minimumDepositAmount()).to.equal(minDepAmount);
        });

        it("Should revert when deposit paused=true", async () => {
            await hhDFIStaking.pause();

            await expect(
                hhDFIStaking.connect(addr1).deposit(
                    {
                        value: ethers.parseEther("1")
                    }
                )
            ).to.be.revertedWithCustomError(
                hhDFIStaking, "EnforcedPause"
            );
            await hhDFIStaking.unpause();

        });

        it("Should revert when deposit msg.value < minimumDepositAmount", async () => {
            await expect(
                hhDFIStaking.connect(addr1).deposit(
                    {
                        value: minDepAmount - ethers.parseEther("0.00000001")
                    }
                )
            ).to.be.revertedWith(
                "DFIStaking: invalid deposit amount"
            );

        });

        it("Should revert when deposit not role for mint", async () => {
            await expect(
                hhDFIStaking.connect(addr1).deposit(
                    {
                        value: minDepAmount
                    }
                )
            ).to.be.revertedWithCustomError(
                erc20Token, "AccessControlUnauthorizedAccount"
            );

            await erc20Token.connect(owner).grantRole(ethers.encodeBytes32String("0x01"), hhDFIStaking.target);

        });

        it("Should deposit", async () => {
            const amount = ethers.parseEther("1");
            const addr1BalanceBefore = await ethers.provider.getBalance(addr1.address);
            const botBalanceBefore = await ethers.provider.getBalance(bot.address);
            const contractBalanceBefore = await ethers.provider.getBalance(hhDFIStaking.target);
            const amountBefore = await erc20Token.balanceOf(addr1.address);

            const tx = await hhDFIStaking.connect(addr1).deposit(
                {
                    value: amount
                }
            );

            const spentOnGas = await getSpentGas(tx);

            await expect(await erc20Token.balanceOf(addr1.address)).to.equal(amountBefore + amount)
            await expect(await ethers.provider.getBalance(addr1.address)).to.equal(addr1BalanceBefore - amount - spentOnGas)
            await expect(await ethers.provider.getBalance(bot.address)).to.equal(botBalanceBefore + amount)
            await expect(await ethers.provider.getBalance(hhDFIStaking.target)).to.equal(contractBalanceBefore)
            await expect(await hhDFIStaking.userDeposit(addr1.address)).to.equal(amount)

        });

        it("Should revert when updateInvestment onlyBot", async () => {
            const amount = ethers.parseEther("1");
            const messageDepositData = [
                {
                    user: addr1.address,
                    amount: amount
                },
                {
                    user: addr3.address,
                    amount: amount
                },
            ]

            const messageRewardsData = [
                {
                    user: addr1.address,
                    amount: amount
                },
                {
                    user: addr3.address,
                    amount: amount
                },
            ]

            await expect(
                hhDFIStaking.connect(addr1).updateInvestment(messageDepositData, messageRewardsData)
            ).to.be.revertedWith(
                "DFIStaking: only bot"
            );

        });

        it("Should revert when updateInvestment userDeposit < _depositInfo[i].amount", async () => {
            const amount = ethers.parseEther("1");
            const userDeposit = await hhDFIStaking.userDeposit(addr1.address)
            const messageDepositData = [
                {
                    user: addr1.address,
                    amount: userDeposit + amount
                },
            ]

            const messageRewardsData = []

            await expect(
                hhDFIStaking.connect(bot).updateInvestment(messageDepositData, messageRewardsData)
            ).to.be.revertedWith(
                "DFIStaking: invalid deposit info"
            );

        });

        it("Should updateInvestment - deposit > 0  investment = 0", async () => {
            const amount = ethers.parseEther("1");
            const userDepositBefore1 = await hhDFIStaking.userDeposit(addr1.address)
            const messageDepositData = [
                {
                    user: addr1.address,
                    amount: amount
                },
            ]
            const messageRewardsData = []

            await hhDFIStaking.connect(bot).updateInvestment(messageDepositData, messageRewardsData);

            await expect(await hhDFIStaking.userDeposit(addr1.address)).to.equal(userDepositBefore1 - amount);
            await expect(await hhDFIStaking.userInvestment(addr1.address)).to.equal(amount);
        });

        it("Should updateInvestment - reinvest, userDeposit=0, rewards > minDepAmount", async () => {
            const amount = ethers.parseEther("1");
            const investmentBefore = await hhDFIStaking.userInvestment(addr3.address);
            const stAmountBefore = await erc20Token.balanceOf(addr3.address)
            const messageDepositData = []
            const messageRewardsData = [
                {
                    user: addr3.address,
                    amount: amount
                },
            ]

            await hhDFIStaking.connect(bot).updateInvestment(messageDepositData, messageRewardsData);

            await expect(await hhDFIStaking.userDeposit(addr3.address)).to.equal(0);
            await expect(await hhDFIStaking.userInvestment(addr3.address)).to.equal(investmentBefore + amount);
            await expect(await hhDFIStaking.userMintRewards(addr3.address)).to.equal(0);
            await expect(await erc20Token.balanceOf(addr3.address)).to.equal(stAmountBefore + amount);

        });

        it("Should updateInvestment - reinvest, userDeposit=0, rewards < minDepAmount", async () => {
            const amount = minDepAmount - ethers.parseEther("0.000005");
            const investmentBefore = await hhDFIStaking.userInvestment(addr3.address);
            const stAmountBefore = await erc20Token.balanceOf(addr3.address)
            const messageDepositData = []
            const messageRewardsData = [
                {
                    user: addr3.address,
                    amount: amount
                },
            ]

            await hhDFIStaking.connect(bot).updateInvestment(messageDepositData, messageRewardsData);

            await expect(await hhDFIStaking.userDeposit(addr3.address)).to.equal(0);
            await expect(await hhDFIStaking.userInvestment(addr3.address)).to.equal(investmentBefore + amount);
            await expect(await hhDFIStaking.userMintRewards(addr3.address)).to.equal(amount);
            await expect(await erc20Token.balanceOf(addr3.address)).to.equal(stAmountBefore);

        });

        it("Should updateInvestment - deposit > 0  investment > 0  investment < deposit with rewards", async () => {
            const investmentAmount = ethers.parseEther("2");
            const rewardsAmount = ethers.parseEther("0.005");
            const depositAmount = ethers.parseEther("3");
            const amountBefore = await hhDFIStaking.userInvestment(addr1.address);

            await hhDFIStaking.connect(addr1).deposit({
                value: depositAmount
            });
            const userDepositBefore = await hhDFIStaking.userDeposit(addr1.address);

            const messageDepositData = [
                {
                    user: addr1.address,
                    amount: investmentAmount
                },
            ]
            const messageRewardsData = [
                {
                    user: addr1.address,
                    amount: rewardsAmount
                },
            ]

            await hhDFIStaking.connect(bot).updateInvestment(messageDepositData, messageRewardsData);

            await expect(await hhDFIStaking.userDeposit(addr1.address)).to.equal(userDepositBefore - investmentAmount);
            await expect(await hhDFIStaking.userInvestment(addr1.address)).to.equal(amountBefore + investmentAmount + rewardsAmount);

        });

        it("Should updateInvestment - deposit > 0  investment > 0  investment = deposit", async () => {
            const userInvestmentBefore = await hhDFIStaking.userInvestment(addr1.address);
            const userDepositBefore = await hhDFIStaking.userDeposit(addr1.address);
            const depositAmount = ethers.parseEther("1");
            const investmentAmount = userDepositBefore + depositAmount

            await hhDFIStaking.connect(addr1).deposit(
                {
                    value: depositAmount
                }
            );

            const messageDepositData = [
                {
                    user: addr1.address,
                    amount: investmentAmount
                },
            ]
            const messageRewardsData = []

            await hhDFIStaking.connect(bot).updateInvestment(messageDepositData, messageRewardsData);

            await expect(await hhDFIStaking.userDeposit(addr1.address)).to.equal(userDepositBefore + depositAmount - investmentAmount);
            await expect(await hhDFIStaking.userInvestment(addr1.address)).to.equal(userInvestmentBefore + investmentAmount);
        });

        it("Should updateInvestment with deposit > new userInvestment ", async () => {
            const userInvestmentBefore = await hhDFIStaking.userInvestment(addr1.address);
            const userDepositBefore = await hhDFIStaking.userDeposit(addr1.address);
            const depositAmount = ethers.parseEther("1");
            const investmentAmount = userDepositBefore;

            await hhDFIStaking.connect(addr1).deposit({
                value: depositAmount
            });

            const messageDepositData = [
                {
                    user: addr1.address,
                    amount: investmentAmount
                },
            ]
            const messageRewardsData = []

            await hhDFIStaking.connect(bot).updateInvestment(messageDepositData, messageRewardsData);

            await expect(await hhDFIStaking.userDeposit(addr1.address)).to.equal(userDepositBefore + depositAmount - investmentAmount);
            await expect(await hhDFIStaking.userInvestment(addr1.address)).to.equal(userInvestmentBefore + investmentAmount);

        });

        it("Should updateInvestment with  diff users", async () => {
            // user1 - investment = deposit
            // user2 - investment = part of deposit
            // user3 - only rewards
            // user4 - investment = part of deposit, + rewards
            const userInvestmentBefore1 = await hhDFIStaking.userInvestment(addr1.address);
            const userInvestmentBefore2 = await hhDFIStaking.userInvestment(addr2.address);
            const userInvestmentBefore3 = await hhDFIStaking.userInvestment(addr3.address);
            const userInvestmentBefore4 = await hhDFIStaking.userInvestment(owner.address);
            const rewardsAmount3 = ethers.parseEther("0.00006");
            const depositAmount1 = ethers.parseEther("0.5");
            const depositAmount2 = ethers.parseEther("1.7");
            const depositAmount4 = ethers.parseEther("2");
            const investmentAmount2 = depositAmount2 - ethers.parseEther("0.3");
            const investmentAmount4 = depositAmount4 - ethers.parseEther("1.3");
            const rewardsAmount4 = ethers.parseEther("0.00009");

            await hhDFIStaking.connect(addr1).deposit({
                value: depositAmount1
            });
            await hhDFIStaking.connect(addr2).deposit({
                value: depositAmount2
            });
            await hhDFIStaking.connect(owner).deposit({
                value: depositAmount4
            });

            const userDepositBefore1 = await hhDFIStaking.userDeposit(addr1.address);
            const userDepositBefore2 = await hhDFIStaking.userDeposit(addr2.address);
            const userDepositBefore3 = await hhDFIStaking.userDeposit(addr3.address);
            const userDepositBefore4 = await hhDFIStaking.userDeposit(owner.address);

            const messageDepositData = [
                {
                    user: addr1.address,
                    amount: userDepositBefore1
                },
                {
                    user: addr2.address,
                    amount: investmentAmount2
                },
                {
                    user: owner.address,
                    amount: investmentAmount4
                },
            ]
            const messageRewardsData = [
                {
                    user: addr3.address,
                    amount: rewardsAmount3
                },
                {
                    user: owner.address,
                    amount: rewardsAmount4
                },
            ]

            await hhDFIStaking.connect(bot).updateInvestment(messageDepositData, messageRewardsData);

            await expect(await hhDFIStaking.userDeposit(addr1.address)).to.equal(0);
            await expect(await hhDFIStaking.userDeposit(addr2.address)).to.equal(userDepositBefore2 - investmentAmount2);
            await expect(await hhDFIStaking.userDeposit(addr3.address)).to.equal(userDepositBefore3);
            await expect(await hhDFIStaking.userDeposit(owner.address)).to.equal(userDepositBefore4 - investmentAmount4);
            await expect(await hhDFIStaking.userInvestment(addr1.address)).to.equal(userInvestmentBefore1 + userDepositBefore1);
            await expect(await hhDFIStaking.userInvestment(addr2.address)).to.equal(userInvestmentBefore2 + investmentAmount2);
            await expect(await hhDFIStaking.userInvestment(addr3.address)).to.equal(userInvestmentBefore3 + rewardsAmount3);
            await expect(await hhDFIStaking.userInvestment(owner.address)).to.equal(userInvestmentBefore4 + investmentAmount4 + rewardsAmount4);
        });

        it("Should revert when request withdraw userInvestment[msg.sender] < _amount", async () => {
            const userInvestment = await hhDFIStaking.userInvestment(addr3.address)
            await expect(
                hhDFIStaking.connect(addr3).requestWithdraw(userInvestment + ethers.parseEther("2"))
            ).to.be.revertedWith(
                "DFIStaking: invalid amount for withdraw"
            );
        });

        it("Should create request withdraw ", async () => {
            const amount = ethers.parseEther("1");
            await hhDFIStaking.connect(addr1).requestWithdraw(amount);

            await expect(await hhDFIStaking.userRequestedWithdraw(addr1.address)).to.equal(amount);
        });

        it("Should revert when updateWithdraw onlyBot", async () => {
            const amount = ethers.parseEther("1");
            const messageData = [
                {
                    user: addr1.address,
                    amount: amount
                },
                {
                    user: addr3.address,
                    amount: amount
                },
            ]

            await expect(
                hhDFIStaking.connect(addr1).updateWithdraw(messageData)
            ).to.be.revertedWith(
                "DFIStaking: only bot"
            );
        });

        it("Should revert when updateWithdraw - userRequestedWithdraw < _withdraw.amount", async () => {
            const amount = await hhDFIStaking.userRequestedWithdraw(addr1.address);
            const messageData = [
                {
                    user: addr1.address,
                    amount: amount + ethers.parseEther("1")
                },
            ]

            await expect(
                hhDFIStaking.connect(bot).updateWithdraw(messageData)
            ).to.be.revertedWith(
                "DFIStaking: invalid claimable amount"
            );
        });

        it("Should updateWithdraw", async () => {
            await erc20Token.mint(bot.address, ethers.parseEther("5"))
            const amount = ethers.parseEther("1");
            const userRequestedWithdrawBefore = await hhDFIStaking.userRequestedWithdraw(addr1.address);
            const userClaimableAmountBefore = await hhDFIStaking.userClaimableAmount(addr1.address);
            const userInvestmentBefore = await hhDFIStaking.userInvestment(addr1.address);

            const messageData = [
                {
                    user: addr1.address,
                    amount: amount
                },
            ]
            await erc20Token.connect(bot).approve(hhDFIStaking.target, amount);
            await hhDFIStaking.connect(bot).updateWithdraw(messageData);

            await expect(await hhDFIStaking.userInvestment(addr1.address)).to.equal(userInvestmentBefore - amount);
            await expect(await hhDFIStaking.userRequestedWithdraw(addr1.address)).to.equal(userRequestedWithdrawBefore - amount);
            await expect(await hhDFIStaking.userClaimableAmount(addr1.address)).to.equal(userClaimableAmountBefore + amount);
        });

        it("Should revert when withdraw _amount <= 0", async () => {
            await expect(
                hhDFIStaking.connect(addr3).withdraw()
            ).to.be.revertedWith("DFIStaking: invalid withdraw amount");

        });

        it("Should revert when withdraw balance < _amount", async () => {
            await expect(
                hhDFIStaking.connect(addr1).withdraw()
            ).to.be.revertedWith("DFIStaking: not enough tokens");

        });

        it("Should revert when withdraw ERC20InsufficientAllowance", async () => {
            const amount = await hhDFIStaking.userClaimableAmount(addr1.address);

            await helpers.setBalance(hhDFIStaking.target, amount)

            await expect(
                hhDFIStaking.connect(addr1).withdraw()
            ).to.be.revertedWithCustomError(erc20Token, "ERC20InsufficientAllowance");

        });

        it("Should withdraw", async () => {
            const amount = await hhDFIStaking.userClaimableAmount(addr1.address);

            await helpers.setBalance(hhDFIStaking.target, amount + ethers.parseEther("1"))
            const contractBalanceBefore = await ethers.provider.getBalance(hhDFIStaking.target);
            const userBalanceBefore = await ethers.provider.getBalance(addr1.address);
            const userStBalanceBefore = await erc20Token.balanceOf(addr1.address);

            await erc20Token.connect(addr1).approve(hhDFIStaking.target, amount);
            const tx = await hhDFIStaking.connect(addr1).withdraw();
            const spentOnGas = await getSpentGas(tx);

            await expect(await erc20Token.balanceOf(addr1.address)).to.equal(userStBalanceBefore - amount);
            await expect(await ethers.provider.getBalance(hhDFIStaking.target)).to.equal(contractBalanceBefore - amount);
            await expect(await hhDFIStaking.userClaimableAmount(addr1.address)).to.equal(0);


        });

        it("Should revert when withdraw paused=true", async () => {
            await hhDFIStaking.pause()
            await expect(
                hhDFIStaking.connect(addr1).withdraw()
            ).to.be.revertedWithCustomError(
                hhDFIStaking, "EnforcedPause"
            );

        });

    });
});


