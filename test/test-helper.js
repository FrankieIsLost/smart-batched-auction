async function getLastTimestamp() {
    const blockNumBefore = await ethers.provider.getBlockNumber();
    const blockBefore = await ethers.provider.getBlock(blockNumBefore);
    return blockBefore.timestamp;
}

async function increaseBlockTime(seconds) {
    await network.provider.send("evm_increaseTime", [seconds])
    await network.provider.send("evm_mine")
}

async function startRaffle() {
    await increaseBlockTime(1 * day);
}

async function endRaffle() {
    await increaseBlockTime(3 * day);
}

const day = 60 * 60 * 24;



module.exports = {
    getLastTimestamp: getLastTimestamp, 
    increaseBlockTime: increaseBlockTime,
    startRaffle: startRaffle, 
    endRaffle: endRaffle, 
    day: day
}