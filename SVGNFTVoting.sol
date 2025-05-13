// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/Base64.sol";

contract SVGNFTVoting is ERC721, Ownable {
    using Counters for Counters.Counter;
    Counters.Counter private _tokenIdCounter;

    struct Vote {
        address voter;
        uint256 timestamp;
        uint256 weight;
    }

    struct Artwork {
        string name;
        string description;
        string svgContent;
        address artist;
        uint256 voteCount;
        uint256 creationDate;
        Vote[] votes;
    }

    mapping(uint256 => Artwork) public artworks;
    mapping(address => uint256) public lastVoteTime;
    mapping(address => mapping(uint256 => bool)) public hasVoted;

    uint256 public constant VOTE_COOLDOWN = 1 days;
    uint256 public constant MAX_ARTWORKS = 100;
    uint256 public artworkCount = 0;
    uint256 public totalVotes = 0;

    event ArtworkCreated(uint256 indexed artworkId, address indexed artist, string name);
    event Voted(uint256 indexed artworkId, address indexed voter, uint256 weight);
    event ArtworkUpdated(uint256 indexed artworkId, string newSvgContent);

    constructor() ERC721("DynamicSVGNFT", "DSNFT") {}

    function createArtwork(
        string memory name,
        string memory description,
        string memory svgContent
    ) public {
        require(artworkCount < MAX_ARTWORKS, "Maximum number of artworks reached");
        require(bytes(svgContent).length > 0, "SVG content cannot be empty");
        require(bytes(name).length > 0, "Name cannot be empty");

        uint256 tokenId = _tokenIdCounter.current();
        _tokenIdCounter.increment();
        _safeMint(msg.sender, tokenId);

        artworks[tokenId] = Artwork({
            name: name,
            description: description,
            svgContent: svgContent,
            artist: msg.sender,
            voteCount: 0,
            creationDate: block.timestamp,
            votes: new Vote[](0)
        });

        artworkCount++;
        emit ArtworkCreated(tokenId, msg.sender, name);
    }

    function vote(uint256 artworkId, uint256 weight) public {
        require(_exists(artworkId), "Artwork does not exist");
        require(!hasVoted[msg.sender][artworkId], "Already voted for this artwork");
        require(block.timestamp >= lastVoteTime[msg.sender] + VOTE_COOLDOWN, "Vote cooldown active");
        require(weight > 0 && weight <= 10, "Weight must be between 1 and 10");

        Artwork storage artwork = artworks[artworkId];
        artwork.voteCount += weight;
        artwork.votes.push(Vote({
            voter: msg.sender,
            timestamp: block.timestamp,
            weight: weight
        }));

        hasVoted[msg.sender][artworkId] = true;
        lastVoteTime[msg.sender] = block.timestamp;
        totalVotes++;

        emit Voted(artworkId, msg.sender, weight);
    }

    function updateArtwork(uint256 artworkId, string memory newSvgContent) public {
        require(_exists(artworkId), "Artwork does not exist");
        require(ownerOf(artworkId) == msg.sender, "Not the artwork owner");
        require(bytes(newSvgContent).length > 0, "SVG content cannot be empty");

        artworks[artworkId].svgContent = newSvgContent;
        emit ArtworkUpdated(artworkId, newSvgContent);
    }

    function getArtwork(uint256 artworkId) public view returns (
        string memory name,
        string memory description,
        string memory svgContent,
        address artist,
        uint256 voteCount,
        uint256 creationDate,
        uint256 voteCount
    ) {
        require(_exists(artworkId), "Artwork does not exist");
        Artwork memory artwork = artworks[artworkId];
        return (
            artwork.name,
            artwork.description,
            artwork.svgContent,
            artwork.artist,
            artwork.voteCount,
            artwork.creationDate,
            artwork.votes.length
        );
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        require(_exists(tokenId), "ERC721Metadata: URI query for nonexistent token");

        Artwork memory artwork = artworks[tokenId];
        
        string memory json = Base64.encode(
            bytes(
                string(
                    abi.encodePacked(
                        '{"name": "', artwork.name, '",',
                        '"description": "', artwork.description, '",',
                        '"image": "data:image/svg+xml;base64,', Base64.encode(bytes(artwork.svgContent)), '",',
                        '"attributes": [',
                            '{"trait_type": "Artist", "value": "', toAsciiString(artwork.artist), '"},',
                            '{"trait_type": "Vote Count", "value": ', Strings.toString(artwork.voteCount), '},',
                            '{"trait_type": "Creation Date", "value": ', Strings.toString(artwork.creationDate), '}',
                        ']}'
                    )
                )
            )
        );

        return string(abi.encodePacked("data:application/json;base64,", json));
    }

    function toAsciiString(address x) internal pure returns (string memory) {
        bytes memory s = new bytes(40);
        for (uint i = 0; i < 20; i++) {
            bytes1 b = bytes1(uint8(uint(uint160(x)) / (2**(8*(19 - i)))));
            bytes1 hi = bytes1(uint8(b) / 16);
            bytes1 lo = bytes1(uint8(b) - 16 * uint8(hi));
            s[2*i] = char(hi);
            s[2*i+1] = char(lo);            
        }
        return string(s);
    }

    function char(bytes1 b) internal pure returns (bytes1 c) {
        if (uint8(b) < 10) return bytes1(uint8(b) + 0x30);
        else return bytes1(uint8(b) + 0x57);
    }

    function getTopArtworks(uint256 count) public view returns (uint256[] memory) {
        require(count <= artworkCount && count > 0, "Invalid count");

        uint256[] memory topArtworks = new uint256[](count);
        uint256[] memory allArtworks = new uint256[](artworkCount);
        uint256[] memory voteCounts = new uint256[](artworkCount);

        // Populate arrays
        for (uint256 i = 0; i < artworkCount; i++) {
            allArtworks[i] = i;
            voteCounts[i] = artworks[i].voteCount;
        }

        // Simple selection sort (optimize with better algorithm for large counts)
        for (uint256 i = 0; i < count; i++) {
            uint256 maxIndex = i;
            for (uint256 j = i + 1; j < artworkCount; j++) {
                if (voteCounts[j] > voteCounts[maxIndex]) {
                    maxIndex = j;
                }
            }
            if (maxIndex != i) {
                (allArtworks[i], allArtworks[maxIndex]) = (allArtworks[maxIndex], allArtworks[i]);
                (voteCounts[i], voteCounts[maxIndex]) = (voteCounts[maxIndex], voteCounts[i]);
            }
            topArtworks[i] = allArtworks[i];
        }

        return topArtworks;
    }
}
