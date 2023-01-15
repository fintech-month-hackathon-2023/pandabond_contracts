// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./DualCurrencyBondFactory.sol";
import "./SoulBoundToken.sol";

contract DualCurrencyBondPeriphery {
    address immutable _owner;
    SoulBoundToken immutable _sbt;

    address[] _entities;

    mapping(address => address) _priceFeeds;
    mapping(address => bool) _isRegistered;

    mapping(address => address[]) _dualCurrencyBondFactories;

    mapping(address => mapping(address => mapping(address => bool))) _dualCurrencyBondFactoryIsInitialized;

    event DualCurrencyBondFactoryInitialized(
        address indexed owner,
        address tokenA,
        address tokenB
    );

    modifier onlyOwner() {
        require(msg.sender == _owner, "Caller is not the owner");
        _;
    }

    modifier onlyIsRegistered() {
        require(_isRegistered[msg.sender] == true, "Caller is not registered");
        _;
    }

    modifier hasActiveSBT() {
        require(
            _sbt.hasActiveSBT(msg.sender),
            "Caller requires an active SoulBound Token"
        );
        _;
    }

    constructor(address sbt) {
        _owner = msg.sender;
        _sbt = SoulBoundToken(sbt);
        _priceFeeds[
            0x21C8a148933E6CA502B47D729a485579c22E8A69
        ] = 0x0d79df66BE487753B02D015Fb622DED7f0E9798d; // DAI/USD
        _priceFeeds[
            0x07865c6E87B9F70255377e024ace6630C1Eaa37F
        ] = 0xAb5c49580294Aff77670F839ea425f5b78ab3Ae7; // USDC/USD
        _priceFeeds[
            0xB4FBF271143F4FBf7B91A5ded31805e42b2208d6
        ] = 0xD4a33860578De61DBAbDc8BFdb98FD742fA7028e; // WETH/USD
        _priceFeeds[
            0x326C977E6efc84E512bB9C30f76E30c160eD06FB
        ] = 0x48731cF7e84dc94C5f84577882c14Be11a5B7456; // LINK/USD
        _priceFeeds[
            0x9C556b18d2370d4c44F3b3153d340D9Abfd8d995
        ] = 0xA39434A63A52E749F02807ae27335515BA4b07F7; // WBTC/USDs
    }

    function register() external hasActiveSBT {
        require(
            _sbt.accessTier(msg.sender) >= 3,
            "Caller does not have valid access tier"
        );
        require(!_isRegistered[msg.sender], "Caller is already registered");
        _isRegistered[msg.sender] = true;
        _entities.push(msg.sender);
    }

    function createDualCurrencyBondFactory(
        string memory uri,
        address tokenA,
        address tokenB
    ) external onlyIsRegistered hasActiveSBT returns (address factory) {
        require(
            _sbt.accessTier(msg.sender) >= 3,
            "Caller does not have valid access tier"
        );
        require(
            _priceFeeds[tokenA] != address(0) &&
                _priceFeeds[tokenB] != address(0),
            "Price feed(s) not available"
        );
        require(
            !_dualCurrencyBondFactoryIsInitialized[msg.sender][tokenA][tokenB],
            "Factory is already initialized"
        );

        factory = address(
            new DualCurrencyBondFactory(
                uri,
                tokenA,
                tokenB,
                _priceFeeds[tokenA],
                _priceFeeds[tokenB],
                msg.sender
            )
        );
        _dualCurrencyBondFactories[msg.sender].push(factory);
        _dualCurrencyBondFactoryIsInitialized[msg.sender][tokenA][
            tokenB
        ] = true;

        emit DualCurrencyBondFactoryInitialized(msg.sender, tokenA, tokenB);
    }

    function registerPriceFeed(address token, address feed) public onlyOwner {
        _priceFeeds[token] = feed;
    }

    function deregisterPriceFeed(address token) public onlyOwner {
        _priceFeeds[token] = address(0);
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

    function dualCurrencyBondFactories(
        address caller
    ) public view returns (address[] memory) {
        return _dualCurrencyBondFactories[caller];
    }

    function dualCurrencyBondFactoryIsInitialized(
        address caller,
        address tokenA,
        address tokenB
    ) public view returns (bool) {
        return _dualCurrencyBondFactoryIsInitialized[caller][tokenA][tokenB];
    }
}
