// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import "./BatchRevealBase.sol";

/// @notice A contract for raffle-based NFT distribution. 
/// This is purely factoring out functionality from the original MultiRaffle.sol contract, 
/// i.e. all code here was written by the original author. 
/// source: https://github.com/Anish-Agnihotri/MultiRaffle/blob/master/src/MultiRaffle.sol
contract MultiRaffle is BatchRevealBase {

    /// ============ Immutable storage ============

    /// @notice Maximum mints per address
    uint256 public immutable MAX_PER_ADDRESS;

     /// ============ Mutable storage ============


    /// @notice Number of raffle entries that have been shuffled
    uint256 public shuffledCount = 0;
    /// @notice Chainlink entropy collected for clearing
    bool public clearingEntropySet = false;
    /// @notice Array of raffle entries
    address[] public raffleEntries;
    /// @notice Address to number of raffle entries
    mapping(address => uint256) public entriesPerAddress;
    /// @notice Ticket to raffle claim status
    mapping(uint256 => bool) public ticketClaimed;

    /// ============ Events ============

    /// @notice Emitted after a successful raffle entry
    /// @param user Address of raffle participant
    /// @param entries Number of entries from participant
    event RaffleEntered(address indexed user, uint256 entries);

    /// @notice Emitted after a successful partial or full shuffle
    /// @param user Address of shuffler
    /// @param numShuffled Number of entries shuffled
    event RaffleShuffled(address indexed user, uint256 numShuffled);

    /// @notice Emitted after user claims winning and/or losing raffle tickets
    /// @param user Address of claimer
    /// @param winningTickets Number of NFTs minted
    /// @param losingTickets Number of losing raffle tickets refunded
    event RaffleClaimed(address indexed user, uint256 winningTickets, uint256 losingTickets);


    constructor(
        string memory _NFT_NAME,
        string memory _NFT_SYMBOL,
        bytes32 _LINK_KEY_HASH,
        address _LINK_ADDRESS,
        address _LINK_VRF_COORDINATOR_ADDRESS,
        uint256 _MINT_COST,
        uint256 _RAFFLE_START_TIME,
        uint256 _RAFFLE_END_TIME,
        uint256 _AVAILABLE_SUPPLY,
        uint256 _MAX_PER_ADDRESS
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
        mintCost = _MINT_COST;
        MAX_PER_ADDRESS = _MAX_PER_ADDRESS;
    }

    /// @notice Enters raffle with numTickets entries
    /// @param numTickets Number of raffle entries
    function enterRaffle(uint256 numTickets) external payable {
        // Ensure raffle is active
        require(block.timestamp >= RAFFLE_START_TIME, "Raffle not active");
        // Ensure raffle has not ended
        require(block.timestamp <= RAFFLE_END_TIME, "Raffle ended");
        // Ensure number of tickets to acquire <= max per address
        require(
            entriesPerAddress[msg.sender] + numTickets <= MAX_PER_ADDRESS, 
            "Max mints for address reached"
        );
        // Ensure sufficient raffle ticket payment
        require(msg.value == numTickets * mintCost, "Incorrect payment");

        // Increase mintsPerAddress to account for new raffle entries
        entriesPerAddress[msg.sender] += numTickets;

        // Add entries to array of raffle entries
        for (uint256 i = 0; i < numTickets; i++) {
            raffleEntries.push(msg.sender);
        }

        numBids += numTickets;

        // Emit successful entry
        emit RaffleEntered(msg.sender, numTickets);
    }

    /// @notice Fulfills randomness from Chainlink VRF
    /// @param requestId returned id of VRF request
    /// @param randomness random number from VRF
    function fulfillRandomness(bytes32 requestId, uint256 randomness) internal override {
        // If auction is cleared
        // Or, if auction does not need clearing
        if (clearingEntropySet || raffleEntries.length < AVAILABLE_SUPPLY) {
            fullfillRandomnessForMetadata(randomness);
        }
        // Else, set entropy
        entropy = randomness;
        // Update entropy set status
        clearingEntropySet = true;
    }

    /// @notice Allows partially or fully clearing a raffle (if needed)
    /// @param numShuffles Number of indices to shuffle (max = remaining)
    function clearRaffle(uint256 numShuffles) external {
        // Ensure raffle has ended
        require(block.timestamp > RAFFLE_END_TIME, "Raffle has not ended");
        // Ensure raffle requires clearing (entries !< supply)
        require(raffleEntries.length > AVAILABLE_SUPPLY, "Raffle does not need clearing");
        // Ensure raffle requires clearing (already cleared)
        require(shuffledCount != AVAILABLE_SUPPLY, "Raffle has already been cleared");
        // Ensure number to shuffle <= required number of shuffles
        require(numShuffles <= AVAILABLE_SUPPLY - shuffledCount, "Excess indices to shuffle");
        // Ensure clearing entropy for shuffle randomness is set
        require(clearingEntropySet, "No entropy to clear raffle");

        // Run Fisher-Yates shuffle for AVAILABLE_SUPPLY
        for (uint256 i = shuffledCount; i < shuffledCount + numShuffles; i++) {
            // Generate a random index to select from
            uint256 randomIndex = i + entropy % (raffleEntries.length - i);
            // Collect the value at that random index
            address randomTmp = raffleEntries[randomIndex];
            // Update the value at the random index to the current value
            raffleEntries[randomIndex] = raffleEntries[i];
            // Update the current value to the value at the random index
            raffleEntries[i] = randomTmp;
        }

        // Update number of shuffled entries
        shuffledCount += numShuffles;

        // Emit successful shuffle
        emit RaffleShuffled(msg.sender, numShuffles);
    }

    /// @notice Allows user to mint NFTs for winning tickets or claim refund for losing tickets
    /// @param tickets indices of all raffle tickets owned by caller
    function claimRaffle(uint256[] calldata tickets) external {
        // Ensure raffle has ended
        require(block.timestamp > RAFFLE_END_TIME, "Raffle has not ended");
        // Ensure raffle has been cleared
        require(
            // Either no shuffling required
            (raffleEntries.length < AVAILABLE_SUPPLY)
            // Or, shuffling completed
            || (shuffledCount == AVAILABLE_SUPPLY),
            "Raffle has not been cleared"
        );

        // Mint NFTs to winning tickets
        uint256 tmpCount = nftCount;
        for (uint256 i = 0; i < tickets.length; i++) {
            // Ensure ticket is in range
            require(tickets[i] < raffleEntries.length, "Ticket is out of entries range");
            // Ensure ticket has not already been claimed
            require(!ticketClaimed[tickets[i]], "Ticket already claimed");
            // Ensure ticket is owned by caller
            require(raffleEntries[tickets[i]] == msg.sender, "Ticket owner mismatch");

            // Toggle ticket claim status
            ticketClaimed[tickets[i]] = true;

            // If ticket is a winner
            if (tickets[i] + 1 <= AVAILABLE_SUPPLY) {
                // Mint NFT to caller
                _safeMint(msg.sender, nftCount + 1);
                // Increment number of minted NFTs
                nftCount++;
            }
        }
        // Calculate number of winning tickets from newly minted
        uint256 winningTickets = nftCount - tmpCount;

        // Refund losing tickets
        if (winningTickets != tickets.length) {
            // Payout value equal to number of bought tickets - paid for winning tickets
            (bool sent, ) = payable(msg.sender).call{
                value: (tickets.length - winningTickets) * mintCost
            }("");
            require(sent, "Unsuccessful in refund");
        }

        // Emit claim event
        emit RaffleClaimed(msg.sender, winningTickets, tickets.length - winningTickets);
    }

    /// @notice Sets entropy for clearing via shuffle
    function setClearingEntropy() external returns (bytes32 requestId) {
        // Ensure raffle has ended
        require(block.timestamp > RAFFLE_END_TIME, "Raffle still active");
        // Ensure contract has sufficient LINK balance
        require(LINK_TOKEN.balanceOf(address(this)) >= 2e18, "Insufficient LINK");
        // Ensure raffle requires entropy (entries !< supply)
        require(raffleEntries.length > AVAILABLE_SUPPLY, "Raffle does not need entropy");
        // Ensure raffle requires entropy (entropy not already set)
        require(!clearingEntropySet, "Clearing entropy already set");

        // Request randomness from Chainlink VRF
        return requestRandomness(KEY_HASH, 2e18);
    }
}
