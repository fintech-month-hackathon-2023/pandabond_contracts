// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract BondFactory is ERC1155, IERC1155Receiver {
    address immutable _owner;
    IERC20 immutable _baseToken;
    uint256 _id = 0;

    uint256 _fundsRaised;

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
        string memory uri,
        address token,
        address deployer
    ) ERC1155(uri) {
        _owner = deployer;
        _baseToken = IERC20(token);
    }

    function issue(
        uint256 bondQuantity,
        uint256 minPurchasedQuantity,
        uint256 tokenAmountPerBond,
        string memory ticker,
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
        emit Issued(
            id,
            bondQuantity,
            tokenAmountPerBond,
            rate,
            block.timestamp + durationDays * 1 days
        );
    }

    function purchase(uint256 id, uint256 bondQuantity) external {
        require(isActive(id), "IB");
        require(remainingQuantity(id) >= bondQuantity, "IQ");

        BondMetadata memory metadata = _bondMetadata[id];
        uint256 tokenAmount = bondQuantity * metadata.tokenAmountPerBond;

        _purchasedQuantity[id] += bondQuantity;
        _designatedTokenPool[id] += tokenAmount;
        _fundsRaised += tokenAmount;
        safeTransferFrom(address(this), msg.sender, id, bondQuantity, "");
        _baseToken.transferFrom(msg.sender, address(this), tokenAmount);
    }

    function withdraw(
        uint256 id,
        uint256 tokenAmount
    ) external virtual onlyOwner {
        require(
            !isActive(id) &&
                !isCanceled(id) &&
                !isCompleted(id) &&
                !(isDefaulted(id) || isDefaultedInTheory(id)),
            "WNA"
        );

        require(tokenAmount <= _designatedTokenPool[id], "WAE");

        _designatedTokenPool[id] -= tokenAmount;
        _baseToken.transfer(msg.sender, tokenAmount);
    }

    function withdrawExcess(uint256 id) external onlyOwner {
        require(isCompleted(id) && isFullyRedeemed(id), "WNA");
        require(_designatedTokenPool[id] > 0, "WFE");

        _designatedTokenPool[id] = 0;
        _baseToken.transfer(msg.sender, _designatedTokenPool[id]);
    }

    function redeem(uint256 id, uint256 bondQuantity) external {
        require(balanceOf(msg.sender, id) >= bondQuantity, "IQ");

        require(isCompleted(id) || isCanceled(id) || isDefaulted(id), "RNA");

        uint256 tokenAmountPerBond;
        uint256 state;

        if (isCompleted(id)) {
            tokenAmountPerBond = _tokenAmountPerBondAfterComplete[id];
            state = 0;
        } else if (isCanceled(id)) {
            tokenAmountPerBond = _bondMetadata[id].tokenAmountPerBond;
            state = 1;
        } else if (isDefaulted(id)) {
            tokenAmountPerBond = _tokenAmountPerBondAfterDefault[id];
            state = 2;
        } else {
            revert();
        }

        _burn(msg.sender, id, bondQuantity);
        _redeemedQuantity[id] += bondQuantity;
        uint256 tokenAmount = bondQuantity * tokenAmountPerBond;
        _designatedTokenPool[id] -= tokenAmount;
        _baseToken.transfer(msg.sender, tokenAmount);

        emit Redeemed(id, msg.sender, bondQuantity, state);
    }

    function deposit(uint256 id, uint256 tokenAmount) external onlyOwner {
        require(
            !(isDefaulted(id) || isDefaultedInTheory(id)) && !isCompleted(id),
            "DNA"
        );

        _designatedTokenPool[id] += tokenAmount;
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
        _baseToken.transfer(msg.sender, callerReward);

        emit Completed(id, totalDebt, paidDebt);
    }

    function onERC1155Received(
        address,
        address,
        uint256,
        uint256,
        bytes memory
    ) public virtual returns (bytes4) {
        return this.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(
        address,
        address,
        uint256[] memory,
        uint256[] memory,
        bytes memory
    ) public virtual returns (bytes4) {
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
        return _bondMetadata[id].tokenAmountPerBond * _purchasedQuantity[id];
    }

    function principalWithInterest(
        uint256 id
    ) public view virtual returns (uint256) {
        return
            principal(id) +
            (principal(id) * _bondMetadata[id].couponRate) /
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
            _designatedTokenPool[id] >= principalWithInterest(id));
    }

    function isDefaultedInTheory(
        uint256 id
    ) public view virtual returns (bool) {
        return (hasReachedMaturity(id) &&
            _designatedTokenPool[id] < principalWithInterest(id));
    }

    function isDefaulted(uint256 id) public view virtual returns (bool) {
        return _isDefaulted[id];
    }

    function bondMetadata(
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
            uint256
        )
    {
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

    function baseToken() public view returns (address) {
        return address(_baseToken);
    }

    function owner() public view returns (address) {
        return _owner;
    }

    function fundsRaised() public view returns (uint256) {
        return _fundsRaised;
    }

    function designatedTokenPool(uint256 id) public view returns (uint256) {
        return _designatedTokenPool[id];
    }

    function numBondsIssued() public view returns (uint256) {
        return _id;
    }
}
