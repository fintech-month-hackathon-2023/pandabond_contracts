// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";


contract DualCurrencyBondFactory is ERC1155 {
    AggregatorV3Interface internal _priceFeedA;
    AggregatorV3Interface internal _priceFeedB;
    
    address immutable _owner;
    IERC20 immutable _tokenA; 
    IERC20 immutable _tokenB;
    uint256 _id = 0;


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
        require(msg.sender == _owner, "Caller is not the owner");
        _;
    }

    event Issued(uint256 indexed id, uint256 bondQuantity, uint256 tokenAAmountPerBond, uint256 tokenBAmountPerBond, uint256 couponRate);
    event Defaulted(uint256 indexed id, uint256 totalDebt, uint256 paidDebtA, uint256 paidDebtB);
    event Completed(uint256 indexed id, uint256 totalDebt, uint256 paidDebt);

    constructor(string memory uri, address tokenA, address tokenB, address priceFeedA, address priceFeedB) ERC1155(uri) {
        _owner = msg.sender;
        _tokenA = IERC20(tokenA);
        _tokenB = IERC20(tokenB);

        _priceFeedA = AggregatorV3Interface(
            priceFeedA
        );
        _priceFeedB = AggregatorV3Interface(
            priceFeedB
        );
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
        return uint256(getLatestPriceA()) * 1e9 / uint256(getLatestPriceB()); // n * 1e9
    }

    function issue(
        uint256 bondQuantity, 
        uint256 minPurchasedQuantity, 
        uint256 tokenAAmountPerBond, 
        string calldata ticker, 
        uint256 durationDays, 
        uint256 activeDurationInDays, 
        uint256 rate, // coupon rate
        bytes memory data
        ) external virtual onlyOwner returns(uint256 id) {
        require(activeDurationInDays < durationDays, "Active duration should be shorter than duration");
        id = _id + 1;
        _mint(msg.sender, id, bondQuantity, data);
        uint256 exchangeRate = getAtoBExchangeRate();
        uint256 tokenBAmountPerBond = exchangeRate * tokenAAmountPerBond / 1e9;
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

        emit Issued(id, bondQuantity, tokenAAmountPerBond, tokenBAmountPerBond,rate);
    }

    function purchase(uint256 id, uint256 bondQuantity) external {
        require(isActive(id), "Bond is inactive");
        require(remainingQuantity(id)>= bondQuantity, "Insufficient bond quantity remaining");

        BondMetadata memory metadata = _bondMetadata[id];
        uint256 tokenAmount = bondQuantity * metadata.tokenAAmountPerBond;

        
        _purchasedQuantity[id] += bondQuantity;
        _designatedTokenAPool[id] += tokenAmount;

        // requires approve
        _tokenA.transferFrom(msg.sender,address(this), tokenAmount);

    }

    function withdraw(uint256 id, uint256 tokenAmount) external virtual onlyOwner {
        require(!isActive(id), "Withdraw not allowed when active");
        require(!isCanceled(id), "Withdraw not allowed when active");
        require(!(isDefaulted(id) || isDefaultedInTheory(id)), "Withdraw not allowed when defaulted");

        require(tokenAmount <= _designatedTokenAPool[id], "Withdrawal token amount exceeds token amount in contract");

        _designatedTokenAPool[id] -= tokenAmount;        
        _tokenA.transfer(msg.sender, tokenAmount);

    }

    function withdrawExcess(uint256 id) external onlyOwner {
        require(isCompleted(id) && isFullyRedeemed(id), "Cannot withdraw excess");
        require(_designatedTokenBPool[id] > 0, "Cannot withdraw from empty pool");

        _designatedTokenBPool[id] = 0;
        _tokenB.transfer(msg.sender, _designatedTokenBPool[id]);

    }

    function redeem(uint256 id, uint256 bondQuantity) external {
        require(isCompleted(id), "Bond is not completed");
        require(balanceOf(msg.sender, id)>=bondQuantity, "Insufficient bond quantity");
        _burn(msg.sender, id, bondQuantity);
        _redeemedQuantity[id]+=bondQuantity;
        uint256 tokenAmount = bondQuantity * _tokenBAmountPerBondAfterComplete[id];

        _tokenB.transfer(msg.sender, tokenAmount);
        _designatedTokenBPool[id] -= tokenAmount;
    }

    function redeemCanceled(uint256 id, uint256 bondQuantity) external {
        require(isCanceled(id), "Bond is not canceled");
        require(balanceOf(msg.sender, id)>=bondQuantity, "Insufficient bond quantity");
        _burn(msg.sender, id, bondQuantity);
        _redeemedQuantity[id]+=bondQuantity;
        uint256 tokenAmount = bondQuantity * _bondMetadata[id].tokenAAmountPerBond;

        _tokenA.transfer(msg.sender, tokenAmount);
        _designatedTokenAPool[id] -= tokenAmount;
    }

    function redeemDefaulted(uint256 id, uint256 bondQuantity) external {
        require(isDefaulted(id), "Bond is not defaulted");
        require(balanceOf(msg.sender, id)>=bondQuantity, "Insufficient bond quantity");
        _burn(msg.sender, id, bondQuantity);
        _redeemedQuantity[id]+=bondQuantity;
        uint256 tokenAAmount = bondQuantity * _tokenAAmountPerBondAfterDefault[id];
        uint256 tokenBAmount = bondQuantity * _tokenBAmountPerBondAfterDefault[id];


        _tokenA.transfer(msg.sender, tokenAAmount);
        _tokenB.transfer(msg.sender, tokenBAmount);
        _designatedTokenAPool[id] -= tokenAAmount;
        _designatedTokenBPool[id] -= tokenBAmount;

    }

    function deposit(uint256 id, uint256 tokenAmount) external onlyOwner{
        require(!(isDefaulted(id) || isDefaultedInTheory(id)),"bond is defaulted");
        require(!isCompleted(id), "bond is completed");

        _designatedTokenBPool[id] += tokenAmount;
        _tokenB.transferFrom(msg.sender, address(this), tokenAmount);

    }

    function markAsDefaulted(uint256 id) external {
        require(!isDefaulted(id) && isDefaultedInTheory(id), "Bond is not defaulted");
        uint256 totalDebt = principalWithInterest(id);
        uint256 rewardA = _designatedTokenAPool[id]/1000;
        uint256 rewardB = _designatedTokenBPool[id]/1000;
        uint256 paidDebtA = _designatedTokenAPool[id] - rewardA;
        uint256 paidDebtB = _designatedTokenBPool[id] - rewardB;


        _tokenAAmountPerBondAfterDefault[id] = paidDebtA / _purchasedQuantity[id];
        _tokenBAmountPerBondAfterDefault[id] = paidDebtB / _purchasedQuantity[id];
        uint256 residualsA = paidDebtA - _tokenAAmountPerBondAfterDefault[id] * _purchasedQuantity[id]; //if token A residuals exist
        uint256 residualsB = paidDebtB - _tokenBAmountPerBondAfterDefault[id] * _purchasedQuantity[id]; //if token A residuals exist

        uint256 toCallerA = rewardA + residualsA;
        uint256 toCallerB = rewardB + residualsB;

        _designatedTokenAPool[id] -= toCallerA;
        _designatedTokenBPool[id] -= toCallerB;
        _isDefaulted[id] = true;

        _tokenA.transfer(msg.sender, toCallerA);
        _tokenB.transfer(msg.sender, toCallerB);

        emit Defaulted(id, totalDebt, paidDebtB, paidDebtA);
    }

    function markAsCompleted(uint256 id) external {
        require(!isCompleted(id) && isCompletedInTheory(id), "Bond is already completed");
        uint256 totalDebt = principalWithInterest(id);
        uint256 reward = totalDebt/1000;
        uint256 paidDebt = totalDebt - reward;
        _tokenBAmountPerBondAfterComplete[id] = paidDebt / _purchasedQuantity[id];
        uint256 residuals = paidDebt - _tokenBAmountPerBondAfterComplete[id] * _purchasedQuantity[id];
        uint256 toCaller = reward + residuals;
        _designatedTokenBPool[id] -= toCaller;

        _isCompleted[id] = true;
        _tokenB.transfer(msg.sender, toCaller);


        emit Completed(id, totalDebt, paidDebt);
    }
     
    function remainingQuantity(uint256 id) public view returns (uint256) {
        return _bondMetadata[id].issuedQuantity - _purchasedQuantity[id];
    }

    function timeElapsed(uint256 id) public view returns(uint256) {
        return block.timestamp - _bondMetadata[id].initBlock;
    }

    function timeRemainingToMaturity(uint256 id) public view returns(uint256) {
        return _bondMetadata[id].durationInDays - timeElapsed(id);
    }

    function timeRemainingToEndOfActive(uint256 id) public view returns(uint256) {
        return _bondMetadata[id].activeDurationInDays - timeElapsed(id);
    }

    function couponRate(uint256 id) public view returns(uint256) {
        return _bondMetadata[id].couponRate;
    }

    function principal(uint256 id) public view returns(uint256) {
        return _bondMetadata[id].tokenBAmountPerBond * _purchasedQuantity[id];
    }

    function principalWithInterest(uint256 id) public virtual view returns(uint256) {
        return principal(id) + principal(id) * _bondMetadata[id].couponRate / 1e18;
    }

    function poolAAmount(uint256 id) public view returns(uint256) {
        return _designatedTokenAPool[id];
    }
    function poolBAmount(uint256 id) public view returns(uint256) {
        return _designatedTokenBPool[id];
    }

    function tvlA() public view returns(uint256) {
        return _tokenA.balanceOf(address(this));
    }

    function tvlB() public view returns(uint256) {
        return _tokenB.balanceOf(address(this));
    }

    function isFullyRedeemed(uint256 id) public view returns(bool) {
        return _redeemedQuantity[id] == _purchasedQuantity[id];
    }

    function isActive(uint256 id) public view returns(bool) {
        return block.timestamp <= _bondMetadata[id].endOfActiveBlock;
    }

    function isFulfilled(uint256 id) public view returns(bool) {
        return _purchasedQuantity[id] >= _bondMetadata[id].minPurchasedQuantity;
    }

    function isCanceled(uint256 id) public view returns(bool) {
        return !isActive(id) && !isFulfilled(id);
    }

    function hasReachedMaturity(uint256 id) public view returns(bool) {
        return block.timestamp > _bondMetadata[id].maturityBlock;
    }

    function isCompleted(uint256 id) public view returns(bool) {
        return _isCompleted[id];
    }

    function isCompletedInTheory(uint256 id) public view virtual returns(bool) {
        return (hasReachedMaturity(id) && _designatedTokenBPool[id] >= principalWithInterest(id));
    }

    function isDefaultedInTheory(uint256 id) public view virtual returns(bool) {
        return (hasReachedMaturity(id) && _designatedTokenBPool[id] < principalWithInterest(id));
    }

    function isDefaulted(uint256 id) public view virtual returns(bool) {
        return _isDefaulted[id];
    }

    function bondmetaData(uint256 id) public view virtual returns(string memory, uint256, uint256, uint256, uint256, uint256, uint256,uint256,uint256,uint256,uint256) {
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
}



