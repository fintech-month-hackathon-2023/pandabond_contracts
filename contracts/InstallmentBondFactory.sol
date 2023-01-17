// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./BondFactory.sol";

contract InstallmentBondFactory is BondFactory {
    using Counters for Counters.Counter;
    Counters.Counter private _id;

    uint256 private constant CATEGORY = 3;

    uint256 constant FACTOR = 180;
    uint256[] THREE = [5, 5, 10, 15, 15];
    uint256[] FIVE = [2, 2, 2, 2, 2, 5, 10, 10, 15];
    uint256[] TEN = [2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 5, 5, 5, 5];

    mapping(uint256 => uint256) _nextObligationDate;
    mapping(uint256 => uint256[]) _minObligationTokenAmountPerBondList;
    mapping(uint256 => uint256) _lockedTokenAmount;
    mapping(uint256 => uint256) _numberOfTimesFulfilled;

    modifier validYearOption(uint256 option) {
        require(option >= 0 && option <= 2, "IYO");
        _;
    }

    constructor(
        string memory uri,
        address token,
        address db,
        address deployer
    ) BondFactory(uri, token, db, deployer) {}

    function issue(
        uint256 bondQuantity,
        uint256 minPurchasedQuantity,
        uint256 tokenAmountPerBond,
        string calldata ticker,
        uint256 yearOption,
        uint256 activeDurationInDays,
        uint256 rate // coupon rate
    )
        external
        override
        onlyOwner
        validYearOption(yearOption)
        returns (uint256 id)
    {
        require(minPurchasedQuantity < bondQuantity, "MPQGTBQ");
        require(activeDurationInDays <= 7, "ADA7D");

        uint256 durationDays = yearOptionToDays(yearOption);

        id = _id.current();
        _id.increment();

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

        _nextObligationDate[id] = block.timestamp + FACTOR * 1 days;
        _minObligationTokenAmountPerBondList[id] = retrieveMinObligationList(
            tokenAmountPerBond,
            yearOption
        );

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
            block.timestamp + durationDays * 1 days
        );
    }

    function fulfillObligationsAndLock(
        uint256 id,
        uint256 tokenAmountPerBond
    ) external onlyOwner {
        require(!(isDefaulted(id) || isDefaultedInTheory(id)), "WNA");
        require(
            (_numberOfTimesFulfilled[id] + 1) * FACTOR !=
                _bondMetadata[id].durationInDays,
            "OAF"
        );
        require(
            tokenAmountPerBond >=
                _minObligationTokenAmountPerBondList[id][
                    _numberOfTimesFulfilled[id]
                ],
            "MONF"
        );
        require(
            (((tokenAmountPerBond -
                _minObligationTokenAmountPerBondList[id][
                    _numberOfTimesFulfilled[id]
                ]) * 1e18) /
                _minObligationTokenAmountPerBondList[id][
                    _numberOfTimesFulfilled[id]
                ]) <= 5e16,
            "EMF"
        );

        uint256 tokenAmount = tokenAmountPerBond *
            _bondMetadata[id].issuedQuantity;
        _lockedTokenAmount[id] += tokenAmount;
        _nextObligationDate[id] = _nextObligationDate[id] + FACTOR * 1 days;
        _numberOfTimesFulfilled[id] += 1;
        _baseToken.transferFrom(msg.sender, address(this), tokenAmount);
    }

    function withdraw(
        uint256 id,
        uint256 tokenAmount
    ) external override onlyOwner {
        require(
            !isActive(id) &&
                !isCanceled(id) &&
                !isCompleted(id) &&
                !(isDefaulted(id) || isDefaultedInTheory(id)),
            "WNA"
        );
        require(
            tokenAmount <= _designatedTokenPool[id] - _lockedTokenAmount[id],
            "WAE"
        );

        _designatedTokenPool[id] -= tokenAmount;
        _baseToken.transfer(msg.sender, tokenAmount);
    }

    //getter

    function isDefaultedInTheory(
        uint256 id
    ) public view override returns (bool) {
        bool cond1 = hasReachedMaturity(id) &&
            _designatedTokenPool[id] < principalWithInterest(id);
        bool cond2 = !hasReachedMaturity(id) &&
            (block.timestamp >
                (_numberOfTimesFulfilled[id] + 1) * 180 * 1 days);

        return cond1 || cond2;
    }

    function lockedTokenAmountPerBond(
        uint256 id
    ) public view returns (uint256) {
        return
            (lockedTokenAmount(id) * 1e18) /
            _bondMetadata[id].issuedQuantity /
            1e18;
    }

    function yearOptionToDays(
        uint256 option
    ) public pure validYearOption(option) returns (uint256) {
        uint256 year = 2 * FACTOR;
        if (option == 0) {
            return 3 * year;
        } else if (option == 1) {
            return 5 * year;
        } else {
            return 10 * year;
        }
    }

    function yearOptionToObligationRateList(
        uint256 option
    ) public view validYearOption(option) returns (uint256[] memory) {
        if (option == 0) {
            return THREE;
        } else if (option == 1) {
            return FIVE;
        } else {
            return TEN;
        }
    }

    function retrieveMinObligationList(
        uint256 tokenAmountPerBond,
        uint256 yearOption
    ) public view validYearOption(yearOption) returns (uint256[] memory) {
        uint256[] memory obligationRateList = yearOptionToObligationRateList(
            yearOption
        );
        uint256 length = obligationRateList.length;
        uint256[] memory obligationPerBondList = new uint256[](length);

        for (uint i = 0; i < length; i++) {
            obligationPerBondList[i] =
                (tokenAmountPerBond * obligationRateList[i]) /
                100;
        }
        return obligationPerBondList;
    }

    function nextObligationDate(uint256 id) public view returns (uint256) {
        return _nextObligationDate[id];
    }

    function minObligationTokenAmountPerBondList(
        uint256 id
    ) public view returns (uint256[] memory) {
        return _minObligationTokenAmountPerBondList[id];
    }

    function lockedTokenAmount(uint256 id) public view returns (uint256) {
        return _lockedTokenAmount[id];
    }

    function numberOfTimesFulfilled(uint256 id) public view returns (uint256) {
        return _numberOfTimesFulfilled[id];
    }
}
