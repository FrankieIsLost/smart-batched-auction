//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "hardhat/console.sol";

struct Bid {
    uint256 bidId;
    address owner;
    uint256 price;
    uint256 quantity;
}

///@notice a min priority queue implementation, based off https://algs4.cs.princeton.edu/24pq/MinPQ.java.html
library MinPriorityQueue {

    struct Queue {
        ///@notice incrementing bid id
        uint256 nextBidId;
        ///@notice array backing priority queue
        uint256[] bidIdList;
        ///@notice total number of bids in queue 
        uint256 numBids;
        //@notice map bid ids to bids
        mapping(uint256 => Bid) bidIdToBidMap;
        ///@notice map addreses to bids they own
        mapping(address => uint256[]) ownerToBidIds;
    }

    ///@notice initialize must be called before using queue. 
    function initialize(Queue storage self) public {
        self.bidIdList.push(0);
        self.nextBidId = 1;
    }

    function isEmpty(Queue storage self) public view returns (bool) {
        return self.numBids == 0;
    }

    function getNumBids(Queue storage self) public view returns (uint256) {
        return self.numBids;
    }

    ///@notice view min bid
    function getMin(Queue storage self) public view returns (Bid storage) {
        require(!isEmpty(self), "nothing to return");
        uint256 minId = self.bidIdList[1];
        return self.bidIdToBidMap[minId];
    }

    ///@notice move bid up heap
    function swim(Queue storage self, uint256 k) private {
        while(k > 1 && isGreater(self, k/2, k)) {
            exchange(self, k, k/2);
            k = k/2;
        }
    }

    ///@notice move bid down heap
    function sink(Queue storage self, uint256 k) private {
        while(2 * k <= self.numBids) {
            uint256 j = 2 * k;
            if(j < self.numBids && isGreater(self, j, j+1)) {
                j++;
            }
            if (!isGreater(self, k, j)) {
                break;
            }
            exchange(self, k, j);
            k = j;
        }
    }

    ///@notice insert bid in heap 
    function insert(Queue storage self, address owner, uint256 price, uint256 quantity) public {
        insert(self, Bid(self.nextBidId++, owner, price, quantity));
    }

    ///@notice insert bid in heap 
    function insert(Queue storage self, Bid memory bid) private {
        self.bidIdList.push(bid.bidId);
        self.bidIdToBidMap[bid.bidId] = bid;
        self.numBids += 1;
        swim(self, self.numBids);
        self.ownerToBidIds[bid.owner].push(bid.bidId);
    }

     ///@notice delete min bid from heap and return
    function delMin(Queue storage self) public returns (Bid memory) {
        require(!isEmpty(self), "nothing to delete");
        Bid memory min = self.bidIdToBidMap[self.bidIdList[1]];
        exchange(self, 1, self.numBids--);
        self.bidIdList.pop();
        delete self.bidIdToBidMap[min.bidId];
        sink(self, 1);
        uint256[] storage curUserBids = self.ownerToBidIds[min.owner];
        for(uint256 i = 0; i < curUserBids.length; i++) {
            if(curUserBids[i] == min.bidId) {
                //remove from array and delete struct
                curUserBids[i] = curUserBids[curUserBids.length - 1];
                curUserBids.pop();
                break;
            }
        }
        return min;
    }

    ///@notice helper function to determine ordering. When two bids have the same price, give priority 
    ///to the one with the larger quantity 
    function isGreater(Queue storage self, uint256 i, uint256 j) private view returns (bool) {
        Bid memory bidI = self.bidIdToBidMap[self.bidIdList[i]];
        Bid memory bidJ = self.bidIdToBidMap[self.bidIdList[j]];
        if(bidI.price == bidJ.price) {
            return bidI.quantity < bidJ.quantity;
        }
        return bidI.price > bidJ.price;
    } 

    ///@notice helper function to exchange to bids in the heap
    function exchange(Queue storage self, uint256 i, uint256 j) private {
        uint256 tempId = self.bidIdList[i];
        self.bidIdList[i] = self.bidIdList[j];
        self.bidIdList[j] = tempId;
    }



  
}