// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "solmate/tokens/ERC721.sol";
import {SignUtils} from "./libraries/SignUtils.sol";

contract Marketplace {
    struct Listing {
        address token;
        uint256 tokenId;
        uint256 price;
        bytes sig;
        // Slot 4
        uint88 deadline;
        address lister;
        bool active;
        uint256 totalShares;
    }

    struct Fraction {
        address owner;
        uint256 amount;
    }

    address public admin;
    uint256 public listingId;

    mapping(uint256 => Listing) public listings; // Mapping of listingId to Listing
    mapping(uint256 => Fraction[]) public fractions; // Mapping of listingId to fractions
    mapping(address => Fraction[]) public userFractions; // Mapping of user to fractions

    uint256 public platformBalance;

    /* ERRORS */
    error NotOwner();
    error NotApproved();
    // error AddressZero();
    // error NoCode();
    error MinPriceTooLow();
    error DeadlineTooSoon();
    error MinDurationNotMet();
    error InvalidSignature();
    error ListingNotExistent();
    error ListingNotActive();
    error PriceNotMet(int256 difference);
    error ListingExpired();
    error PriceMismatch(uint256 originalPrice);

    /* EVENTS */
    event ListingCreated(uint256 indexed listingId, Listing);
    event ListingExecuted(uint256 indexed listingId, Listing);
    event ListingEdited(uint256 indexed listingId, Listing);
    event FractionPurchased(uint256 indexed listingId, address buyer, uint256 amount);
    event FractionCreated(uint256 indexed listingId, address owner, uint256 amount);

    constructor() {
        admin = msg.sender;
    }

    function createListing(Listing calldata l) public returns (uint256 lId) {
        if (ERC721(l.token).ownerOf(l.tokenId) != msg.sender)
            revert NotOwner();
        if (!ERC721(l.token).isApprovedForAll(msg.sender, address(this)))
            revert NotApproved();

        if (l.price < 0.01 ether) revert MinPriceTooLow();
        if (l.deadline < block.timestamp) revert DeadlineTooSoon();
        if (l.deadline - block.timestamp < 60 minutes)
            revert MinDurationNotMet();

        // Assert signature
        if (
            !SignUtils.isValid(
                SignUtils.constructMessageHash(
                    l.token,
                    l.tokenId,
                    l.price,
                    l.deadline,
                    l.lister
                ),
                l.sig,
                msg.sender
            )
        ) revert InvalidSignature();

        // append to Storage
        Listing storage li = listings[listingId];
        li.token = l.token;
        li.tokenId = l.tokenId;
        li.price = l.price;
        li.sig = l.sig;
        li.deadline = uint88(l.deadline);
        li.lister = msg.sender;
        li.active = true;
        li.totalShares = 0;

        // Emit event
        emit ListingCreated(listingId, l);
        lId = listingId;
        listingId++;
        return lId;
    }

    function executeListing(uint256 _listingId) public payable {
        if (_listingId >= listingId) revert ListingNotExistent();
        Listing storage listing = listings[_listingId];
        if (listing.deadline < block.timestamp) revert ListingExpired();
        if (!listing.active) revert ListingNotActive();
        if (listing.price != msg.value)
            revert PriceNotMet(int256(listing.price) - int256(msg.value));

        // Update state
        listing.active = false;

        // transfer
        ERC721(listing.token).transferFrom(
            listing.lister,
            msg.sender,
            listing.tokenId
        );

        // transfer eth
        payable(listing.lister).transfer(listing.price);

        // Update storage
        emit ListingExecuted(_listingId, listing);
    }

    function editListing(
        uint256 _listingId,
        uint256 _newPrice,
        bool _active
    ) public {
        if (_listingId >= listingId) revert ListingNotExistent();
        Listing storage listing = listings[_listingId];
        if (listing.lister != msg.sender) revert NotOwner();
        listing.price = _newPrice;
        listing.active = _active;
        emit ListingEdited(_listingId, listing);
    }

    function createFractions(uint256 _listingId, uint256 _numberOfFractionsToCreate) public {
        if (_listingId >= listingId) revert ListingNotExistent();
        Listing storage listing = listings[_listingId];
        if (!listing.active) revert ListingNotActive();

        // calculate token price for each fraction
        uint256 fractionPrice = listing.price / _numberOfFractionsToCreate;

        // create fractions
        for (uint i = 0; i < _numberOfFractionsToCreate; i++) {
            fractions[_listingId].push(Fraction({
                owner: msg.sender,
                amount: fractionPrice
            }));
        }

        // Update totalShares of the listing
        listing.totalShares += _numberOfFractionsToCreate;

        // Emit the fraction created event
        emit FractionCreated(_listingId, msg.sender, _numberOfFractionsToCreate);
    }

    function getFractionAmount(uint256 _listingId) public view returns (uint256) {
        if (_listingId >= listingId) revert ListingNotExistent();
        Listing storage listing = listings[_listingId];
        if (!listing.active) revert ListingNotActive();

        Fraction[] storage fractionsList = fractions[_listingId];

        // Iterate through the user's fractions and find the ones to transfer
        for (uint i = 0; i < fractionsList.length; i++) {
            if (fractionsList[i].owner == msg.sender) {
                return fractionsList[i].amount;
            }
        }
        return 0;
    }

    function exchangeEtherForFraction(uint256 _listingId) public payable {
        if (_listingId >= listingId) revert ListingNotExistent();
        Listing storage listing = listings[_listingId];
        if (!listing.active) revert ListingNotActive();

        // check the price of the fraction
        uint256 fractionPrice = getFractionAmount(_listingId);

        // check if the user sent enough ether
        if (msg.value < fractionPrice) revert PriceNotMet(int256(fractionPrice) - int256(msg.value));

        // deduct platform fees  0.1 % of all amount accumulated from sales.
        uint256 platformFee = msg.value / 1000;
        platformBalance += platformFee;

        // transfer eth to the seller
        payable(listing.lister).transfer(msg.value - platformFee);

        // updated the userFraction
        Fraction[] storage fractionsList = fractions[_listingId];
        for (uint i = 0; i < fractionsList.length; i++) {
            if (fractionsList[i].owner == msg.sender) {
                fractionsList[i].amount = 0;
                fractionsList[i].owner = address(0);
                break;
            }
        }

        // add fraction to userFraction map
        userFractions[msg.sender].push(Fraction({
            owner: msg.sender,
            amount: fractionPrice
        }));

        // Update totalShares of the listing
        listing.totalShares -= 1;
    }

    function transferFractions(uint256 _listingId, address _recipient, uint256 _amount) public {
        if (_listingId >= listingId) revert ListingNotExistent();
        Listing storage listing = listings[_listingId];
        if (!listing.active) revert ListingNotActive();

        Fraction[] storage fractionsList = fractions[_listingId];

        // Iterate through the user's fractions and find the ones to transfer
        for (uint i = 0; i < fractionsList.length; i++) {
            if (fractionsList[i].owner == msg.sender && fractionsList[i].amount >= _amount) {
                fractionsList[i].amount -= _amount;
                fractionsList.push(Fraction({
                    owner: _recipient,
                    amount: _amount
                }));
                return;
            }
        }
        revert("Insufficient balance or fraction not found");
    }

    // add getter for listing
    function getListing(
        uint256 _listingId
    ) public view returns (Listing memory) {
        // if (_listingId >= listingId)
        return listings[_listingId];
    }

    function withdrawPlatformFees() public {
        require(msg.sender == admin, "Only admin can withdraw platform fees");
        uint256 feeToWithdraw = platformBalance;
        platformBalance = 0;
        payable(admin).transfer(feeToWithdraw);
    }
}
