// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./InstallmentBondFactory.sol";
import "./SoulBoundToken.sol";

contract InstallmentBondPeriphery {
    address immutable _owner;
    SoulBoundToken immutable _sbt;

    address[] _entities;

    mapping(address => bool) _isRegistered;

    mapping(address => address[]) _installmentBondFactories;

    mapping(address => mapping(address => bool)) _installmentBondFactoryIsInitialized;

    event InstallmentBondFactoryInitialized(
        address indexed owner,
        address token
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

    function createInstallmentBondFactory(
        string memory uri,
        address token
    ) external onlyIsRegistered hasActiveSBT returns (address factory) {
        require(
            _sbt.accessTier(msg.sender) >= 3,
            "Caller does not have valid access tier"
        );
        require(
            !_installmentBondFactoryIsInitialized[msg.sender][token],
            "Factory is already initialized"
        );
        factory = address(new InstallmentBondFactory(uri, token, msg.sender));
        _installmentBondFactories[msg.sender].push(factory);
        _installmentBondFactoryIsInitialized[msg.sender][token] = true;

        emit InstallmentBondFactoryInitialized(msg.sender, token);
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

    function installmentBondFactories(
        address caller
    ) public view returns (address[] memory) {
        return _installmentBondFactories[caller];
    }

    function installmentBondFactoryIsInitialized(
        address caller,
        address token
    ) public view returns (bool) {
        return _installmentBondFactoryIsInitialized[caller][token];
    }
}
