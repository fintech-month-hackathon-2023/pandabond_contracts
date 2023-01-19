// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

import "../interfaces/IBondDB.sol";
import "../interfaces/IBond.sol";

contract BondFactory is ERC1155Holder {
    using Counters for Counters.Counter;
    Counters.Counter private _numBonds;

    address immutable _owner;
    IERC20 immutable _baseToken;
    IBondDB immutable _bondDB;
    IBond immutable _bondToken;

    uint256 private constant CATEGORY = 1;

    uint256[] _bonds;

    mapping(uint256 => uint256) _purchasedQuantity;
    mapping(uint256 => uint256) _redeemedQuantity;
    mapping(uint256 => uint256) _designatedTokenPool;
    mapping(uint256 => uint256) _tokenAmountPerBondAfterDefault;
    mapping(uint256 => uint256) _tokenAmountPerBondAfterComplete;

    mapping(uint256 => bool) _isIssuedByFactory;
    mapping(uint256 => bool) _isDefaulted;
    mapping(uint256 => bool) _isCompleted;

    modifier onlyOwner() {
        require(msg.sender == _owner, "NTO");
        _;
    }

    event Issued(
        uint256 indexed id,
        uint256 bondQuantity,
        uint256 tokenAmountPerBond,
        uint256 couponRate,
        uint256 maturityDate
    );
    event Defaulted(uint256 indexed id, uint256 totalDebt, uint256 paidDebt);
    event Completed(uint256 indexed id, uint256 totalDebt, uint256 paidDebt);
    event Redeemed(
        uint256 indexed id,
        address buyer,
        uint256 bondQuantity,
        uint256 state
    );

    constructor(
        address token,
        address bondToken,
        address db,
        address deployer
    ) {
        _owner = deployer;
        _baseToken = IERC20(token);
        _bondDB = IBondDB(db);
        _bondToken = IBond(bondToken);
    }

    function issue(
        uint256 bondQuantity,
        uint256 minPurchasedQuantity,
        uint256 tokenAmountPerBond,
        string memory ticker,
        uint256 durationInDays,
        uint256 activeDurationInDays,
        uint256 rate // coupon rate
    ) external virtual onlyOwner returns (uint256 id) {
        require(minPurchasedQuantity < bondQuantity, "MPQGTBQ");
        require(durationInDays >= 180, "DB6M");
        require(activeDurationInDays <= 7, "ADA7D");

        _numBonds.increment();

        IBond.BondMetadata memory metadata = IBond.BondMetadata(
            ticker,
            address(_baseToken),
            msg.sender
        );

        IBond.BondData memory data = IBond.BondData(
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

        id = _bondToken.mint(address(this), bondQuantity, data, metadata);

        _bonds.push(id);
        _isIssuedByFactory[id] = true;

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

    function purchase(uint256 id, uint256 bondQuantity) external {
        require(_bondToken.isActive(id), "IB");
        require(remainingQuantity(id) >= bondQuantity, "IQ");

        uint256 tokenAmount = bondQuantity *
            _bondToken.bondDataAsStruct(id).tokenAmountPerBond;

        _purchasedQuantity[id] += bondQuantity;
        _designatedTokenPool[id] += tokenAmount;
        _bondDB.incrementTVLByToken(tokenAmount, address(_baseToken));
        _bondDB.incrementFundsRaisedByToken(tokenAmount, address(_baseToken));
        _bondDB.incrementFundsRaisedByCompanyAndToken(
            tokenAmount,
            _owner,
            address(_baseToken)
        );
        _bondDB.incrementFundsRaisedByCompanyAndTokenAndCategory(
            tokenAmount,
            _owner,
            address(_baseToken),
            CATEGORY
        );
        _bondDB.incrementFundsRaisedByTokenAndCategory(
            tokenAmount,
            address(_baseToken),
            CATEGORY
        );

        _bondToken.safeTransferFrom(
            address(this),
            msg.sender,
            id,
            bondQuantity,
            ""
        );
        _baseToken.transferFrom(msg.sender, address(this), tokenAmount);
    }

    function withdraw(
        uint256 id,
        uint256 tokenAmount
    ) external virtual onlyOwner {
        require(
            !_bondToken.isActive(id) &&
                !isCanceled(id) &&
                !isCompleted(id) &&
                !(isDefaulted(id) || isDefaultedInTheory(id)),
            "WNA"
        );

        require(tokenAmount <= _designatedTokenPool[id], "WAE");

        _designatedTokenPool[id] -= tokenAmount;
        _bondDB.decrementTVLByToken(tokenAmount, address(_baseToken));

        _baseToken.transfer(msg.sender, tokenAmount);
    }

    function withdrawExcess(uint256 id) external onlyOwner {
        require(isCompleted(id) && isFullyRedeemed(id), "WNA");
        require(_designatedTokenPool[id] > 0, "WFE");

        uint256 tokenAmount = _designatedTokenPool[id];
        _designatedTokenPool[id] = 0;
        _bondDB.decrementTVLByToken(tokenAmount, address(_baseToken));

        _baseToken.transfer(msg.sender, tokenAmount);
    }

    function redeem(uint256 id, uint256 bondQuantity) external {
        require(_bondToken.balanceOf(msg.sender, id) >= bondQuantity, "IQ");

        require(isCompleted(id) || isCanceled(id) || isDefaulted(id), "RNA");

        uint256 tokenAmountPerBond;
        uint256 state;

        if (isCompleted(id)) {
            tokenAmountPerBond = _tokenAmountPerBondAfterComplete[id];
            state = 0;
        } else if (isCanceled(id)) {
            tokenAmountPerBond = _bondToken
                .bondDataAsStruct(id)
                .tokenAmountPerBond;
            state = 1;
        } else if (isDefaulted(id)) {
            tokenAmountPerBond = _tokenAmountPerBondAfterDefault[id];
            state = 2;
        } else {
            revert();
        }

        _bondToken.burn(msg.sender, id, bondQuantity);
        _redeemedQuantity[id] += bondQuantity;
        uint256 tokenAmount = bondQuantity * tokenAmountPerBond;

        _designatedTokenPool[id] -= tokenAmount;
        _bondDB.decrementTVLByToken(tokenAmount, address(_baseToken));

        _baseToken.transfer(msg.sender, tokenAmount);

        emit Redeemed(id, msg.sender, bondQuantity, state);
    }

    function deposit(uint256 id, uint256 tokenAmount) external onlyOwner {
        require(
            !(isDefaulted(id) || isDefaultedInTheory(id)) && !isCompleted(id),
            "DNA"
        );

        _designatedTokenPool[id] += tokenAmount;
        _bondDB.incrementTVLByToken(tokenAmount, address(_baseToken));

        _baseToken.transferFrom(msg.sender, address(this), tokenAmount);
    }

    function preMaturityDefault(uint256 id) external onlyOwner {
        require(
            !isCompleted(id) &&
                !isDefaulted(id) &&
                (_designatedTokenPool[id] < principalWithInterest(id)),
            "PMDNA"
        );

        uint256 paidDebt = _designatedTokenPool[id];
        _tokenAmountPerBondAfterDefault[id] = paidDebt / _purchasedQuantity[id];

        _isDefaulted[id] = true;

        _bondDB.incrementNumberOfTimesDefaultedByCompany(_owner);
        _bondDB.incrementNumberOfTimesDefaultedByCompanyAndCategory(
            _owner,
            CATEGORY
        );

        emit Defaulted(id, principalWithInterest(id), paidDebt);
    }

    function markAsDefaulted(uint256 id) external {
        require(
            !isCompleted(id) && !isDefaulted(id) && isDefaultedInTheory(id),
            "MADNA"
        );
        uint256 callerReward = _designatedTokenPool[id] / 1000;
        uint256 paidDebt = _designatedTokenPool[id] - callerReward;

        _tokenAmountPerBondAfterDefault[id] = paidDebt / _purchasedQuantity[id];
        _designatedTokenPool[id] -= callerReward;

        _isDefaulted[id] = true;

        _bondDB.incrementNumberOfTimesDefaultedByCompany(_owner);
        _bondDB.incrementNumberOfTimesDefaultedByCompanyAndCategory(
            _owner,
            CATEGORY
        );

        _bondDB.decrementTVLByToken(callerReward, address(_baseToken));

        _baseToken.transfer(msg.sender, callerReward);

        emit Defaulted(id, principalWithInterest(id), paidDebt);
    }

    function markAsCompleted(uint256 id) external {
        require(
            !isDefaulted(id) && !isCompleted(id) && isCompletedInTheory(id),
            "MACNA"
        );
        uint256 totalDebt = principalWithInterest(id);
        uint256 callerReward = totalDebt / 1000;
        uint256 paidDebt = totalDebt - callerReward;
        _tokenAmountPerBondAfterComplete[id] =
            paidDebt /
            _purchasedQuantity[id];
        _designatedTokenPool[id] -= callerReward;
        _isCompleted[id] = true;

        _bondDB.decrementTVLByToken(callerReward, address(_baseToken));
        _baseToken.transfer(msg.sender, callerReward);

        emit Completed(id, totalDebt, paidDebt);
    }

    function remainingQuantity(uint256 id) public view returns (uint256) {
        return
            _bondToken.bondDataAsStruct(id).issuedQuantity -
            _purchasedQuantity[id];
    }

    function principal(uint256 id) public view returns (uint256) {
        return
            _bondToken.bondDataAsStruct(id).tokenAmountPerBond *
            _purchasedQuantity[id];
    }

    function principalWithInterest(
        uint256 id
    ) public view virtual returns (uint256) {
        return
            principal(id) +
            (principal(id) * _bondToken.bondDataAsStruct(id).couponRate) /
            1e18;
    }

    function poolAmount(uint256 id) public view returns (uint256) {
        return _designatedTokenPool[id];
    }

    function tvl() public view returns (uint256) {
        return _baseToken.balanceOf(address(this));
    }

    function isFullyRedeemed(uint256 id) public view returns (bool) {
        return _redeemedQuantity[id] == _purchasedQuantity[id];
    }

    function isFulfilled(uint256 id) public view returns (bool) {
        return
            _purchasedQuantity[id] >=
            _bondToken.bondDataAsStruct(id).minPurchasedQuantity;
    }

    function isCanceled(uint256 id) public view returns (bool) {
        return !_bondToken.isActive(id) && !isFulfilled(id);
    }

    function isCompleted(uint256 id) public view returns (bool) {
        return _isCompleted[id];
    }

    function isCompletedInTheory(
        uint256 id
    ) public view virtual returns (bool) {
        return (_bondToken.hasReachedMaturity(id) &&
            _designatedTokenPool[id] >= principalWithInterest(id));
    }

    function isDefaultedInTheory(
        uint256 id
    ) public view virtual returns (bool) {
        return (_bondToken.hasReachedMaturity(id) &&
            _designatedTokenPool[id] < principalWithInterest(id));
    }

    function isDefaulted(uint256 id) public view virtual returns (bool) {
        return _isDefaulted[id];
    }

    function baseToken() public view returns (address) {
        return address(_baseToken);
    }

    function owner() public view returns (address) {
        return _owner;
    }

    function designatedTokenPool(uint256 id) public view returns (uint256) {
        return _designatedTokenPool[id];
    }

    function isIssuedByFactory(uint256 id) public view returns (bool) {
        return _isIssuedByFactory[id];
    }

    function bonds() public view returns (uint256[] memory) {
        return _bonds;
    }
}
