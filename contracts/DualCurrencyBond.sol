// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "./interfaces/IBondDB.sol";
import "./interfaces/IDualCurrencyBond.sol";

contract DualCurrencyBond is ERC1155 {
    using Counters for Counters.Counter;
    mapping(uint256 => IDualCurrencyBond.BondMetadata) _bondMetadata;
    mapping(uint256 => IDualCurrencyBond.BondData) _bondData;

    address immutable _owner;
    Counters.Counter private _id;
    IBondDB immutable _bondDB;

    modifier onlyFactory() {
        require(
            _bondDB.isFactory(msg.sender),
            "Caller is not a Factory Contract"
        );
        _;
    }

    constructor(address bondDB, string memory uri) ERC1155(uri) {
        _owner = msg.sender;
        _bondDB = IBondDB(bondDB);
        _id.increment();
    }

    function mint(
        address to,
        uint256 bondQuantity,
        IDualCurrencyBond.BondData memory data,
        IDualCurrencyBond.BondMetadata memory metadata
    ) public onlyFactory returns (uint256 id) {
        id = _id.current();
        _id.increment();
        _bondMetadata[id] = metadata;
        _bondData[id] = data;

        _mint(to, id, bondQuantity, "");
    }

    function burn(
        address account,
        uint256 id,
        uint256 quantity
    ) public virtual {
        require(
            account == _msgSender() || isApprovedForAll(account, _msgSender()),
            "ERC1155: caller is not token owner or approved"
        );

        _burn(account, id, quantity);
    }

    function bondData(
        uint256 id
    )
        public
        view
        returns (
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
        IDualCurrencyBond.BondData memory bd = _bondData[id];
        return (
            bd.tokenAAmountPerBond,
            bd.tokenBAmountPerBond,
            bd.initBlock,
            bd.maturityBlock,
            bd.endOfActiveBlock,
            bd.activeDurationInDays,
            bd.durationInDays,
            bd.issuedQuantity,
            bd.minPurchasedQuantity,
            bd.couponRate
        );
    }

    function bondMetadata(
        uint256 id
    ) public view returns (string memory, address, address, address) {
        IDualCurrencyBond.BondMetadata memory bm = _bondMetadata[id];
        return (bm.ticker, bm.currencyA, bm.currencyB, bm.issuer);
    }

    function bondDataAsStruct(
        uint256 id
    ) public view returns (IDualCurrencyBond.BondData memory) {
        return _bondData[id];
    }

    function bondMetadataAsStruct(
        uint256 id
    ) public view returns (IDualCurrencyBond.BondMetadata memory) {
        return _bondMetadata[id];
    }

    function numBondsIssued() public view returns (uint256) {
        return _id.current() - 1;
    }

    function timeElapsed(uint256 id) public view returns (uint256) {
        return block.timestamp - _bondData[id].initBlock;
    }

    function timeRemainingToMaturity(uint256 id) public view returns (uint256) {
        return _bondData[id].maturityBlock - block.timestamp;
    }

    function timeRemainingToEndOfActive(
        uint256 id
    ) public view returns (uint256) {
        return _bondData[id].endOfActiveBlock - block.timestamp;
    }

    function hasReachedMaturity(uint256 id) public view returns (bool) {
        return block.timestamp > _bondData[id].maturityBlock;
    }

    function isActive(uint256 id) public view returns (bool) {
        return block.timestamp <= _bondData[id].endOfActiveBlock;
    }
}
