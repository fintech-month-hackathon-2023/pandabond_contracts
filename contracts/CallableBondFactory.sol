// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./BondFactory.sol";

contract CallableBondFactory is BondFactory {
    mapping(uint256 => uint256) _minObligationPeriod; // in days
    mapping(uint256 => uint256) _couponRateOnCall;
    mapping(uint256 => bool) _isCalled;

    event Called(
        uint256 indexed id,
        uint256 couponRate,
        uint256 couponRateOnCall
    );

    constructor(string memory uri, address token) BondFactory(uri, token) {}

    function call(uint256 id) external {
        require(!isCompleted(id), "Bond is completed");
        require(
            timeElapsed(id) > _minObligationPeriod[id] * 1 days,
            "Minimum obligation period not reached"
        );
        _couponRateOnCall[id] =
            (_bondMetadata[id].couponRate * timeElapsed(id)) /
            (_bondMetadata[id].durationInDays * 1 days);
        _isCalled[id] = true;

        emit Called(id, _bondMetadata[id].couponRate, _couponRateOnCall[id]);
    }

    function issue(
        uint256 bondQuantity,
        uint256 minPurchasedQuantity,
        uint256 tokenAmountPerBond,
        string calldata ticker,
        uint256 durationDays,
        uint256 activeDurationInDays,
        uint256 rate, // coupon rate
        bytes memory data
    ) external override onlyOwner returns (uint256 id) {
        id = BondFactory(address(this)).issue(
            bondQuantity,
            minPurchasedQuantity,
            tokenAmountPerBond,
            ticker,
            durationDays,
            activeDurationInDays,
            rate,
            data
        );
        _minObligationPeriod[id] = durationDays / 2;
    }

    //getter

    function principalWithInterest(
        uint256 id
    ) public view override returns (uint256) {
        uint256 couponRate = _bondMetadata[id].couponRate;
        if (_isCalled[id]) couponRate = couponRateOnCall(id);

        return principal(id) + (principal(id) * couponRate) / 1e18;
    }

    function couponRateOnCall(uint256 id) public view returns (uint256) {
        return _couponRateOnCall[id];
    }
}
