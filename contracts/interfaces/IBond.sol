// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IBond {
    struct BondMetadata {
        string ticker;
        address currency;
        address issuer;
    }

    struct BondData {
        uint256 tokenAmountPerBond;
        uint256 initBlock;
        uint256 maturityBlock;
        uint256 endOfActiveBlock;
        uint256 activeDurationInDays;
        uint256 durationInDays; // x days
        uint256 issuedQuantity;
        uint256 minPurchasedQuantity;
        uint256 couponRate; // 1e18 -> 100%
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 id,
        uint256 value,
        bytes memory data
    ) external;

    function mint(
        address to,
        uint256 bondQuantity,
        BondData memory data,
        BondMetadata memory metadata
    ) external returns (uint256 id);

    function burn(address account, uint256 id, uint256 quantity) external;

    function bondData(
        uint256 id
    )
        external
        view
        returns (
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256, // x days
            uint256,
            uint256,
            uint256
        );

    function bondMetadata(
        uint256 id
    ) external view returns (string memory, address, address);

    function bondDataAsStruct(
        uint256 id
    ) external view returns (BondData memory);

    function bondMetadataAsStruct(
        uint256 id
    ) external view returns (BondMetadata memory);

    function numBondsIssued() external view returns (uint256);

    function balanceOf(
        address owner,
        uint256 id
    ) external view returns (uint256);

    function timeElapsed(uint256 id) external view returns (uint256);

    function timeRemainingToMaturity(
        uint256 id
    ) external view returns (uint256);

    function timeRemainingToEndOfActive(
        uint256 id
    ) external view returns (uint256);

    function hasReachedMaturity(uint256 id) external view returns (bool);

    function isActive(uint256 id) external view returns (bool);
}
