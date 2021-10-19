const { expect } = require("chai");
const { ethers } = require("hardhat");
const { getLastTimestamp, endRaffle, day } = require("../test/test-helper");
const path = require('path');

async function main() {
    
    //hardhat network
    const fee = ethers.BigNumber.from("100000000000000000");
    const keyHash = '0x6c3699283bda56ad74f6b855546325b68d482e983852a7a82979cc4807b641f4';
    
    const minBidPrice = ethers.utils.parseEther('0.1');
    const mintCost = minBidPrice;
    const availableSupply = 10000;
    const maxPerAddress = 10000;
    
    
    const [owner, addr1, addr2, ...addrs] = await ethers.getSigners();

    const linkTokenFactory = await ethers.getContractFactory("LinkToken");
    const linkToken = await linkTokenFactory.deploy();

    const vrfCoordinatorMockFactory = await ethers.getContractFactory("VRFCoordinatorMock");
    const vrfCoordinatorMock = await vrfCoordinatorMockFactory.deploy(linkToken.address);

    const curTime = await getLastTimestamp();
    const startTime = curTime;
    const endTime = curTime + 2 * day

    const minPQFactory = await ethers.getContractFactory("MinPriorityQueue");
    const minPQ = await minPQFactory.deploy();
    const batchAuctionFactory = await ethers.getContractFactory("BatchAuction", {
        libraries: {
            MinPriorityQueue: minPQ.address,
        }
    });
    
    const batchAuction = await batchAuctionFactory.deploy(
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

    const multiRaffleFactory = await ethers.getContractFactory("MultiRaffle");
    
    const multiRaffle = await multiRaffleFactory.deploy(
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

    const createCsvWriter = require('csv-writer').createObjectCsvWriter
    const csvWriter = createCsvWriter({
        path: path.resolve(__dirname, '../output/gascosts.csv'),
        header: [
            { id: 'bidNumber', title: 'bidNumber' },
            { id: 'batchAuctionCost', title: 'batchAuctionCost' },
            { id: 'multiRaffleCost', title: 'multiRaffleCost' }
        ]
    })

    const basePrice = ethers.utils.parseEther("0.2");
    const averageMintSize = 5;

    for(let i = 0; i < availableSupply / averageMintSize; i++) {
        const curPrice = basePrice.sub(i);

        let receipt = await (await batchAuction.enterBid(averageMintSize, curPrice, {value:curPrice.mul(averageMintSize)})).wait();
        const batchAuctionGas = receipt.gasUsed.toString();

        receipt = await (await multiRaffle.enterRaffle(averageMintSize, {value:mintCost.mul(averageMintSize)})).wait();
        const multiRaffleGas = receipt.gasUsed.toString();

        
        await csvWriter.writeRecords([{
            bidNumber: i * averageMintSize,
            batchAuctionCost: batchAuctionGas,
            multiRaffleCost: multiRaffleGas
        }])
    }

    await endRaffle();
    await multiRaffle.setClearingEntropy();
    await vrfCoordinatorMock.callBackWithRandomness(ethers.constants.HashZero, 0, multiRaffle.address);
    receipt = await (await multiRaffle.clearRaffle(availableSupply)).wait();

    let clearingCost = receipt.gasUsed.toString();
    console.log("clearing cost for raffle: ", clearingCost);

}



main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error)
    process.exit(1)
  });

