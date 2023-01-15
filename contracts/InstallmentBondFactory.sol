// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./BondFactory.sol";

contract InstallmentBondFactory is BondFactory {
    uint256 constant FACTOR = 180;
    uint256[] THREE = [5, 5, 10, 15, 15];
    uint256[] FIVE = [2, 3, 5, 5, 5, 10, 10, 15, 15];
    uint256[] TEN = [2, 2, 2, 4, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 10];

    mapping(uint256 => uint256) _nextObligationDate;
    mapping(uint256 => uint256[]) _minObligationTokenAmountPerBondList;
    mapping(uint256 => uint256) _lockedTokenAmount;
    mapping(uint256 => uint256) _numberOfTimesFulfilled;

    modifier validYearOption(uint256 option) {
        require(option >= 0 && option <= 2, "Year option out of range");
        _;
    }

    constructor(string memory uri, address token) BondFactory(uri, token) {}

    function issue(
        uint256 bondQuantity,
        uint256 minPurchasedQuantity,
        uint256 tokenAmountPerBond,
        string calldata ticker,
        uint256 yearOption,
        uint256 activeDurationInDays,
        uint256 rate, // coupon rate
        bytes memory data
    )
        external
        override
        onlyOwner
        validYearOption(yearOption)
        returns (uint256 id)
    {
        require(
            activeDurationInDays < FACTOR,
            "Active duration should be shorter than 180 days"
        );

        uint256 durationDays = yearOptionToDays(yearOption);

        id = _id + 1;
        _mint(msg.sender, id, bondQuantity, data);
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

        emit Issued(id, bondQuantity, tokenAmountPerBond, rate);
    }

    function fulfillObligationsAndLock(
        uint256 id,
        uint256 tokenAmountPerBond
    ) external onlyOwner {
        require(
            !(isDefaulted(id) || isDefaultedInTheory(id)),
            "Withdraw not allowed when defaulted"
        );
        require(
            (_numberOfTimesFulfilled[id] + 1) * FACTOR !=
                _bondMetadata[id].durationInDays,
            "All obligations fulfilled"
        );
        require(
            tokenAmountPerBond >=
                _minObligationTokenAmountPerBondList[id][
                    _numberOfTimesFulfilled[id]
                ],
            "Minimum obligation not fulfilled"
        );
        require(
            (((tokenAmountPerBond -
                _minObligationTokenAmountPerBondList[id][
                    _numberOfTimesFulfilled[id]
                ]) * 1e18) /
                _minObligationTokenAmountPerBondList[id][
                    _numberOfTimesFulfilled[id]
                ]) <= 5e16,
            "Fulfillment should not exceed 5% above obligation"
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
        require(!isActive(id), "Withdraw not allowed when active");
        require(!isCanceled(id), "Withdraw not allowed when active");
        require(!isCompleted(id), "Withdraw not allowed after completion");
        require(
            !(isDefaulted(id) || isDefaultedInTheory(id)),
            "Withdraw not allowed when defaulted"
        );
        require(
            tokenAmount <= _designatedTokenPool[id] - _lockedTokenAmount[id],
            "Withdrawal token amount exceeds token amount in contract"
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

    function lockedTokenAmount(uint256 id) public view returns (uint256) {
        return _lockedTokenAmount[id];
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
}
