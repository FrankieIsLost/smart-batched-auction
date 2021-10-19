//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "../libraries/MinPriorityQueue.sol";

///@notice helper contract to test MinPriorityQueue library
contract TestPriorityQueue {
    using MinPriorityQueue for MinPriorityQueue.Queue;

    MinPriorityQueue.Queue public minPQ;

    constructor() {
        minPQ.initialize();
    }

    function isEmpty() public view returns (bool) {
        return minPQ.isEmpty();
    }

    function getNumBids() public view returns (uint256) {
        return minPQ.getNumBids();
    }


    function getMin() public view returns (Bid memory) {
        return minPQ.getMin();
    }
    
    function insert(address owner, uint256 price, uint256 quantity) public {
        minPQ.insert(owner, price, quantity);
    }

    function delMin() public returns (Bid memory) {
        return minPQ.delMin();
    }

    function getMinPrice() public view returns (uint256) {
        return minPQ.getMin().price;
    }
}