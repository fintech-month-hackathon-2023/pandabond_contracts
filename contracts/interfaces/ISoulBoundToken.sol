// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface ISoulBoundToken {
    function hasActiveSBT(address owner) external view returns (bool);

    function ownerToTokenId(address owner) external view returns (uint256);

    function accessTier(uint256 id) external view returns (uint8);

    function accessTier(address owner) external view returns (uint8);

    function safeMint(
        address to,
        uint8 tier,
        bytes32 hashed
    ) external returns (uint256 tokenId);

    function modifyTier(uint256 id, uint8 tier) external;

    function deactivate(uint256 id) external;

    function activate(uint256 id) external;
}
