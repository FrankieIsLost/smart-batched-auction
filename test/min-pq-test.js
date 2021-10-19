const { expect } = require("chai");

describe("Min Priority Queue", function () {

    let testPQ;
    let owner;
    let addrs;

    async function insertBid(price) {
        await testPQ.insert(owner.address, price, 1);
    }

    beforeEach(async function () {

        const minPQFactory = await ethers.getContractFactory("MinPriorityQueue");
        const minPQ = await minPQFactory.deploy();

        const TestPQFactory = await ethers.getContractFactory("TestPriorityQueue",
        {
            libraries: {
                MinPriorityQueue: minPQ.address,
            }
        });
        testPQ = await TestPQFactory.deploy();
        [owner, ...addrs] = await ethers.getSigners();
    });

    
    it("should be empty after initialization", async function () {
        const size = await testPQ.getNumBids();
        expect(size).to.equal(0);
    });

    it("should increment size", async function () {
        await insertBid(1);
        const size = await testPQ.getNumBids();
        expect(size).to.equal(1);
    });

    it("should return min", async function () {
        for(let j = 0; j < 8; j++) {
            await insertBid(j);
        }
        let curMinPrice = await testPQ.getMinPrice();
        expect(curMinPrice).to.eq(0);
        await testPQ.delMin();
        curMinPrice = await testPQ.getMinPrice();
        expect(curMinPrice).to.eq(1);
    });

    it("should return min correctly after inserts and deletes", async function () {
        const numItems = 100
        const max = 1000;

        let curMin = max;
        let curMax = 0;
        for(let j = 0; j < numItems; j++) {
            const rand = getRandomInt(max)
            await insertBid(rand);
            curMax = Math.max(curMax, rand);
            curMin = Math.min(curMin, rand);
            pqMin = await testPQ.getMinPrice();
            expect(curMin).to.eq(pqMin);
        }        

        for(let j = 0; j < numItems-1; j++) {
            await testPQ.delMin();
        }
        expect(await testPQ.getNumBids()).to.eq(1);
        curMinPrice = await testPQ.getMinPrice();
        expect(curMinPrice).to.eq(curMax);

        curMin = curMax;
        for(let j = 0; j < numItems; j++) {
            const rand = getRandomInt(max)
            await insertBid(rand);
            curMin = Math.min(curMin, rand);
        }

        curMinPrice = await testPQ.getMinPrice();
        expect(curMinPrice).to.eq(curMin);
    });

});

function getRandomInt(max) {
    return Math.floor(Math.random() * max);
  }