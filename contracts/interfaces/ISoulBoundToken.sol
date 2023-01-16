// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface ISoulBoundToken {
    function hasActiveSBT(address owner) external view returns (bool);

    function ownerToTokenId(address owner) external view returns (uint256);

    function accessTier(uint256 id) external view returns (uint8);

    function accessTier(address owner) external view returns (uint8);
}
