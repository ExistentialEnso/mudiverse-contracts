/**
 *                     .___.__                                       
 *   _____   __ __   __| _/|__|___  __  ____ _______  ______  ____   
 *  /     \ |  |  \ / __ | |  |\  \/ /_/ __ \\_  __ \/  ___/_/ __ \  
 * |  Y Y  \|  |  // /_/ | |  | \   / \  ___/ |  | \/\___ \ \  ___/  
 * |__|_|  /|____/ \____ | |__|  \_/   \___  >|__|  /______> \___ > 
 *
 *                  contract by: ens0.eth 
 *
 *   On-chain MUD-like game. Contract handles player movement and 
 *   representing locations in NFT form, which render as on-chain SVGs.   
 *                                                             
 */

pragma solidity ^0.8.13;

import "@openzeppelin/contracts/access/Ownable.sol";
import "erc721a/contracts/ERC721A.sol";

error NotYourLocation();
error NoExitThatWay();
error InvalidTokenId();
error NotRespawnPoint();
error MaxQuantityExceeded();
error InsufficientEther();
error ExceedsMaximumSupply();
error NameTooLong();
error DescriptionTooLong();
error TokenMetadataFrozen();

contract Mudiverse is ERC721A, Ownable {
    /**
     * On-chain data for each location.
     */
    struct Location {
        string name;
        string description;

        bool respawnPoint;

        uint16 north;
        uint16 south;
        uint16 east;
        uint16 west;
    }

    // Minting a new location costs 2 MATIC
    uint256 public constant MINT_PRICE = 2 ether;

    // Scarcity only defined by our desire to limit to uint16 for gas optimization purposes
    uint16 public constant MAX_LOCATIONS = 65535;

    mapping(address => uint16) public playerPositions;
    mapping(uint16 => Location) public locations;
    mapping(uint16 => bool) public frozen;

    // Events that log the player's movements around the map
    event Movement(address indexed player, uint16 indexed originId, uint16 indexed destinationId);
    event Respawn(address indexed player, uint16 indexed despawnId, uint16 indexed respawnId);

    constructor() ERC721A("mudiverse", "MUD") {
        _mintERC2309(msg.sender, 100);
    }

    /**
     * Start at 1 so we can use 0 to mean a direction has no exit.
     */
    function _startTokenId() override internal view virtual returns (uint256) {
        return 1;
    }

    /**
     * Create up to 1000 new locations represented in NFT form.
     */
    function mint(uint16 qty) external payable {
        if(qty > 1000) revert MaxQuantityExceeded();

        unchecked {
            if(msg.value < qty * MINT_PRICE) revert InsufficientEther();
            if(totalSupply() + qty > MAX_LOCATIONS) revert ExceedsMaximumSupply();
        }

        _mint(msg.sender, qty);
    }

    /**
     * Freezes a token, preventing its metadata from being altered unless unfrozen. Allows mitigation 
     * of posting abusive content through token data.
     */
    function setFrozen(uint16 tokenId, bool isFrozen) external onlyOwner {
        frozen[tokenId] = isFrozen;
    }

    /**
     * Changes the metadata on the token, allowing token owners to customize the map.
     */
    function setMetadata(uint16 tokenId, Location calldata data) external {
        // Prevent the strings being too long to fit the SVG
        if(bytes(data.name).length > 55) revert NameTooLong();
        if(bytes(data.description).length > 170) revert DescriptionTooLong();

        // Ensure this token actually exists
        if(!_exists(tokenId)) revert InvalidTokenId();

        // See if they are either the contract owner or the token owner
        // (Contract owner can also update metadata as a safeguard against abuse)
        if(ownerOf(tokenId) != msg.sender && owner() != msg.sender) revert NotYourLocation();

        // Prevent a token being used in an abusive way from being edited
        if(frozen[tokenId]) revert TokenMetadataFrozen();

        // Update the on-chain data
        locations[tokenId] = data;
    }

    /**
     * Moves the calling player's position to any location marked as a respawn point, allowing one-time circumventing of 
     * their chosen respawn location. Can be used essentially as a "teleport" function, since the only penalty is paying gas.
     */
    function respawn(uint16 tokenId) external {
        if(!_exists(tokenId)) revert InvalidTokenId();
        if(!locations[tokenId].respawnPoint) revert NotRespawnPoint();

        uint16 currentId = positionId();
        playerPositions[msg.sender] = tokenId;

        emit Respawn(msg.sender, currentId, tokenId);
}

    /**
     * Moves the calling player's position north based on their current location's exits.
     */
    function north() external {
        uint16 currentId = positionId();

        if(locations[currentId].north == 0) revert NoExitThatWay();
        if(!_exists(locations[currentId].north)) revert InvalidTokenId();

        playerPositions[msg.sender] = locations[currentId].north;

        emit Movement(msg.sender, currentId, locations[currentId].north);
    }

    /**
     * Moves the calling player's position south based on their current location's exits.
     */
    function south() external {
        uint16 currentId = positionId();

        if(locations[currentId].south == 0) revert NoExitThatWay();
        if(!_exists(locations[currentId].south)) revert InvalidTokenId();

        playerPositions[msg.sender] = locations[currentId].south;

        emit Movement(msg.sender, currentId, locations[currentId].south);
    }

    /**
     * Moves the calling player's position east based on their current location's exits.
     */
    function east() external {
        uint16 currentId = positionId();

        if(locations[currentId].east == 0) revert NoExitThatWay();
        if(!_exists(locations[currentId].east)) revert InvalidTokenId();

        playerPositions[msg.sender] = locations[currentId].east;

        emit Movement(msg.sender, currentId, locations[currentId].east);
    }

    /**
     * Moves the calling player's position west based on their current location's exits.
     */
    function west() external {
        uint16 currentId = positionId();

        if(locations[currentId].west == 0) revert NoExitThatWay();
        if(!_exists(locations[currentId].west)) revert InvalidTokenId();

        playerPositions[msg.sender] = locations[currentId].west;

        emit Movement(msg.sender, currentId, locations[currentId].west);
    }

    /**
     * Calls tokenURI() on the caller's location.
     */
    function look() external view returns (string memory) {
        uint16 currentId = positionId();

        return tokenURI(currentId);
    }

    /**
     * Get the tokenId of the caller's location.
     */
    function positionId() public view returns (uint16) {
        // Fall back to tokenId of 1 for players who haven't played *at all* yet.
        // Value will default to zero, but 0 is reserved for a "no exit" uint16 value.
        // TokenId incrementing counter starts at 1.
        return playerPositions[msg.sender] == 0 ? 1 : playerPositions[msg.sender];
    }

    /**
     * Handles splitting the description into multiple lines elegantly for SVG rendering.
     */
    function splitDescription(bytes calldata descBytes) public pure returns (string[3] memory) {
        string[3] memory split;

        if(descBytes.length < 51) {
            split[0] = string(descBytes); // Short enough to go on one line
        } else {
            uint8 firstSplit = 50;

            // look for place to make first linebreak
            while(descBytes[firstSplit] != ' ' && firstSplit + 1 < descBytes.length) {
                ++firstSplit;
            }

            if(descBytes[firstSplit] == ' ') {
                split[0] = string(descBytes[:firstSplit]);

                if(descBytes.length < firstSplit + 51) {
                    split[1] = string(descBytes[firstSplit:]); // Short enough to go on two lines
                } else {
                    uint8 secondSplit = firstSplit + 50;

                    while(descBytes[secondSplit] != ' ' && secondSplit + 1 < descBytes.length) {
                        ++secondSplit;
                    }

                    if(descBytes[secondSplit] == ' ') {
                        split[1] = string(descBytes[firstSplit:secondSplit]);
                        split[2] = string(descBytes[secondSplit:]);
                    } else {
                        split[1] = string(descBytes[firstSplit:]); // Second line break failed, put remainder on second line
                    }
                }
            } else {
                split[0] = string(descBytes); // First line break failed, just put it all on one line
            }
        }

        return split;
    }

    /**
     * Override URI-fetching function to render the SVG on-chain.
     */
    function tokenURI(uint256 tokenId) override public view returns (string memory) {
        string memory noExit = "No Exit";
        uint16 tokenId_u16 = uint16(tokenId);
        Location memory data = locations[tokenId_u16];

        string[3] memory descPieces = this.splitDescription(bytes(data.description));

        string[17] memory parts;
        string[5] memory traits;

        traits[0] = string(abi.encodePacked('{"trait_type":"North","value":"', (data.north > 0 ? _toString(data.north) : noExit), '"},'));
        traits[1] = string(abi.encodePacked('{"trait_type":"South","value":"', (data.south > 0 ? _toString(data.south) : noExit), '"},'));
        traits[2] = string(abi.encodePacked('{"trait_type":"East","value":"', (data.east > 0 ? _toString(data.east) : noExit), '"},'));
        traits[3] = string(abi.encodePacked('{"trait_type":"West","value":"', (data.west > 0 ? _toString(data.west) : noExit), '"}'));

        // Build out our SVG
        parts[0] = '<svg xmlns="http://www.w3.org/2000/svg" preserveAspectRatio="xMinYMin meet" viewBox="0 0 350 350"><style>.base { font-family: monospace; font-size: 10px; } .title { font-weight: bold; font-size: 12px; } .destination { font-weight: bold }</style><rect width="100%" height="100%" fill="#000" /><text x="10" y="20" class="base title" fill="#FFF">';
        parts[1] = bytes(data.name).length == 0 ? "No Name": data.name;
        parts[2] = '</text><text x="10" y="40" class="base" fill="#FFF">';
        parts[3] = bytes(descPieces[0]).length == 0 ? "No Description" : descPieces[0];
        parts[4] = '</text><text x="10" y="60" class="base" fill="#FFF">';
        parts[5] = bytes(descPieces[1]).length == 0 ? " " : descPieces[1];
        parts[6] = '</text><text x="10" y="80" class="base" fill="#FFF">';
        parts[7] = bytes(descPieces[2]).length == 0 ? " " : descPieces[2];
        parts[8] = '</text><text x="10" y="100" class="base" fill="#FFF">North: <tspan class="destination">';
        parts[9] = _exists(data.north) ? locations[data.north].name : noExit;
        parts[10] = '</tspan></text><text x="10" y="120" class="base" fill="#FFF">South: <tspan class="destination">';
        parts[11] = _exists(data.south) ? locations[data.south].name : noExit;
        parts[12] = '</tspan></text><text x="10" y="140" class="base" fill="#FFF">East: <tspan class="destination">';
        parts[13] = _exists(data.east) ? locations[data.east].name : noExit;
        parts[14] = '</tspan></text><text x="10" y="160" class="base" fill="#FFF">West: <tspan class="destination">';
        parts[15] = _exists(data.west) ? locations[data.west].name : noExit;
        parts[16] = '</tspan></text></svg>';

        string memory output = string(abi.encodePacked(parts[0], parts[1], parts[2], parts[3], parts[4], parts[5], parts[6], parts[7], parts[8]));
        output = Base64.encode(bytes(string(abi.encodePacked(output, parts[9], parts[10], parts[11], parts[12], parts[13], parts[14], parts[15], parts[16]))));
        
        string memory json = Base64.encode(bytes(string(abi.encodePacked('{"name": "', locations[tokenId_u16].name, '", "description": "', locations[tokenId_u16].description ,'", "attributes": [', traits[0], traits[1], traits[2], traits[3], traits[4], '], "image": "data:image/svg+xml;base64,', bytes(output), '"}'))));
        output = string(abi.encodePacked('data:application/json;base64,', json));

        return output;
    }

    function withdraw() external onlyOwner {
        payable(msg.sender).transfer(address(this).balance);
    }
}

