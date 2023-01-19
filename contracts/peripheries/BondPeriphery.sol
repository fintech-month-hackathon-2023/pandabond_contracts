// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../factories/BondFactory.sol";
import "../interfaces/ISoulBoundToken.sol";
import "../interfaces/IBondDB.sol";
import "../interfaces/IBond.sol";

contract BondPeriphery {
    address immutable _owner;
    ISoulBoundToken immutable _sbt;
    IBondDB immutable _bondDB;

    IBond immutable _bondToken;

    address[] _entities;

    mapping(address => bool) _isRegistered;

    mapping(address => bool) _isAllowedCurrency;

    mapping(address => address[]) _bondFactories;

    mapping(address => mapping(address => bool)) _bondFactoryIsInitialized;

    event FactoryInitialized(address indexed owner, address token);

    modifier onlyOwner() {
        require(msg.sender == _owner, "NTO");
        _;
    }

    modifier onlyIsRegistered() {
        require(_isRegistered[msg.sender], "NR");
        _;
    }

    modifier onlyAllowedCurrencies(address currency) {
        require(_isAllowedCurrency[currency], "IC");
        _;
    }

    modifier hasActiveSBT() {
        require(_sbt.hasActiveSBT(msg.sender), "NAST");
        _;
    }

    constructor(address sbt, address db, address bt) {
        _owner = msg.sender;
        _sbt = ISoulBoundToken(sbt);
        _bondDB = IBondDB(db);
        _bondToken = IBond(bt);
        _isAllowedCurrency[0x21C8a148933E6CA502B47D729a485579c22E8A69] = true; // DAI
        _isAllowedCurrency[0x07865c6E87B9F70255377e024ace6630C1Eaa37F] = true; // USDC
        _isAllowedCurrency[0xB4FBF271143F4FBf7B91A5ded31805e42b2208d6] = true; // WETH
        _isAllowedCurrency[0x326C977E6efc84E512bB9C30f76E30c160eD06FB] = true; // LINK
        _isAllowedCurrency[0x9C556b18d2370d4c44F3b3153d340D9Abfd8d995] = true; // WBTC
    }

    function register() external virtual hasActiveSBT {
        require(!_isRegistered[msg.sender], "AR");
        require(_sbt.accessTier(msg.sender) >= 2, "NVAT");
        _isRegistered[msg.sender] = true;
        _entities.push(msg.sender);
    }

    function createBondFactory(
        address token
    )
        external
        virtual
        onlyIsRegistered
        hasActiveSBT
        onlyAllowedCurrencies(token)
        returns (address factory)
    {
        require(_sbt.accessTier(msg.sender) >= 2, "NVAT");
        require(!_bondFactoryIsInitialized[msg.sender][token], "AI");
        factory = address(
            new BondFactory(
                token,
                address(_bondToken),
                address(_bondDB),
                msg.sender
            )
        );
        _bondFactories[msg.sender].push(factory);
        _bondFactoryIsInitialized[msg.sender][token] = true;
        _bondDB.registerFactory(factory);

        emit FactoryInitialized(msg.sender, token);
    }

    //getters
    function owner() public view returns (address) {
        return _owner;
    }

    function entities() public view returns (address[] memory) {
        return _entities;
    }

    function isRegistered(address caller) public view returns (bool) {
        return _isRegistered[caller];
    }

    function bondFactories(
        address caller
    ) public view returns (address[] memory) {
        return _bondFactories[caller];
    }

    function bondFactoryIsInitialized(
        address caller,
        address token
    ) public view returns (bool) {
        return _bondFactoryIsInitialized[caller][token];
    }

    function bondDB() public view returns (address) {
        return address(_bondDB);
    }
}
