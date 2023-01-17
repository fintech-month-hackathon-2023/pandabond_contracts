// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/ISoulBoundToken.sol";
import "./CompanyDB.sol";

contract SoulBoundToken is ERC721, Ownable, ISoulBoundToken {
    using Counters for Counters.Counter;

    Counters.Counter private _tokenIdCounter;

    CompanyDB _dbAdmin;

    mapping(uint256 => uint8) _accessTier;
    mapping(uint256 => bool) _isActive;
    mapping(uint256 => bytes32) _hashedIdentity;
    mapping(address => uint256) _ownerToTokenId;

    modifier onlyDbAdmin() {
        require(msg.sender == address(_dbAdmin), "NTDBA");
        _;
    }

    constructor() ERC721("SoulBoundToken", "SBT") {
        _tokenIdCounter.increment();
    }

    function registerDbAdmin(address addr) public onlyOwner {
        _dbAdmin = CompanyDB(addr);
    }

    function safeMint(
        address to,
        uint8 tier,
        bytes32 hashed
    ) public onlyDbAdmin returns (uint256 tokenId) {
        tokenId = _tokenIdCounter.current();
        _tokenIdCounter.increment();
        _isActive[tokenId] = true;
        _accessTier[tokenId] = tier;
        _hashedIdentity[tokenId] = hashed;
        _ownerToTokenId[to] = tokenId;
        _safeMint(to, tokenId);
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256,
        uint256
    ) internal pure override {
        require(from == address(0) || to == address(0), "SBTCT");
    }

    function modifyTier(uint256 id, uint8 tier) public onlyDbAdmin {
        _accessTier[id] = tier;
    }

    function deactivate(uint256 id) public onlyDbAdmin {
        _isActive[id] = false;
    }

    function activate(uint256 id) public onlyDbAdmin {
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

    function hasSBT(address owner) public view returns (bool) {
        return ownerToTokenId(owner) != 0;
    }

    function ownerToTokenId(address owner) public view returns (uint256) {
        return _ownerToTokenId[owner];
    }

    function dbAdmin() public view returns (address) {
        return address(_dbAdmin);
    }
}
