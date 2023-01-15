// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./BondFactory.sol";
import "./CallableBondFactory.sol";
import "./InstallmentBondFactory.sol";
import "./DualCurrencyBondFactory.sol";
import "./SoulBoundToken.sol";

contract Mainframe {
    address immutable _owner;
    SoulBoundToken immutable _sbt;

    address[] _entities;

    mapping(address => address) _priceFeeds;
    mapping(address => bool) _isRegistered;

    mapping(address => address[]) _bondFactories;
    mapping(address => address[]) _callableBondFactories;
    mapping(address => address[]) _installmentBondFactories;
    mapping(address => address[]) _dualCurrencyBondFactories;

    mapping(address => mapping(address => bool)) _bondFactoryIsInitialized;
    mapping(address => mapping(address => bool)) _callableBondFactoryIsInitialized;
    mapping(address => mapping(address => bool)) _installmentBondFactoryIsInitialized;
    mapping(address => mapping(address => mapping(address => bool))) _dualCurrencyBondFactoryIsInitialized;

    event BondFactoryInitialized(address indexed owner, address token);
    event CallableBondFactoryInitialized(address indexed owner, address token);

    event InstallmentBondFactoryInitialized(
        address indexed owner,
        address token
    );

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

    modifier hasValidAccessTier(uint8 tier) {
        require(
            _sbt.accessTier(msg.sender) >= tier,
            "Caller does not have valid access tier"
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
        require(!_isRegistered[msg.sender], "Caller is already registered");
        _isRegistered[msg.sender] = true;
        _entities.push(msg.sender);
    }

    function createBondFactory(
        string memory uri,
        address token
    )
        external
        onlyIsRegistered
        hasActiveSBT
        hasValidAccessTier(2)
        returns (address factory)
    {
        require(
            !_bondFactoryIsInitialized[msg.sender][token],
            "Factory is already initialized"
        );
        factory = address(new BondFactory(uri, token, msg.sender));
        _bondFactories[msg.sender].push(factory);
        _bondFactoryIsInitialized[msg.sender][token] = true;

        emit BondFactoryInitialized(msg.sender, token);
    }

    function createCallableBondFactory(
        string memory uri,
        address token
    )
        external
        onlyIsRegistered
        hasActiveSBT
        hasValidAccessTier(1)
        returns (address factory)
    {
        require(
            !_callableBondFactoryIsInitialized[msg.sender][token],
            "Factory is already initialized"
        );
        factory = address(new CallableBondFactory(uri, token, msg.sender));
        _callableBondFactories[msg.sender].push(factory);
        _callableBondFactoryIsInitialized[msg.sender][token] = true;

        emit CallableBondFactoryInitialized(msg.sender, token);
    }

    function createInstallmentBondFactory(
        string memory uri,
        address token
    )
        external
        onlyIsRegistered
        hasActiveSBT
        hasValidAccessTier(3)
        returns (address factory)
    {
        require(
            !_installmentBondFactoryIsInitialized[msg.sender][token],
            "Factory is already initialized"
        );
        factory = address(new InstallmentBondFactory(uri, token, msg.sender));
        _installmentBondFactories[msg.sender].push(factory);
        _installmentBondFactoryIsInitialized[msg.sender][token] = true;

        emit InstallmentBondFactoryInitialized(msg.sender, token);
    }

    function createDualCurrencyBondFactory(
        string memory uri,
        address tokenA,
        address tokenB
    )
        external
        onlyIsRegistered
        hasActiveSBT
        hasValidAccessTier(2)
        returns (address factory)
    {
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

    function bondFactories(
        address caller
    ) public view returns (address[] memory) {
        return _bondFactories[caller];
    }

    function callableBondFactories(
        address caller
    ) public view returns (address[] memory) {
        return _callableBondFactories[caller];
    }

    function installmentBondFactories(
        address caller
    ) public view returns (address[] memory) {
        return _installmentBondFactories[caller];
    }

    function dualCurrencyBondFactories(
        address caller
    ) public view returns (address[] memory) {
        return _dualCurrencyBondFactories[caller];
    }

    function bondFactoryIsInitialized(
        address caller,
        address token
    ) public view returns (bool) {
        return _bondFactoryIsInitialized[caller][token];
    }

    function callableBondFactoryIsInitialized(
        address caller,
        address token
    ) public view returns (bool) {
        return _callableBondFactoryIsInitialized[caller][token];
    }

    function installmentBondFactoryIsInitialized(
        address caller,
        address token
    ) public view returns (bool) {
        return _installmentBondFactoryIsInitialized[caller][token];
    }

    function dualCurrencyBondFactoryIsInitialized(
        address caller,
        address tokenA,
        address tokenB
    ) public view returns (bool) {
        return _dualCurrencyBondFactoryIsInitialized[caller][tokenA][tokenB];
    }
}
