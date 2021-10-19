const { expect } = require("chai");
const { ethers } = require("hardhat");
const {startRaffle, endRaffle, getLastTimestamp, day} = require("./test-helper");


//issue with chainlink provided mocks causes extra WARNING logs 
//in current version of ethers. Restricting logs to ERROR only until patch. 
//See  https://github.com/ethers-io/ethers.js/issues/905 
const Logger = ethers.utils.Logger;
Logger.setLogLevel(Logger.levels.ERROR)

describe("MultiRaffle", function () {

    let owner;
    let addr1;
    let addr2;
    let addrs;
  
    let vrfCoordinatorMock;
    let multiRaffle;
    
    //hardhat network
    const fee = ethers.BigNumber.from("100000000000000000");
    const keyHash = '0x6c3699283bda56ad74f6b855546325b68d482e983852a7a82979cc4807b641f4';

    const mintCost = ethers.utils.parseEther('0.1');
    const availableSupply = 10;
    const maxPerAddress = 9;

   
    async function submitEntry(signer, quantity) {
        const val = mintCost.mul(quantity);
        await multiRaffle.connect(signer).enterRaffle(quantity, {value:val});
    }

    async function clearRaffle() {
        await multiRaffle.setClearingEntropy();
        await vrfCoordinatorMock.callBackWithRandomness(ethers.constants.HashZero, 0, multiRaffle.address);
        await multiRaffle.clearRaffle(availableSupply);
    }

    async function getWinningIndices(signer) {
        const indices = []

        for(let i = 0; i < availableSupply; i++) {
            const curAddr = await multiRaffle.raffleEntries(i);
            if(curAddr == signer.address) {
                indices.push(i);
            }
        }
        return indices;
    }

    beforeEach(async function () {

        [owner, addr1, addr2, ...addrs] = await ethers.getSigners();
    
        const linkTokenFactory = await ethers.getContractFactory("LinkToken");
        const linkToken = await linkTokenFactory.deploy();
    
        const vrfCoordinatorMockFactory = await ethers.getContractFactory("VRFCoordinatorMock");
        vrfCoordinatorMock = await vrfCoordinatorMockFactory.deploy(linkToken.address);

        const multiRaffleFactory = await ethers.getContractFactory("MultiRaffle");

        const curTime = await getLastTimestamp();
        const startTime = curTime + day;
        const endTime = curTime + 2 * day
        
        multiRaffle = await multiRaffleFactory.deploy(
          "NFT"
          , "NFT"
          , keyHash
          , linkToken.address
          , vrfCoordinatorMock.address
          , mintCost
          , startTime
          , endTime
          , availableSupply
          , maxPerAddress
        );

        await linkToken.transfer(multiRaffle.address, fee.mul(100));
    
    });
      
    describe("bidding", function () {

        it("can't submit bid before raffle is active", async function () {
            await expect(
                multiRaffle.enterRaffle(1)
              ).to.be.revertedWith("Raffle not active");
        });

        it("can't submit bid after raffle has ended", async function () {
            await endRaffle();
            await expect(
                multiRaffle.enterRaffle(1)
              ).to.be.revertedWith("Raffle ended");
        });

        it("can't enter raffle past max mints ", async function () {
            await startRaffle();
            await expect(
                multiRaffle.enterRaffle(10)
              ).to.be.revertedWith("Max mints for address reached");
        });

        it("creates correct number of entries", async function () {
            await startRaffle();
            const numTickets = 8;
           
            await submitEntry(owner, numTickets);
            const numEntries = await multiRaffle.entriesPerAddress(owner.address);
            expect(numTickets).to.eq(numEntries);
        });
    });

    describe("clearing", function () {

        it("raffle can be cleared", async function () {
            await startRaffle();
            const numTickets = 8;
            await submitEntry(owner, numTickets);
            await submitEntry(addr1, numTickets);
            await submitEntry(addr2, numTickets);
            await endRaffle();

            await clearRaffle();

            const shuffleCount = await multiRaffle.shuffledCount();
            expect(shuffleCount).to.eq(availableSupply);

        });

        it("can mint winning tickets", async function () {
            await startRaffle();
            const numTickets = 8;
            await submitEntry(owner, numTickets);
            await submitEntry(addr1, numTickets);
            await submitEntry(addr2, numTickets);
            await endRaffle();

            await clearRaffle();
            const winningIndices = await getWinningIndices(addr1);

            await multiRaffle.connect(addr1).claimRaffle(winningIndices);

            const balance = await multiRaffle.balanceOf(addr1.address);
            expect(balance).to.be.gt(0);
        });
    });
    
});

