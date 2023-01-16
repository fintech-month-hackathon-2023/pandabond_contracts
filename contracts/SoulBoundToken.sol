// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/ISoulBoundToken.sol";

contract SoulBoundToken is ERC721, Ownable, ISoulBoundToken {
    using Counters for Counters.Counter;

    Counters.Counter private _tokenIdCounter;

    mapping(uint256 => uint8) _accessTier;
    mapping(uint256 => bool) _isActive;
    mapping(uint256 => bytes32) _hashedIdentity;
    mapping(address => uint256) _ownerToTokenId;

    modifier validLevel(uint8 tier) {
        require(tier >= 1 && tier <= 3, "IT");
        _;
    }

    constructor() ERC721("SoulBoundToken", "SBT") {
        _tokenIdCounter.increment();
    }

    function safeMint(
        address to,
        uint8 tier,
        bytes32 hashed
    ) public onlyOwner validLevel(tier) {
        require(_ownerToTokenId[to] == 0, "STAE");
        uint256 tokenId = _tokenIdCounter.current();
        _tokenIdCounter.increment();
        _isActive[tokenId] = true;
        _accessTier[tokenId] = tier;
        _hashedIdentity[tokenId] = hashed;
        _ownerToTokenId[to] = tokenId;
        _safeMint(to, tokenId);
    }

    function burn(uint256 tokenId) external {
        require(ownerOf(tokenId) == msg.sender, "NO");
        _burn(tokenId);
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256,
        uint256
    ) internal pure override {
        require(from == address(0) || to == address(0), "SBTCT");
    }

    function _burn(uint256 tokenId) internal override(ERC721) {
        super._burn(tokenId);
    }

    function modifyLevel(
        uint256 id,
        uint8 tier
    ) public onlyOwner validLevel(tier) {
        _accessTier[id] = tier;
    }

    function deactivate(uint256 id) public onlyOwner {
        _isActive[id] = false;
    }

    function reactivate(uint256 id) public onlyOwner {
        _isActive[id] = true;
    }

    //getters
    function accessTier(uint256 id) public view returns (uint8) {
        return _accessTier[id];
    }

    function accessTier(address owner) public view returns (uint8) {
        return accessTier(ownerToTokenId(owner));
    }

    function isActive(uint256 id) public view returns (bool) {
        return _isActive[id];
    }

    function hashedIdentity(uint256 id) public view returns (bytes32) {
        return _hashedIdentity[id];
    }

    function hasActiveSBT(address owner) public view returns (bool) {
        return _isActive[ownerToTokenId(owner)];
    }

    function ownerToTokenId(address owner) public view returns (uint256) {
        return _ownerToTokenId[owner];
    }
}
