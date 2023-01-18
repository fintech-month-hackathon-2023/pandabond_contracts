// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "./interfaces/IBondDB.sol";
import "./interfaces/IBond.sol";

contract Bond is ERC1155 {
    using Counters for Counters.Counter;
    mapping(uint256 => IBond.BondMetadata) _bondMetadata;

    address immutable _owner;
    Counters.Counter private _id;
    IBondDB immutable _bondDB;

    modifier onlyFactory(){
        require(_bondDB.isFactory(msg.sender), "Caller is not a Factory Contract");
        _;
    }

    constructor(address bondDB, string memory uri) ERC1155(uri) {
        _owner = msg.sender;
        _bondDB = IBondDB(bondDB);
        _id.increment();
    }


    function mint(address to, uint256 bondQuantity, IBond.BondMetadata memory metadata) public onlyFactory returns(uint256 id) {
        id = _id.current();
        _id.increment();
        _bondMetadata[id] = metadata;

        _mint(to, id, bondQuantity, '');

    }

    function burn(address account, uint256 id, uint256 quantity) public virtual {
        require(
            account == _msgSender() || isApprovedForAll(account, _msgSender()),
            "ERC1155: caller is not token owner or approved"
        );

        _burn(account, id, quantity);
    }

    function bondMetadata(uint256 id) public view returns (string memory,
        address,
        address,
        uint256,
        uint256,
        uint256,
        uint256,
        uint256,
        uint256, // x days
        uint256,
        uint256,
        uint256){

            IBond.BondMetadata memory bm = _bondMetadata[id];
            return (
                bm.ticker,
        bm.currency,
        bm.issuer,
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

    function bondMetadataAsStruct(uint256 id) public view returns (IBond.BondMetadata memory){
            return _bondMetadata[id];
    }

    function numBondsIssued() public view returns (uint256) {
        return _id.current() - 1;
    }
}
