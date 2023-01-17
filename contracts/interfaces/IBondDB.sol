// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IBondDB {
    function registerPeriphery(address[] memory peripheries) external;

    function registerFactory(address factory) external;

    function incrementFundsRaisedByToken(
        uint256 amount,
        address token
    ) external;

    function incrementFundsRaisedByTokenAndCategory(
        uint256 amount,
        address token,
        uint256 category
    ) external;

    function incrementFundsRaisedByCompanyAndToken(
        uint256 amount,
        address company,
        address token
    ) external;

    function incrementFundsRaisedByCompanyAndTokenAndCategory(
        uint256 amount,
        address company,
        address token,
        uint256 category
    ) external;

    function incrementNumberOfIssuedBondsByCategory(uint256 category) external;

    function incrementNumberOfIssuedBondsByCompanyAndCategory(
        address company,
        uint256 category
    ) external;

    function incrementNumberOfTimesDefaultedByCompany(address company) external;

    function incrementNumberOfTimesDefaultedByCompanyAndCategory(
        address company,
        uint256 category
    ) external;

    function owner() external view;

    function isPeriphery(address account) external view;

    function isFactory(address account) external view;

    function fundsRaisedByToken(address token) external view;

    function fundsRaisedByTokenAndCategory(
        address token,
        uint256 category
    ) external view;

    function fundsRaisedByCompanyAndToken(
        address company,
        address token
    ) external view;

    function fundsRaisedByCompanyAndTokenAndCategory(
        address company,
        address token,
        uint256 category
    ) external view;

    function numberOfIssuedBondsByCategory(uint256 category) external view;

    function numberOfIssuedBondsByCompanyAndCategory(
        address company,
        uint256 category
    ) external view;

    function numberOfTimesDefaultedByCompany(address company) external view;

    function numberOfTimesDefaultedByCompanyAndCategory(
        address company,
        uint256 category
    ) external view;
}
