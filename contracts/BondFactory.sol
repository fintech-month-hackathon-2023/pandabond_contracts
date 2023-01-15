// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";


contract BondFactory is ERC1155 {
    address immutable _owner;
    IERC20 immutable _baseToken;
    uint256 _id = 0;

    struct BondMetadata {
        string ticker;
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

    mapping(uint256 => BondMetadata) _bondMetadata;
    mapping(uint256 => uint256) _purchasedQuantity;
    mapping(uint256 => uint256) _redeemedQuantity;
    mapping(uint256 => uint256) _designatedTokenPool;
    mapping(uint256 => uint256) _tokenAmountPerBondAfterDefault;
    mapping(uint256 => uint256) _tokenAmountPerBondAfterComplete;

    mapping(uint256 => bool) _isDefaulted;
    mapping(uint256 => bool) _isCompleted;

    modifier onlyOwner() {
        require(msg.sender == _owner, "Caller is not the owner");
        _;
    }

    event Issued(uint256 indexed id, uint256 bondQuantity, uint256 tokenAmountPerBond, uint256 couponRate);
    event Defaulted(uint256 indexed id, uint256 totalDebt, uint256 paidDebt);
    event Completed(uint256 indexed id, uint256 totalDebt, uint256 paidDebt);

    constructor (string memory uri, address token) ERC1155(uri) {
        _owner = msg.sender;
        _baseToken = IERC20(token);
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
        ) external virtual onlyOwner returns(uint256 id) {
        require(activeDurationInDays < durationDays, "Active duration should be shorter than duration");
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
        emit Issued(id, bondQuantity, tokenAmountPerBond, rate);

    }

    function purchase(uint256 id, uint256 bondQuantity) external {
        require(isActive(id), "Bond is inactive");
        require(remainingQuantity(id)>= bondQuantity, "Insufficient bond quantity remaining");

        BondMetadata memory metadata = _bondMetadata[id];
        uint256 tokenAmount = bondQuantity * metadata.tokenAmountPerBond;

        _baseToken.transferFrom(msg.sender,address(this), tokenAmount);

        _purchasedQuantity[id] += bondQuantity;
        _designatedTokenPool[id] += tokenAmount;

    }

    function withdraw(uint256 id, uint256 tokenAmount) external virtual onlyOwner {
        require(!isActive(id), "Withdraw not allowed when active");
        require(!isCanceled(id), "Withdraw not allowed when active");
        require(!isCompleted(id), "Withdraw not allowed after completion");
        require(!(isDefaulted(id) || isDefaultedInTheory(id)), "Withdraw not allowed when defaulted");

        require(tokenAmount <= _designatedTokenPool[id], "Withdrawal token amount exceeds token amount in contract");

        _designatedTokenPool[id] -= tokenAmount;
        _baseToken.transfer(msg.sender, tokenAmount);
    }

    function withdrawExcess(uint256 id) external onlyOwner {
        require(isCompleted(id) && isFullyRedeemed(id), "Cannot withdraw excess");
        require(_designatedTokenPool[id] > 0, "Cannot withdraw from empty pool");

        _designatedTokenPool[id] = 0;
        _baseToken.transfer(msg.sender, _designatedTokenPool[id]);

    }

    

    function redeem(uint256 id, uint256 bondQuantity) external {
        require(isCompleted(id), "Bond is not completed");
        require(balanceOf(msg.sender, id)>=bondQuantity, "Insufficient bond quantity");
        _burn(msg.sender, id, bondQuantity);
        _redeemedQuantity[id]+=bondQuantity;
        uint256 tokenAmount = bondQuantity * _tokenAmountPerBondAfterComplete[id];

        _baseToken.transfer(msg.sender, tokenAmount);
        _designatedTokenPool[id] -= tokenAmount;
    }

    function redeemCanceled(uint256 id, uint256 bondQuantity) external {
        require(isCanceled(id), "Bond is not canceled");
        require(balanceOf(msg.sender, id)>=bondQuantity, "Insufficient bond quantity");
        _burn(msg.sender, id, bondQuantity);
        _redeemedQuantity[id]+=bondQuantity;
        uint256 tokenAmount = bondQuantity * _bondMetadata[id].tokenAmountPerBond;

        _baseToken.transfer(msg.sender, tokenAmount);
        _designatedTokenPool[id] -= tokenAmount;
    }

    function redeemDefaulted(uint256 id, uint256 bondQuantity) external {
        require(isDefaulted(id), "Bond is not defaulted");
        require(balanceOf(msg.sender, id)>=bondQuantity, "Insufficient bond quantity");
        _burn(msg.sender, id, bondQuantity);
        _redeemedQuantity[id]+=bondQuantity;
        uint256 tokenAmount = bondQuantity * _tokenAmountPerBondAfterDefault[id];

        _baseToken.transfer(msg.sender, tokenAmount);
        _designatedTokenPool[id] -= tokenAmount;
    }

    function deposit(uint256 id, uint256 tokenAmount) external onlyOwner{
        require(!(isDefaulted(id) || isDefaultedInTheory(id)),"bond is defaulted");
        require(!isCompleted(id), "bond is completed");

        _designatedTokenPool[id] += tokenAmount;
        _baseToken.transferFrom(msg.sender, address(this), tokenAmount);

    }

    function markAsDefaulted(uint256 id) external {
        require(!isDefaulted(id) && isDefaultedInTheory(id), "Bond is not defaulted");
        uint256 totalDebt = principalWithInterest(id);
        uint256 reward = _designatedTokenPool[id]/1000;
        uint256 paidDebt = _designatedTokenPool[id] - reward;

        _tokenAmountPerBondAfterDefault[id] = paidDebt / _purchasedQuantity[id];
        uint256 residuals = paidDebt - _tokenAmountPerBondAfterDefault[id] * _purchasedQuantity[id]; //if residuals exist
        uint256 toCaller = reward + residuals;
        _designatedTokenPool[id] -= toCaller;

        _isDefaulted[id] = true;
        _baseToken.transfer(msg.sender, toCaller);

        emit Defaulted(id, totalDebt, paidDebt);
    }

    function markAsCompleted(uint256 id) external {
        require(!isCompleted(id) && isCompletedInTheory(id), "Bond is already completed");
        uint256 totalDebt = principalWithInterest(id);
        uint256 reward = totalDebt/1000;
        uint256 paidDebt = totalDebt - reward;
        _tokenAmountPerBondAfterComplete[id] = paidDebt / _purchasedQuantity[id];
        uint256 residuals = paidDebt - _tokenAmountPerBondAfterComplete[id] * _purchasedQuantity[id];
        uint256 toCaller = reward + residuals;
        _designatedTokenPool[id] -= toCaller;
        _isCompleted[id] = true;
        _baseToken.transfer(msg.sender, toCaller);


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
        return _bondMetadata[id].tokenAmountPerBond * _purchasedQuantity[id];
    }

    function principalWithInterest(uint256 id) public virtual view returns(uint256) {
        return principal(id) + principal(id) * _bondMetadata[id].couponRate / 1e18;
    }

    function poolAmount(uint256 id) public view returns(uint256) {
        return _designatedTokenPool[id];
    }

    function tvl() public view returns(uint256) {
        return _baseToken.balanceOf(address(this));
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
        return (hasReachedMaturity(id) && _designatedTokenPool[id] >= principalWithInterest(id));
    }

    function isDefaultedInTheory(uint256 id) public view virtual returns(bool) {
        return (hasReachedMaturity(id) && _designatedTokenPool[id] < principalWithInterest(id));
    }

    function isDefaulted(uint256 id) public view virtual returns(bool) {
        return _isDefaulted[id];
    }

    function bondmetaData(uint256 id) public view virtual returns(string memory, uint256, uint256, uint256, uint256, uint256,uint256,uint256,uint256,uint256) {
        BondMetadata memory bm = _bondMetadata[id];
        return (
            bm.ticker,
            bm.tokenAmountPerBond,
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



