// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

contract DualCurrencyBondFactory is ERC1155, IERC1155Receiver {
    AggregatorV3Interface immutable _priceFeedA;
    AggregatorV3Interface immutable _priceFeedB;

    address immutable _owner;
    IERC20 immutable _tokenA;
    IERC20 immutable _tokenB;
    uint256 _id = 0;

    uint256 _fundsRaised;

    struct BondMetadata {
        string ticker;
        uint256 tokenAAmountPerBond;
        uint256 tokenBAmountPerBond;
        uint256 initBlock;
        uint256 maturityBlock;
        uint256 endOfActiveBlock;
        uint256 activeDurationInDays;
        uint256 durationInDays; // x days
        uint256 issuedQuantity;
        uint256 minPurchasedQuantity;
        uint256 couponRate; // 1e18 -> 100%
    }

    mapping(uint256 => BondMetadata) _bondMetadata;
    mapping(uint256 => uint256) _purchasedQuantity;
    mapping(uint256 => uint256) _redeemedQuantity;
    mapping(uint256 => uint256) _designatedTokenAPool;
    mapping(uint256 => uint256) _designatedTokenBPool;
    mapping(uint256 => uint256) _tokenAAmountPerBondAfterDefault;
    mapping(uint256 => uint256) _tokenBAmountPerBondAfterDefault;
    mapping(uint256 => uint256) _tokenBAmountPerBondAfterComplete;

    mapping(uint256 => bool) _isDefaulted;
    mapping(uint256 => bool) _isCompleted;

    modifier onlyOwner() {
        require(msg.sender == _owner, "NTO");
        _;
    }

    event Issued(
        uint256 indexed id,
        uint256 bondQuantity,
        uint256 tokenAAmountPerBond,
        uint256 tokenBAmountPerBond,
        uint256 couponRate,
        uint256 maturityDate
    );
    event Defaulted(
        uint256 indexed id,
        uint256 totalDebt,
        uint256 paidDebtA,
        uint256 paidDebtB
    );
    event Completed(uint256 indexed id, uint256 totalDebt, uint256 paidDebt);
    event Redeemed(
        uint256 indexed id,
        address buyer,
        uint256 bondQuantity,
        uint256 state
    );

    constructor(
        string memory uri,
        address a,
        address b,
        address priceFeedA,
        address priceFeedB,
        address deployer
    ) ERC1155(uri) {
        _owner = deployer;
        _tokenA = IERC20(a);
        _tokenB = IERC20(b);

        _priceFeedA = AggregatorV3Interface(priceFeedA);
        _priceFeedB = AggregatorV3Interface(priceFeedB);
    }

    function getLatestPriceA() public view returns (int) {
        (
            ,
            /*uint80 roundID*/ int price /*uint startedAt*/ /*uint timeStamp*/ /*uint80 answeredInRound*/,
            ,
            ,

        ) = _priceFeedA.latestRoundData();
        return price;
    }

    function getLatestPriceB() public view returns (int) {
        (
            ,
            /*uint80 roundID*/ int price /*uint startedAt*/ /*uint timeStamp*/ /*uint80 answeredInRound*/,
            ,
            ,

        ) = _priceFeedB.latestRoundData();
        return price;
    }

    function getAtoBExchangeRate() public view returns (uint256) {
        return (uint256(getLatestPriceA()) * 1e9) / uint256(getLatestPriceB()); // n * 1e9
    }

    function issue(
        uint256 bondQuantity,
        uint256 minPurchasedQuantity,
        uint256 tokenAAmountPerBond,
        string calldata ticker,
        uint256 durationDays,
        uint256 activeDurationInDays,
        uint256 rate // coupon rate
    ) external virtual onlyOwner returns (uint256 id) {
        require(minPurchasedQuantity < bondQuantity, "MPQGTBQ");
        require(durationDays >= 180, "DB6M");
        require(activeDurationInDays <= 7, "ADA7D");
        id = _id + 1;
        _id += 1;
        _mint(address(this), id, bondQuantity, "");
        uint256 exchangeRate = getAtoBExchangeRate();
        uint256 tokenBAmountPerBond = (exchangeRate * tokenAAmountPerBond) /
            1e9;
        _bondMetadata[id] = BondMetadata(
            ticker,
            tokenAAmountPerBond,
            tokenBAmountPerBond,
            block.timestamp,
            block.timestamp + durationDays * 1 days,
            block.timestamp + activeDurationInDays * 1 days,
            activeDurationInDays,
            durationDays,
            bondQuantity,
            minPurchasedQuantity,
            rate
        );

        emit Issued(
            id,
            bondQuantity,
            tokenAAmountPerBond,
            tokenBAmountPerBond,
            rate,
            block.timestamp + durationDays * 1 days
        );
    }

    function purchase(uint256 id, uint256 bondQuantity) external {
        require(isActive(id), "IB");
        require(remainingQuantity(id) >= bondQuantity, "IQ");

        BondMetadata memory metadata = _bondMetadata[id];
        uint256 tokenAmount = bondQuantity * metadata.tokenAAmountPerBond;

        _purchasedQuantity[id] += bondQuantity;
        _designatedTokenAPool[id] += tokenAmount;
        _fundsRaised += tokenAmount;

        // requires approve
        _tokenA.transferFrom(msg.sender, address(this), tokenAmount);
        safeTransferFrom(address(this), msg.sender, id, bondQuantity, "");
    }

    function withdraw(
        uint256 id,
        uint256 tokenAmount
    ) external virtual onlyOwner {
        require(
            !isActive(id) &&
                !isCanceled(id) &&
                !(isDefaulted(id) || isDefaultedInTheory(id)),
            "WNA"
        );

        require(tokenAmount <= _designatedTokenAPool[id], "WAE");

        _designatedTokenAPool[id] -= tokenAmount;
        _tokenA.transfer(msg.sender, tokenAmount);
    }

    function withdrawExcess(uint256 id) external onlyOwner {
        require(isCompleted(id) && isFullyRedeemed(id), "WNA");
        require(_designatedTokenBPool[id] > 0, "WFE");

        _designatedTokenBPool[id] = 0;
        _tokenB.transfer(msg.sender, _designatedTokenBPool[id]);
    }

    function redeem(uint256 id, uint256 bondQuantity) external {
        require(balanceOf(msg.sender, id) >= bondQuantity, "IQ");

        require(isCompleted(id) || isCanceled(id) || isDefaulted(id), "RNA");

        uint256 tokenAAmountPerBond;
        uint256 tokenBAmountPerBond;
        uint256 state;

        if (isCompleted(id)) {
            tokenBAmountPerBond = _tokenBAmountPerBondAfterComplete[id];
            state = 0;
        } else if (isCanceled(id)) {
            tokenAAmountPerBond = _bondMetadata[id].tokenAAmountPerBond;
            state = 1;
        } else if (isDefaulted(id)) {
            tokenAAmountPerBond = _tokenAAmountPerBondAfterDefault[id];
            tokenBAmountPerBond = _tokenBAmountPerBondAfterDefault[id];
            state = 2;
        } else {
            revert();
        }

        _burn(msg.sender, id, bondQuantity);
        _redeemedQuantity[id] += bondQuantity;

        if (state == 0) {
            _tokenB.transfer(
                msg.sender,
                bondQuantity * _tokenBAmountPerBondAfterComplete[id]
            );
            _designatedTokenBPool[id] -=
                bondQuantity *
                _tokenBAmountPerBondAfterComplete[id];
        } else if (state == 1) {
            _tokenA.transfer(
                msg.sender,
                bondQuantity * _bondMetadata[id].tokenAAmountPerBond
            );
            _designatedTokenAPool[id] -=
                bondQuantity *
                _bondMetadata[id].tokenAAmountPerBond;
        } else if (state == 2) {
            _tokenA.transfer(
                msg.sender,
                bondQuantity * _tokenAAmountPerBondAfterDefault[id]
            );
            _tokenB.transfer(
                msg.sender,
                bondQuantity * _tokenBAmountPerBondAfterDefault[id]
            );
            _designatedTokenAPool[id] -=
                bondQuantity *
                _tokenAAmountPerBondAfterDefault[id];
            _designatedTokenBPool[id] -=
                bondQuantity *
                _tokenBAmountPerBondAfterDefault[id];
        } else {
            revert();
        }

        emit Redeemed(id, msg.sender, bondQuantity, state);
    }

    function deposit(uint256 id, uint256 tokenAmount) external onlyOwner {
        require(
            !(isDefaulted(id) || isDefaultedInTheory(id)) && !isCompleted(id),
            "DNA"
        );

        _designatedTokenBPool[id] += tokenAmount;
        _tokenB.transferFrom(msg.sender, address(this), tokenAmount);
    }

    function preMaturityDefault(uint256 id) external onlyOwner {
        require(
            !isCompleted(id) &&
                !isDefaulted(id) &&
                (_designatedTokenBPool[id] < principalWithInterest(id)),
            "PMDNA"
        );

        uint256 paidDebtA = _designatedTokenAPool[id];
        uint256 paidDebtB = _designatedTokenBPool[id];

        _tokenAAmountPerBondAfterDefault[id] =
            paidDebtA /
            _purchasedQuantity[id];
        _tokenBAmountPerBondAfterDefault[id] =
            paidDebtB /
            _purchasedQuantity[id];

        _isDefaulted[id] = true;

        emit Defaulted(id, principalWithInterest(id), paidDebtB, paidDebtA);
    }

    function markAsDefaulted(uint256 id) external {
        require(
            !isCompleted(id) && !isDefaulted(id) && isDefaultedInTheory(id),
            "MADNA"
        );
        uint256 callerRewardA = _designatedTokenAPool[id] / 2000;
        uint256 callerRewardB = _designatedTokenBPool[id] / 2000;
        uint256 paidDebtA = _designatedTokenAPool[id] - callerRewardA;
        uint256 paidDebtB = _designatedTokenBPool[id] - callerRewardB;

        _tokenAAmountPerBondAfterDefault[id] =
            paidDebtA /
            _purchasedQuantity[id];
        _tokenBAmountPerBondAfterDefault[id] =
            paidDebtB /
            _purchasedQuantity[id];

        _designatedTokenAPool[id] -= callerRewardA;
        _designatedTokenBPool[id] -= callerRewardB;
        _isDefaulted[id] = true;

        _tokenA.transfer(msg.sender, callerRewardA);
        _tokenB.transfer(msg.sender, callerRewardB);

        emit Defaulted(id, principalWithInterest(id), paidDebtB, paidDebtA);
    }

    function markAsCompleted(uint256 id) external {
        require(
            !isDefaulted(id) && !isCompleted(id) && isCompletedInTheory(id),
            "MACNA"
        );
        uint256 totalDebt = principalWithInterest(id);
        uint256 reward = totalDebt / 1000;
        uint256 paidDebt = totalDebt - reward;
        _tokenBAmountPerBondAfterComplete[id] =
            paidDebt /
            _purchasedQuantity[id];
        uint256 residuals = paidDebt -
            _tokenBAmountPerBondAfterComplete[id] *
            _purchasedQuantity[id];
        uint256 toCaller = reward + residuals;
        _designatedTokenBPool[id] -= toCaller;

        _isCompleted[id] = true;
        _tokenB.transfer(msg.sender, toCaller);

        emit Completed(id, totalDebt, paidDebt);
    }

    function onERC1155Received(address, address, uint256, uint256, bytes memory) public virtual returns (bytes4) {
        return this.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(address, address, uint256[] memory, uint256[] memory, bytes memory) public virtual returns (bytes4) {
        return this.onERC1155BatchReceived.selector;
    }

    function remainingQuantity(uint256 id) public view returns (uint256) {
        return _bondMetadata[id].issuedQuantity - _purchasedQuantity[id];
    }

    function timeElapsed(uint256 id) public view returns (uint256) {
        return block.timestamp - _bondMetadata[id].initBlock;
    }

    function timeRemainingToMaturity(uint256 id) public view returns (uint256) {
        return _bondMetadata[id].maturityBlock - block.timestamp;
    }

    function timeRemainingToEndOfActive(
        uint256 id
    ) public view returns (uint256) {
        return _bondMetadata[id].endOfActiveBlock - block.timestamp;
    }

    function couponRate(uint256 id) public view returns (uint256) {
        return _bondMetadata[id].couponRate;
    }

    function principal(uint256 id) public view returns (uint256) {
        return _bondMetadata[id].tokenBAmountPerBond * _purchasedQuantity[id];
    }

    function principalWithInterest(
        uint256 id
    ) public view virtual returns (uint256) {
        return
            principal(id) +
            (principal(id) * _bondMetadata[id].couponRate) /
            1e18;
    }

    function poolAAmount(uint256 id) public view returns (uint256) {
        return _designatedTokenAPool[id];
    }

    function poolBAmount(uint256 id) public view returns (uint256) {
        return _designatedTokenBPool[id];
    }

    function tvlA() public view returns (uint256) {
        return _tokenA.balanceOf(address(this));
    }

    function tvlB() public view returns (uint256) {
        return _tokenB.balanceOf(address(this));
    }

    function isFullyRedeemed(uint256 id) public view returns (bool) {
        return _redeemedQuantity[id] == _purchasedQuantity[id];
    }

    function isActive(uint256 id) public view returns (bool) {
        return block.timestamp <= _bondMetadata[id].endOfActiveBlock;
    }

    function isFulfilled(uint256 id) public view returns (bool) {
        return _purchasedQuantity[id] >= _bondMetadata[id].minPurchasedQuantity;
    }

    function isCanceled(uint256 id) public view returns (bool) {
        return !isActive(id) && !isFulfilled(id);
    }

    function hasReachedMaturity(uint256 id) public view returns (bool) {
        return block.timestamp > _bondMetadata[id].maturityBlock;
    }

    function isCompleted(uint256 id) public view returns (bool) {
        return _isCompleted[id];
    }

    function isCompletedInTheory(
        uint256 id
    ) public view virtual returns (bool) {
        return (hasReachedMaturity(id) &&
            _designatedTokenBPool[id] >= principalWithInterest(id));
    }

    function isDefaultedInTheory(
        uint256 id
    ) public view virtual returns (bool) {
        return (hasReachedMaturity(id) &&
            _designatedTokenBPool[id] < principalWithInterest(id));
    }

    function isDefaulted(uint256 id) public view virtual returns (bool) {
        return _isDefaulted[id];
    }

    function bondmetaData(
        uint256 id
    )
        public
        view
        virtual
        returns (
            string memory,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256
        )
    {
        BondMetadata memory bm = _bondMetadata[id];
        return (
            bm.ticker,
            bm.tokenAAmountPerBond,
            bm.tokenBAmountPerBond,
            bm.initBlock,
            bm.maturityBlock,
            bm.endOfActiveBlock,
            bm.activeDurationInDays,
            bm.durationInDays,
            bm.issuedQuantity,
            bm.minPurchasedQuantity,
            bm.couponRate
        );
    }

    function designatedTokenAPool(uint256 id) public view returns (uint256) {
        return _designatedTokenAPool[id];
    }

    function designatedTokenBPool(uint256 id) public view returns (uint256) {
        return _designatedTokenBPool[id];
    }

    function tokenA() public view returns (address) {
        return address(_tokenA);
    }

    function tokenB() public view returns (address) {
        return address(_tokenB);
    }

    function owner() public view returns (address) {
        return _owner;
    }

    function fundsRaised() public view returns (uint256) {
        return _fundsRaised;
    }

    function numBondsIssued() public view returns (uint256) {
        return _id;
    }
}
