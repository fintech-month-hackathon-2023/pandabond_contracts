// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./CallableBondFactory.sol";
import "./SoulBoundToken.sol";

contract CallableBondPeriphery {
    address immutable _owner;
    SoulBoundToken immutable _sbt;

    address[] _entities;

    mapping(address => bool) _isRegistered;

    mapping(address => address[]) _callableBondFactories;

    mapping(address => mapping(address => bool)) _callableBondFactoryIsInitialized;

    event CallableBondFactoryInitialized(address indexed owner, address token);

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
    }

    function register() external hasActiveSBT {
        require(
            _sbt.accessTier(msg.sender) >= 1,
            "Caller does not have valid access tier"
        );
        require(!_isRegistered[msg.sender], "Caller is already registered");
        _isRegistered[msg.sender] = true;
        _entities.push(msg.sender);
    }

    function createCallableBondFactory(
        string memory uri,
        address token
    ) external onlyIsRegistered hasActiveSBT returns (address factory) {
        require(
            _sbt.accessTier(msg.sender) >= 1,
            "Caller does not have valid access tier"
        );
        require(
            !_callableBondFactoryIsInitialized[msg.sender][token],
            "Factory is already initialized"
        );
        factory = address(new CallableBondFactory(uri, token, msg.sender));
        _callableBondFactories[msg.sender].push(factory);
        _callableBondFactoryIsInitialized[msg.sender][token] = true;

        emit CallableBondFactoryInitialized(msg.sender, token);
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

    function callableBondFactories(
        address caller
    ) public view returns (address[] memory) {
        return _callableBondFactories[caller];
    }

    function callableBondFactoryIsInitialized(
        address caller,
        address token
    ) public view returns (bool) {
        return _callableBondFactoryIsInitialized[caller][token];
    }
}
