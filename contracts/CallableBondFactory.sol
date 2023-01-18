// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./BondFactory.sol";

contract CallableBondFactory is BondFactory {
    using Counters for Counters.Counter;
    Counters.Counter private _numBonds; 
    uint256 private constant CATEGORY = 2;

    mapping(uint256 => uint256) _minObligationPeriod; // in days
    mapping(uint256 => uint256) _couponRateOnCall;
    mapping(uint256 => bool) _isCalled;

    event Called(
        uint256 indexed id,
        uint256 couponRate,
        uint256 couponRateOnCall
    );

    constructor(
        address token,
        address bondToken,
        address db,
        address deployer
    ) BondFactory(token, bondToken, db, deployer) {}

    function call(uint256 id) external {
        require(!isCompleted(id) && !isCanceled(id) && !isDefaulted(id), "CBC");
        require(timeElapsed(id) > _minObligationPeriod[id] * 1 days, "MOPNW");
        _couponRateOnCall[id] =
            (_bondToken.bondMetadataAsStruct(id).couponRate * timeElapsed(id)) /
            (_bondToken.bondMetadataAsStruct(id).durationInDays * 1 days);
        _isCalled[id] = true;
        _isCompleted[id] = true;

        emit Called(id, _bondToken.bondMetadataAsStruct(id).couponRate, _couponRateOnCall[id]);
    }

    function issue(
        uint256 bondQuantity,
        uint256 minPurchasedQuantity,
        uint256 tokenAmountPerBond,
        string memory ticker,
        uint256 durationInDays,
        uint256 activeDurationInDays,
        uint256 rate // coupon rate
    ) external override onlyOwner returns (uint256 id) {
        require(minPurchasedQuantity < bondQuantity, "MPQGTBQ");
        require(durationInDays >= 180, "DB6M");
        require(activeDurationInDays <= 7, "ADA7D");
        _numBonds.increment();

        IBond.BondMetadata memory metadata = IBond.BondMetadata(
            ticker,
            address(_baseToken),
            msg.sender,
            tokenAmountPerBond,
            block.timestamp,
            block.timestamp + durationInDays * 1 days,
            block.timestamp + activeDurationInDays * 1 days,
            activeDurationInDays,
            durationInDays,
            bondQuantity,
            minPurchasedQuantity,
            rate
        );

        id = _bondToken.mint(
            address(this),
            bondQuantity,
            metadata
        );
        _bonds.push(id);
        _isIssuedByFactory[id] = true;

        _minObligationPeriod[id] = durationInDays / 2;

        _bondDB.incrementNumberOfIssuedBondsByCategory(CATEGORY);
        _bondDB.incrementNumberOfIssuedBondsByCompanyAndCategory(
            _owner,
            CATEGORY
        );

        emit Issued(
            id,
            bondQuantity,
            tokenAmountPerBond,
            rate,
            block.timestamp + durationInDays * 1 days
        );
    }

    //getter

    function principalWithInterest(
        uint256 id
    ) public view override returns (uint256) {
        uint256 couponRate = _bondToken.bondMetadataAsStruct(id).couponRate;
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
