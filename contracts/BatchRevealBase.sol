// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import "./interfaces/IERC20.sol"; // ERC20 minified interface

import "@openzeppelin/contracts/access/Ownable.sol"; // OZ: Ownership
import "@openzeppelin/contracts/token/ERC721/ERC721.sol"; // OZ: ERC721 
import "@chainlink/contracts/src/v0.8/VRFConsumerBase.sol"; // Chainlink VRF


/// @notice A base contract for batch-revealed, randomized metadata ERC721. 
/// This is purely factoring out functionality from the original MultiRaffle.sol contract, 
/// i.e. all code here was written by the original author. 
/// source: https://github.com/Anish-Agnihotri/MultiRaffle/blob/master/src/MultiRaffle.sol
abstract contract BatchRevealBase is Ownable, ERC721, VRFConsumerBase {

     /// ============ Structs ============

    /// @notice Metadata for range of tokenIds
    struct Metadata {
        // Starting index (inclusive)
        uint256 startIndex;
        // Ending index (exclusive)
        uint256 endIndex;
        // Randomness for range of tokens
        uint256 entropy;
    }

    /// ============ Immutable storage ============

    /// @notice LINK token
    IERC20 public immutable LINK_TOKEN;
    /// @dev Chainlink key hash
    bytes32 internal immutable KEY_HASH;
    /// @notice Start time for raffle
    uint256 public immutable RAFFLE_START_TIME;
    /// @notice End time for raffle
    uint256 public immutable RAFFLE_END_TIME;
    /// @notice Available NFT supply
    uint256 public immutable AVAILABLE_SUPPLY;

    /// ============ Mutable storage ============

    /// @notice Entropy from Chainlink VRF
    uint256 public entropy;
    /// @notice Number of NFTs minted
    uint256 public nftCount = 0;
    /// @notice Number of NFTs w/ metadata revealed
    uint256 public nftRevealedCount = 0;
    /// @notice Array of NFT metadata
    Metadata[] public metadatas;
    /// @notice Owner has claimed raffle proceeds
    bool public proceedsClaimed = false;
     /// @notice Cost to mint each NFT (in wei)
    uint256 public mintCost;
     /// @notice number of bids committed 
    uint256 public numBids;

     /// ============ Events ============

    /// @notice Emitted after owner claims raffle proceeds
    /// @param owner Address of owner
    /// @param amount Amount of proceeds claimed by owner
    event RaffleProceedsClaimed(address indexed owner, uint256 amount);

    /// ============ Constructor ============

    /// @notice Creates a new NFT distribution contract
    /// @param _NFT_NAME name of NFT
    /// @param _NFT_SYMBOL symbol of NFT
    /// @param _LINK_KEY_HASH key hash for LINK VRF oracle
    /// @param _LINK_ADDRESS address to LINK token
    /// @param _LINK_VRF_COORDINATOR_ADDRESS address to LINK VRF Coordinator
    /// @param _RAFFLE_START_TIME in seconds to begin raffle
    /// @param _RAFFLE_END_TIME in seconds to end raffle
    /// @param _AVAILABLE_SUPPLY total NFTs to sell
    constructor(
        string memory _NFT_NAME,
        string memory _NFT_SYMBOL,
        bytes32 _LINK_KEY_HASH,
        address _LINK_ADDRESS,
        address _LINK_VRF_COORDINATOR_ADDRESS,
        uint256 _RAFFLE_START_TIME,
        uint256 _RAFFLE_END_TIME,
        uint256 _AVAILABLE_SUPPLY
    ) 
        VRFConsumerBase(
            _LINK_VRF_COORDINATOR_ADDRESS,
            _LINK_ADDRESS
        )
        ERC721(_NFT_NAME, _NFT_SYMBOL)
    {
        LINK_TOKEN = IERC20(_LINK_ADDRESS);
        KEY_HASH = _LINK_KEY_HASH;
        RAFFLE_START_TIME = _RAFFLE_START_TIME;
        RAFFLE_END_TIME = _RAFFLE_END_TIME;
        AVAILABLE_SUPPLY = _AVAILABLE_SUPPLY;
    }


    /// @notice Reveals metadata for all NFTs with reveals pending (batch reveal)
    function revealPendingMetadata() external returns (bytes32 requestId) {
        // Ensure raffle has ended
        // Ensure at least 1 NFT has been minted
        // Ensure at least 1 minted NFT requires metadata
        require(nftCount - nftRevealedCount > 0, "No NFTs pending metadata reveal");
        // Ensure contract has sufficient LINK balance
        require(LINK_TOKEN.balanceOf(address(this)) >= 2e18, "Insufficient LINK");

        // Request randomness from Chainlink VRF
        return requestRandomness(KEY_HASH, 2e18);
    }

    function fullfillRandomnessForMetadata(uint256 randomness) internal {
        // Push new metadata (end index non-inclusive)
        metadatas.push(Metadata({
                startIndex: nftRevealedCount + 1,
                endIndex: nftCount + 1,
                entropy: randomness
            }));
        // Update number of revealed NFTs
        nftRevealedCount = nftCount;
    }

    /// @notice Fulfills randomness from Chainlink VRF
    /// @param requestId returned id of VRF request
    /// @param randomness random number from VRF
    function fulfillRandomness(bytes32 requestId, uint256 randomness) internal override virtual {
        fullfillRandomnessForMetadata(randomness);
    }

    /// @notice Allows contract owner to withdraw proceeds of winning tickets
    function withdrawProceeds() external onlyOwner {
        // Ensure raffle has ended
        require(block.timestamp > RAFFLE_END_TIME, "Raffle has not ended");
        // Ensure proceeds have not already been claimed
        require(!proceedsClaimed, "Proceeds already claimed");

        // Toggle proceeds being claimed
        proceedsClaimed = true;

        // proceeds are equal to final mint price times number of bids 
        uint256 proceeds = mintCost * numBids;

        // Pay owner proceeds
        (bool sent, ) = payable(msg.sender).call{value: proceeds}(""); 
        require(sent, "Unsuccessful in payout");

        // Emit successful proceeds claim
        emit RaffleProceedsClaimed(msg.sender, proceeds);
    }

    /// ============ Developer-defined functions ============

    /// @notice Returns metadata about a token (depending on randomness reveal status)
    /// @dev Partially implemented, returns only example string of randomness-dependent content
    function tokenURI(uint256 tokenId) override public view returns (string memory) {
        uint256 randomness;
        bool metadataCleared;
        string[3] memory parts;

        for (uint256 i = 0; i < metadatas.length; i++) {
            if (tokenId >= metadatas[i].startIndex && tokenId < metadatas[i].endIndex) {
                randomness = metadatas[i].entropy;
                metadataCleared = true;
            }
        }

        parts[0] = '<svg xmlns="http://www.w3.org/2000/svg" preserveAspectRatio="xMinYMin meet" viewBox="0 0 350 350"><style>.base { fill: white; font-family: serif; font-size: 14px; }</style><rect width="100%" height="100%" fill="black" /><text x="10" y="20" class="base">';

        if (metadataCleared) {
            parts[1] = string(abi.encodePacked('Randomness: ', _toString(randomness)));
        } else {
            parts[1] = 'No randomness assigned';
        }

        parts[2] = '</text></svg>';
        string memory output = string(abi.encodePacked(parts[0], parts[1], parts[2]));

        return output;
    }

    /// @notice Converts a uint256 to its string representation
    /// @dev Inspired by OraclizeAPI's implementation
    function _toString(uint256 value) internal pure returns (string memory) {
        if (value == 0) {
            return "0";
        }
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }
}