// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./interfaces/ISoulBoundToken.sol";

contract CompanyDB {
    struct CompanyMetadata {
        string name;
        bytes32 hashedIdentity;
        uint8 tier;
    }

    address[] _registeredCompanies;
    mapping(address => bool) _isRegisteredCompany;
    mapping(address => CompanyMetadata) _companyMetadata;

    address immutable _owner;
    ISoulBoundToken immutable _soulBoundToken;

    modifier onlyOwner() {
        require(_owner == msg.sender, "NTO");
        _;
    }

    modifier validTier(uint8 tier) {
        require(tier >= 1 && tier <= 3, "IT");
        _;
    }

    constructor(address sbt) {
        _owner = msg.sender;
        _soulBoundToken = ISoulBoundToken(sbt);
    }

    function registerCompany(
        address account,
        string memory name,
        bytes32 hashedIdentity,
        uint8 tier
    ) external onlyOwner validTier(tier) returns (uint256 sbtId) {
        require(!_isRegisteredCompany[account], "CIAR");
        _registeredCompanies.push(account);
        _isRegisteredCompany[account] = true;
        _companyMetadata[account] = CompanyMetadata(name, hashedIdentity, tier);
        sbtId = _soulBoundToken.safeMint(account, tier, hashedIdentity);
    }

    function reissueSBT(
        address account,
        bytes32 hashedIdentity,
        uint8 tier
    ) external onlyOwner returns (uint256 sbtId) {
        require(_isRegisteredCompany[account], "CINR");
        sbtId = _soulBoundToken.safeMint(account, tier, hashedIdentity);
    }

    function deactivateSBT(address account) public onlyOwner {
        require(_soulBoundToken.hasActiveSBT(account), "NASBT");
        _soulBoundToken.deactivate(_soulBoundToken.ownerToTokenId(account));
    }

    function activateSBT(address account) public onlyOwner {
        require(!_soulBoundToken.hasActiveSBT(account), "IASBT");
        require(_soulBoundToken.ownerToTokenId(account) != 0, "NSBT");
        _soulBoundToken.activate(_soulBoundToken.ownerToTokenId(account));
    }

    function modifyTier(address account, uint8 tier) external onlyOwner {
        require(_soulBoundToken.hasActiveSBT(account), "NASBT");
        require(tier != _companyMetadata[account].tier, "ATCST");
        _companyMetadata[account].tier = tier;
        _soulBoundToken.modifyTier(
            _soulBoundToken.ownerToTokenId(account),
            tier
        );
    }

    function isRegisteredCompany(address account) public view returns (bool) {
        return _isRegisteredCompany[account];
    }

    function registeredCompanies() public view returns (address[] memory) {
        return _registeredCompanies;
    }

    function companyMetadata(
        address account
    ) public view returns (string memory, bytes32, uint8) {
        return (
            _companyMetadata[account].name,
            _companyMetadata[account].hashedIdentity,
            _companyMetadata[account].tier
        );
    }

    function owner() public view returns (address) {
        return _owner;
    }

    function soulBoundToken() public view returns (address) {
        return address(_soulBoundToken);
    }
}
