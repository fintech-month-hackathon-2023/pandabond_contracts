// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./interfaces/IBondDB.sol";

/** PandaBond Data Aggregator
 * Includes:
 * Total Funds Raised in each currency: _fundsRaisedByToken
 * Total Funds Raised in each currency by category: _fundsRaisedByTokenAndCategory
 * Total Funds Raised in each currency by company: _fundsRaisedByCompanyAndToken
 * Total Funds Raised in each currency by company and category: _fundsRaisedByCompanyAndTokenAndCategory
 * Number of Issued Bonds by category: _numberOfIssuedBondsByCategory
 * Number of Issued Bonds by company and category: _numberOfIssuedBondsByCompanyAndCategory
 * Number of times defaulted by company: _numberOfTimesDefaultedByCompany
 * Number of times defaulted by company and category: _numberOfTimesDefaultedByCompanyAndCategory
 */

contract BondDB is IBondDB {
    address immutable _owner;

    mapping(address => bool) _isPeriphery;
    mapping(address => bool) _isFactory;

    mapping(address => uint256) _fundsRaisedByToken;
    mapping(address => mapping(uint256 => uint256)) _fundsRaisedByTokenAndCategory;
    mapping(address => mapping(address => uint256)) _fundsRaisedByCompanyAndToken;
    mapping(address => mapping(address => mapping(uint256 => uint256))) _fundsRaisedByCompanyAndTokenAndCategory;
    mapping(uint256 => uint256) _numberOfIssuedBondsByCategory;
    mapping(address => mapping(uint256 => uint256)) _numberOfIssuedBondsByCompanyAndCategory;
    mapping(address => uint256) _numberOfTimesDefaultedByCompany;
    mapping(address => mapping(uint256 => uint256)) _numberOfTimesDefaultedByCompanyAndCategory;
    mapping(address => uint256) _tvlByToken;

    constructor() {
        _owner = msg.sender;
    }

    function registerPeriphery(address[] memory peripheries) external {
        require(_owner == msg.sender, "NTO");
        for (uint i = 0; i < peripheries.length; i++) {
            _isPeriphery[peripheries[i]] = true;
        }
    }

    function registerFactory(address factory) external {
        require(_isPeriphery[msg.sender], "NAP");
        _isFactory[factory] = true;
    }

    function incrementFundsRaisedByToken(
        uint256 amount,
        address token
    ) external {
        require(_isFactory[msg.sender] || _isPeriphery[msg.sender], "NAPOF");
        _fundsRaisedByToken[token] += amount;
    }

    function incrementFundsRaisedByTokenAndCategory(
        uint256 amount,
        address token,
        uint256 category
    ) external {
        require(_isFactory[msg.sender] || _isPeriphery[msg.sender], "NAPOF");
        _fundsRaisedByTokenAndCategory[token][category] += amount;
    }

    function incrementFundsRaisedByCompanyAndToken(
        uint256 amount,
        address company,
        address token
    ) external {
        require(_isFactory[msg.sender] || _isPeriphery[msg.sender], "NAPOF");
        _fundsRaisedByCompanyAndToken[company][token] += amount;
    }

    function incrementFundsRaisedByCompanyAndTokenAndCategory(
        uint256 amount,
        address company,
        address token,
        uint256 category
    ) external {
        require(_isFactory[msg.sender] || _isPeriphery[msg.sender], "NAPOF");
        _fundsRaisedByCompanyAndTokenAndCategory[company][token][
            category
        ] += amount;
    }

    function incrementNumberOfIssuedBondsByCategory(uint256 category) external {
        require(_isFactory[msg.sender] || _isPeriphery[msg.sender], "NAPOF");
        _numberOfIssuedBondsByCategory[category] += 1;
    }

    function incrementNumberOfIssuedBondsByCompanyAndCategory(
        address company,
        uint256 category
    ) external {
        require(_isFactory[msg.sender] || _isPeriphery[msg.sender], "NAPOF");
        _numberOfIssuedBondsByCompanyAndCategory[company][category] += 1;
    }

    function incrementNumberOfTimesDefaultedByCompany(
        address company
    ) external {
        require(_isFactory[msg.sender] || _isPeriphery[msg.sender], "NAPOF");
        _numberOfTimesDefaultedByCompany[company] += 1;
    }

    function incrementNumberOfTimesDefaultedByCompanyAndCategory(
        address company,
        uint256 category
    ) external {
        require(_isFactory[msg.sender] || _isPeriphery[msg.sender], "NAPOF");
        _numberOfTimesDefaultedByCompanyAndCategory[company][category] += 1;
    }

    function incrementTVLByToken(uint256 amount, address token) external {
        require(_isFactory[msg.sender] || _isPeriphery[msg.sender], "NAPOF");
        _tvlByToken[token] += amount;
    }

    function decrementTVLByToken(uint256 amount, address token) external {
        require(_isFactory[msg.sender] || _isPeriphery[msg.sender], "NAPOF");
        require(_tvlByToken[token] >= amount, "AETVL");
        _tvlByToken[token] -= amount;
    }

    function owner() external view returns (address) {
        return _owner;
    }

    function isPeriphery(address account) external view returns (bool) {
        return _isPeriphery[account];
    }

    function isFactory(address account) external view returns (bool) {
        return _isFactory[account];
    }

    function fundsRaisedByToken(address token) external view returns (uint256) {
        return _fundsRaisedByToken[token];
    }

    function fundsRaisedByTokenAndCategory(
        address token,
        uint256 category
    ) external view returns (uint256) {
        return _fundsRaisedByTokenAndCategory[token][category];
    }

    function fundsRaisedByCompanyAndToken(
        address company,
        address token
    ) external view returns (uint256) {
        return _fundsRaisedByCompanyAndToken[company][token];
    }

    function fundsRaisedByCompanyAndTokenAndCategory(
        address company,
        address token,
        uint256 category
    ) external view returns (uint256) {
        return
            _fundsRaisedByCompanyAndTokenAndCategory[company][token][category];
    }

    function numberOfIssuedBondsByCategory(
        uint256 category
    ) external view returns (uint256) {
        return _numberOfIssuedBondsByCategory[category];
    }

    function numberOfIssuedBondsByCompanyAndCategory(
        address company,
        uint256 category
    ) external view returns (uint256) {
        return _numberOfIssuedBondsByCompanyAndCategory[company][category];
    }

    function numberOfTimesDefaultedByCompany(
        address company
    ) external view returns (uint256) {
        return _numberOfTimesDefaultedByCompany[company];
    }

    function numberOfTimesDefaultedByCompanyAndCategory(
        address company,
        uint256 category
    ) external view returns (uint256) {
        return _numberOfTimesDefaultedByCompanyAndCategory[company][category];
    }

    function tvlByToken(address token) external view returns (uint256) {
        return _tvlByToken[token];
    }
}
