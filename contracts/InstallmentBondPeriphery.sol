// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./InstallmentBondFactory.sol";
import "./interfaces/ISoulBoundToken.sol";

import "./BondPeriphery.sol";

contract InstallmentBondPeriphery is BondPeriphery {
    constructor(address sbt) BondPeriphery(sbt) {}

    function register() external override hasActiveSBT {
        require(!_isRegistered[msg.sender], "AR");
        require(_sbt.accessTier(msg.sender) >= 3, "NVAT");

        _isRegistered[msg.sender] = true;
        _entities.push(msg.sender);
    }

    function createBondFactory(
        string memory uri,
        address token
    )
        external
        override
        onlyIsRegistered
        hasActiveSBT
        onlyAllowedCurrencies(token)
        returns (address factory)
    {
        require(_sbt.accessTier(msg.sender) >= 3, "NVAT");
        require(!_bondFactoryIsInitialized[msg.sender][token], "AI");
        factory = address(new InstallmentBondFactory(uri, token, msg.sender));
        _bondFactories[msg.sender].push(factory);
        _bondFactoryIsInitialized[msg.sender][token] = true;

        emit FactoryInitialized(msg.sender, token);
    }
}
