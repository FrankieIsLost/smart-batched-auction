const { expect } = require("chai");
const { ethers } = require("hardhat");
const {startRaffle, endRaffle, getLastTimestamp, day} = require("./test-helper");


//issue with chainlink provided mocks causes extra WARNING logs 
//in current version of ethers. Restricting logs to ERROR only until patch. 
//See  https://github.com/ethers-io/ethers.js/issues/905 
const Logger = ethers.utils.Logger;
Logger.setLogLevel(Logger.levels.ERROR)

describe("Batch Auction", function () {

    let owner;
    let addr1;
    let addr2;
    let addr3;
    let addrs;
  
    let vrfCoordinatorMock;
    let batchAuction;

    
    //hardhat network
    const fee = ethers.BigNumber.from("100000000000000000");
    const keyHash = '0x6c3699283bda56ad74f6b855546325b68d482e983852a7a82979cc4807b641f4';

    const minBidPrice = ethers.utils.parseEther('0.1');
    const availableSupply = 10;

    async function submitBid(signer, quantity, price) {
        const val = price.mul(quantity);
        await batchAuction.connect(signer).enterBid(quantity, price, {value:val});
    }

    async function getUserBids(signer) {
        const curBidIds = await batchAuction.getUserBidIds(signer.address);
        const bids = [];
        for(let i = 0; i < curBidIds.length; i++) {
            bids.push(await batchAuction.getBidById(curBidIds[i]));
        }
        return bids;
    }

    async function claimAndCalculateRefund(signer) {
        const initialBalance =  await ethers.provider.getBalance(signer.address);
        const receipt = await (await batchAuction.connect(signer).claim()).wait();
        const gasSpent = receipt.cumulativeGasUsed.mul(receipt.effectiveGasPrice);
        const finalBalance = await ethers.provider.getBalance(signer.address);
        const totalRefund = finalBalance.sub(initialBalance).add(gasSpent);
        return totalRefund;
    }

    async function withdrawAndCalculateProceeds(signer) {
        const initialBalance =  await ethers.provider.getBalance(signer.address);
        const receipt = await (await batchAuction.connect(signer).withdrawProceeds()).wait();
        const gasSpent = receipt.cumulativeGasUsed.mul(receipt.effectiveGasPrice);
        const finalBalance = await ethers.provider.getBalance(signer.address);
        const totalProceeds = finalBalance.sub(initialBalance).add(gasSpent);
        return totalProceeds;
    }

    async function tokenHasMetadata(tokenId) {
        const uri = await batchAuction.tokenURI(tokenId);
        const matches = uri.match(/<text [^>]+>(.*?)<\/text>/);
        const match = matches[1];
        return match != 'No randomness assigned';
    }

    beforeEach(async function () {

        [owner, addr1, addr2, addr3,  ...addrs] = await ethers.getSigners();
    
        const linkTokenFactory = await ethers.getContractFactory("LinkToken");
        const linkToken = await linkTokenFactory.deploy();
    
        const vrfCoordinatorMockFactory = await ethers.getContractFactory("VRFCoordinatorMock");
        vrfCoordinatorMock = await vrfCoordinatorMockFactory.deploy(linkToken.address);

        const curTime = await getLastTimestamp();
        const startTime = curTime + day;
        const endTime = curTime + 2 * day

        const minPQFactory = await ethers.getContractFactory("MinPriorityQueue");
        const minPQ = await minPQFactory.deploy();
        const batchAuctionFactory = await ethers.getContractFactory("BatchAuction", {
            libraries: {
                MinPriorityQueue: minPQ.address,
            }
        });
        
        batchAuction = await batchAuctionFactory.deploy(
          "NFT"
          , "NFT"
          , keyHash
          , linkToken.address
          , vrfCoordinatorMock.address
          , startTime
          , endTime
          , availableSupply
          , minBidPrice
        );

        await linkToken.transfer(batchAuction.address, fee.mul(100));
    });
      
    describe("bidding", function () {

        it("can't submit bid before raffle is active", async function () {
            await expect(
                batchAuction.enterBid(1, minBidPrice)
              ).to.be.revertedWith("Raffle not active");
        });

        it("can't submit bid after raffle has ended", async function () {
            await endRaffle();
            await expect(
                batchAuction.enterBid(1, minBidPrice)
              ).to.be.revertedWith("Raffle ended");
        });

        it("can't submit bid below min ", async function () {
            await startRaffle();
            await expect(
                batchAuction.enterBid(1, minBidPrice.sub(1))
              ).to.be.revertedWith("Insufficient price for bid");
        });
    

        it("can submit min bid when available supply remain", async function () {
            await startRaffle();
            const quantity = 3;
            const price = minBidPrice;
            await submitBid(owner, quantity, price);
            const bids = await getUserBids(owner);
            expect(bids[0].quantity).to.eq(quantity);
            expect(bids[0].price).to.eq(price);
        });

        it("can fill partially", async function () {
            await startRaffle();
            await submitBid(owner, 7, minBidPrice.add(1));
            await submitBid(addr1, 5, minBidPrice);
            const bids = await getUserBids(addr1);
            expect(bids[0].quantity).to.eq(3);
            expect(bids[0].price).to.eq(minBidPrice);
        });

        it("won't submit bid below cur min", async function () {
            await startRaffle();
            await submitBid(owner, 10, minBidPrice.add(1));
            await submitBid(addr1, 5, minBidPrice);
            const bids = await getUserBids(addr1);
            expect(bids.length).to.eq(0);
        });
    
      });

      describe("claims", function () {
        it("process refunds correctly", async function () {
            await startRaffle();
            await submitBid(owner, 10, minBidPrice);
            await submitBid(addr1, 10, minBidPrice.add(1));
            await endRaffle();
            let refund = await claimAndCalculateRefund(owner);
            expect(refund).to.eq(minBidPrice.mul(10));
            refund = await claimAndCalculateRefund(addr1);
            expect(refund).to.eq(minBidPrice.mul(0));

        });

        it("mints for winners", async function () {
            await startRaffle();
            
            await submitBid(addr2, 10, minBidPrice);
            await submitBid(owner, 10, minBidPrice.add(1));
            await submitBid(addr1, 7, minBidPrice.add(2));
            
            await endRaffle();
            
            await claimAndCalculateRefund(owner);
            await claimAndCalculateRefund(addr1);
            expect(await batchAuction.balanceOf(owner.address)).to.eq(3)
            expect(await batchAuction.balanceOf(addr1.address)).to.eq(7)
        });
    
      });

      describe("withdrawal", function () {
        it("withdraws right amount for partial mint ", async function () {
            await startRaffle();
            await submitBid(addr1, 3, minBidPrice);
            await submitBid(addr2, 3, minBidPrice.add(1));
            await endRaffle();

            const proceeds = await withdrawAndCalculateProceeds(owner);
            expect(proceeds).to.eq(minBidPrice.mul(6));

        });

        it("withdraws right amount for full mint ", async function () {
            await startRaffle();
            await submitBid(addr1, 3, minBidPrice);
            await submitBid(addr2, 3, minBidPrice.add(1));
            await submitBid(addr3, 8, minBidPrice.add(100));
            await endRaffle();

            const proceeds = await withdrawAndCalculateProceeds(owner);
            expect(proceeds).to.eq(minBidPrice.add(1).mul(10));
        });

    
      });

      describe("metadata", function () {

        it("reveal metadata correctly", async function () {
            await startRaffle();
            await submitBid(addr1, 3, minBidPrice.add(1));
            await submitBid(addr2, 8, minBidPrice.add(100));
            await endRaffle();

            await claimAndCalculateRefund(addr1);
            const curOwner = await batchAuction.ownerOf(1);
            expect(curOwner).to.eq(addr1.address);
            let hasMetadata = await tokenHasMetadata(1);
            expect(hasMetadata).to.be.false;
            await batchAuction.revealPendingMetadata();
            await vrfCoordinatorMock.callBackWithRandomness(ethers.constants.HashZero, 0, batchAuction.address);
            hasMetadata = await tokenHasMetadata(1);
            expect(hasMetadata).to.be.true;
        });

    
      });
});