/// [MIT License]
/// @title Base64
/// @notice Provides a function for encoding some bytes in base64
/// @author Brecht Devos <brecht@loopring.org>
library Base64 {
    bytes internal constant TABLE = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

    /// @notice Encodes some bytes to the base64 representation
    function encode(bytes memory data) internal pure returns (string memory) {
        uint256 len = data.length;
        if (len == 0) return "";

        // multiply by 4/3 rounded up
        uint256 encodedLen = 4 * ((len + 2) / 3);

        // Add some extra buffer at the end
        bytes memory result = new bytes(encodedLen + 32);

        bytes memory table = TABLE;

        assembly {
            let tablePtr := add(table, 1)
            let resultPtr := add(result, 32)

            for {
                let i := 0
            } lt(i, len) {

            } {
                i := add(i, 3)
                let input := and(mload(add(data, i)), 0xffffff)

                let out := mload(add(tablePtr, and(shr(18, input), 0x3F)))
                out := shl(8, out)
                out := add(out, and(mload(add(tablePtr, and(shr(12, input), 0x3F))), 0xFF))
                out := shl(8, out)
                out := add(out, and(mload(add(tablePtr, and(shr(6, input), 0x3F))), 0xFF))
                out := shl(8, out)
                out := add(out, and(mload(add(tablePtr, and(input, 0x3F))), 0xFF))
                out := shl(224, out)

                mstore(resultPtr, out)

                resultPtr := add(resultPtr, 4)
            }

            switch mod(len, 3)
            case 1 {
                mstore(sub(resultPtr, 2), shl(240, 0x3d3d))
            }
            case 2 {
                mstore(sub(resultPtr, 1), shl(248, 0x3d))
            }

            mstore(result, encodedLen)
        }

        return string(result);
    }
}