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

    constructor(
        string memory uri,
        address token,
        address deployer
    ) BondFactory(uri, token, deployer) {}

    function call(uint256 id) external {
        require(!isCompleted(id) && !isCanceled(id) && !isDefaulted(id), "CBC");
        require(
            timeElapsed(id) > _minObligationPeriod[id] * 1 days,
            "MOPNW"
        );
        _couponRateOnCall[id] =
            (_bondMetadata[id].couponRate * timeElapsed(id)) /
            (_bondMetadata[id].durationInDays * 1 days);
        _isCalled[id] = true;
        _isCompleted[id] = true;

        emit Called(id, _bondMetadata[id].couponRate, _couponRateOnCall[id]);
    }

    function issue(
        uint256 bondQuantity,
        uint256 minPurchasedQuantity,
        uint256 tokenAmountPerBond,
        string calldata ticker,
        uint256 durationDays,
        uint256 activeDurationInDays,
        uint256 rate // coupon rate
    ) external override onlyOwner returns (uint256 id) {
        require(minPurchasedQuantity < bondQuantity, "MPQGTBQ");
        require(durationDays >= 180, "DB6M");
        require(activeDurationInDays <= 7, "ADA7D");
        id = _id + 1;
        _id += 1;
        _mint(msg.sender, id, bondQuantity, "");
        _bondMetadata[id] = BondMetadata(
            ticker,
            tokenAmountPerBond,
            block.timestamp,
            block.timestamp + durationDays * 1 days,
            block.timestamp + activeDurationInDays * 1 days,
            activeDurationInDays,
            durationDays,
            bondQuantity,
            minPurchasedQuantity,
            rate
        );

        _minObligationPeriod[id] = durationDays / 2;
        emit Issued(
            id,
            bondQuantity,
            tokenAmountPerBond,
            rate,
            block.timestamp + durationDays * 1 days
        );
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

    function isCalled(uint256 id) public view returns (bool) {
        return _isCalled[id];
    }

    function minObligationPeriod(uint256 id) public view returns (uint256) {
        return _minObligationPeriod[id];
    }
}
