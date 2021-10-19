//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "./BatchRevealBase.sol";
import "./libraries/MinPriorityQueue.sol";

import "hardhat/console.sol";

///@notice an implementation of "smart batched auctions" for ERC721. Users are able to enter 
///bids with a specified quantity and price during a bidding phase. After the bidding phase is over, 
///a clearing price is computed by matching the highest-priced orders with available supply. The 
///auction clears at a uniform price, i.e. the lowest price that clears all supply. 
contract BatchAuction is BatchRevealBase {
    using MinPriorityQueue for MinPriorityQueue.Queue;

    /// @notice Minimum bid price 
    uint256 public immutable MIN_BID_PRICE;

    /// @notice priority queue holding currently winning bids 
    MinPriorityQueue.Queue public bidPriorityQueue;

    /// @notice total amount paid for by user
    mapping(address => uint256) public balanceContributed;

    /// @notice event emitted when a new bid is entered
    event BidEntered(address indexed user, uint256 quantity, uint256 price);

    /// @notice event emitted when claim to mint quantity and get refund
    event Claimed(address indexed user, uint256 quantity);

    constructor(
        string memory _NFT_NAME,
        string memory _NFT_SYMBOL,
        bytes32 _LINK_KEY_HASH,
        address _LINK_ADDRESS,
        address _LINK_VRF_COORDINATOR_ADDRESS,
        uint256 _RAFFLE_START_TIME,
        uint256 _RAFFLE_END_TIME,
        uint256 _AVAILABLE_SUPPLY,
        uint256 _MIN_BID_PRICE
    ) 
        BatchRevealBase(
            _NFT_NAME,
            _NFT_SYMBOL,
            _LINK_KEY_HASH,
            _LINK_ADDRESS,
            _LINK_VRF_COORDINATOR_ADDRESS,
            _RAFFLE_START_TIME,
            _RAFFLE_END_TIME,
            _AVAILABLE_SUPPLY
        )
    {
        //priority queue requires initialization prior to use 
        bidPriorityQueue.initialize();
        MIN_BID_PRICE = _MIN_BID_PRICE;
    }

    ///@notice enter a bid for a specified quantity and price. 
    function enterBid(uint256 quantity, uint256 price) external payable {
        require(block.timestamp >= RAFFLE_START_TIME, "Raffle not active");
        require(block.timestamp <= RAFFLE_END_TIME, "Raffle ended");
        require(price >= MIN_BID_PRICE, "Insufficient price for bid");
        require(msg.value == quantity * price, "Incorrect payment");

        //keep track of total contribution by user
        balanceContributed[msg.sender] += msg.value;

        //first, accept all bids while there is still available supply 
        uint256 remainingSupply = AVAILABLE_SUPPLY - numBids;
        //min between remaining supply and quantity 
        uint256 fillAtAnyPriceQuantity = remainingSupply < quantity ? remainingSupply : quantity;

        if (fillAtAnyPriceQuantity > 0) {
            bidPriorityQueue.insert(msg.sender, price, fillAtAnyPriceQuantity);
            numBids += fillAtAnyPriceQuantity;
        }

        //if any quantity is still unfilled, we need to see if the price beats the lowest bids
        uint256 unfilledQuantity = quantity - fillAtAnyPriceQuantity;
        //process as many bids as possible given current prices
        unfilledQuantity = processBidsInQueue(unfilledQuantity, price);
        uint256 filledQuantity = quantity - unfilledQuantity;
        if(filledQuantity > 0) {
            //update current mint cost
            mintCost = bidPriorityQueue.getMin().price;
            emit BidEntered(msg.sender, filledQuantity, price);
        }
    }

    ///@notice mints NFTs for winning bids, and refunds all remaining contributions
    function claim() public {
        require(block.timestamp > RAFFLE_END_TIME, "Raffle has not ended");
        //clearing price is the price of the min bid at the time the bidding period is over
        uint256 clearingPrice = bidPriorityQueue.getMin().price;
        uint256 balance = balanceContributed[msg.sender];
        uint256[] storage winningBidIds = bidPriorityQueue.ownerToBidIds[msg.sender];
        //iterate through winning bids, minting correct quantity for user
        uint256 curNFTCount = nftCount;
        for(uint256 i = 0; i < winningBidIds.length; i++) {
            uint256 curBidId = winningBidIds[i];
            Bid storage curBid = bidPriorityQueue.bidIdToBidMap[curBidId];
            for(uint256 j = 0; j < curBid.quantity; j++) {
                _safeMint(msg.sender, ++nftCount);
            }
            //charge user quantity times clearing price
            balance -= curBid.quantity * clearingPrice;
            curBid.quantity = 0;
        }
        //refund any contributions not spent on mint
        (bool sent, ) = payable(msg.sender).call{value: balance}("");
        require(sent, "Unsuccessful in refund");
        emit Claimed(msg.sender, nftCount - curNFTCount);
    }

    ///@notice try to accept bid for specifc quantity and price. Return unfilled quantity
    function processBidsInQueue(uint256 quantity, uint256 price) private returns (uint256) {
        //loop while we are still trying to fill bids
        while(quantity > 0) {

            //get current lowest bid
            Bid storage lowestBid = bidPriorityQueue.getMin();
            //if we can't beat lowest bid, break
            if (lowestBid.price >= price) {
                break;
            }
            uint256 lowestBidQuantity = lowestBid.quantity;

            //if lowest bid has higher quantity that what we need to fill, 
            //reduce that bid's quantity by respective amount
            if(lowestBidQuantity > quantity) {
                //reduce quantity of lowest bid. This can be safely done in place
                lowestBid.quantity -= quantity;
                //put new bid in queue
                bidPriorityQueue.insert(msg.sender, price, quantity);
                quantity = 0;
            }
            //else we remove lowest bid completely 
            else {
                //eliminate lowest bid
                bidPriorityQueue.delMin();
                //fill appropriate quantity of new bid
                bidPriorityQueue.insert(msg.sender, price, lowestBidQuantity);
                //update quantity that we still need to fill
                quantity -= lowestBidQuantity;
            }
        }
        return quantity;
    }

    function getUserBidIds(address addr) public view returns (uint256[] memory) {
        return bidPriorityQueue.ownerToBidIds[addr];
    }

    function getBidById(uint256 id) public view returns (Bid memory) {
        return bidPriorityQueue.bidIdToBidMap[id];
    }
}