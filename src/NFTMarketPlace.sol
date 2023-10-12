// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../lib/openzeppelin-contracts/contracts/token/ERC721/IERC721.sol";
import "../lib/openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";
import "../lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import {SignUtils} from "./libraries/SignUtils.sol";

contract NFTMarketplace is ReentrancyGuard, Ownable {


    error OnlySellerError();
    error InvalidOrderIdError();
    error NFTContractNotAcceptedError();
    error InvalidTradeStateError();
    error NFTAlreadyListedError();
    error IncorrectListingFeeError();
    error DeadlineInPastError();
    error PriceZeroError();
    error InvalidTokenAddressError();
    error TokenAddressHasNoCodeError();
    error ContractNotApprovedError();
    error InvalidSignatureError();


    struct Order {
        address seller;
        uint256 tokenId;
        uint256 price;
        uint256 deadline;
        bool isActive;
        address nftContractAddress;
        bytes signature;
    }

    IERC721 public nftContract;
    uint256 public listingFee;
    uint256 public orderCounter;

    mapping(uint256 => Order) public tokenIdToOrder;

    // Mapping of order ID to trade state (0: Initial, 1: Buyer Confirmed, 2: Seller Confirmed)
    mapping(uint256 => uint256) public tradeStates;

    constructor(uint256 _listingFee) {
        listingFee = _listingFee;
    }

    event OrderCreated(address indexed seller, uint256 indexed tokenId, uint256 price, uint256 deadline);
    event OrderCancelled(uint256 indexed tokenId);
    event OrderExecuted(uint256 indexed orderId, address indexed buyer);
    event TradeConfirmed(uint256 indexed orderId, address indexed confirmer);

    modifier onlySeller(uint256 _tokenId) {
        require(msg.sender == tokenIdToOrder[_tokenId].seller, "Only seller can perform this action");
        _;
    }

    function setListingFee(uint256 _newFee) external onlyOwner {
        listingFee = _newFee;
    }

    function createOrder(uint256 _tokenId, uint256 _price, uint256 _deadline, bytes memory _signature, address nftContractAddress_) external payable nonReentrant {
        if (msg.sender == owner()) {
            revert OnlySellerError();
        }
        if (tradeStates[_tokenId] != 0) {
            revert InvalidTradeStateError();
        }
        if (tokenIdToOrder[_tokenId].isActive) {
            revert NFTAlreadyListedError();
        }
        if (msg.value != listingFee) {
            revert IncorrectListingFeeError();
        }
        if (_deadline < block.timestamp) {
            revert DeadlineInPastError();
        }
        if (_price == 0) {
            revert PriceZeroError();
        }

        
        nftContract = IERC721(nftContractAddress_);

        if (!nftContract.isApprovedForAll(msg.sender, address(this))) {
            revert ContractNotApprovedError();
        }


        tokenIdToOrder[_tokenId] = Order({
            seller: msg.sender,
            tokenId: _tokenId,
            price: _price,
            deadline: _deadline,
            isActive: true,
            signature: _signature,
            nftContractAddress: nftContractAddress_
        });

        tradeStates[orderCounter] = 1;
        orderCounter += 1;



        emit OrderCreated(msg.sender, _tokenId, _price, _deadline);
    }

    function _confirmTrade(uint256 _orderId) internal returns(bool) {
        if (tradeStates[_orderId] != 1) {
            revert InvalidTradeStateError();
        }

        /** Mark the trade as Seller Confirmed **/
        tradeStates[_orderId] = 2;

        emit TradeConfirmed(_orderId, msg.sender);

        return true;
    }

    function executeOrder(uint256 _orderId) external payable nonReentrant {
        if  (_orderId > orderCounter) {
            revert InvalidOrderIdError();
        }
        _confirmTrade(_orderId);
        if (msg.value != tokenIdToOrder[_orderId].price) {
            revert PriceZeroError();
        }
        if (!tokenIdToOrder[_orderId].isActive) {
            revert NFTAlreadyListedError();
        }
        Order storage order = tokenIdToOrder[_orderId];


        if (tradeStates[_orderId] == 2) {
            bytes32 messageHash = SignUtils.constructMessageHashV2(order.tokenId, order.price, order.seller, order.deadline);
            require(SignUtils.isValid(messageHash, order.signature, msg.sender), 'invalid signature');
            nftContract = IERC721(msg.sender);
            /** Transfer the NFT to the buyer **/
            nftContract.safeTransferFrom(order.seller, msg.sender, order.tokenId);

            /** Transfer the payment to the contract **/
            payable(address(this)).transfer(msg.value);  

            order.isActive = false;
        }
    }

    function getOrder(uint256 tokenId) external view returns (address seller, uint256 price, uint256 deadline, bool isActive, bytes memory signature) {
        Order storage order = tokenIdToOrder[tokenId];
        return (order.seller, order.price, order.deadline, order.isActive, order.signature);
    }

    function updateTradeState(uint256 _orderId, uint256 _tradeState) external onlyOwner {
        tradeStates[_orderId] = _tradeState;
    }

    function getTradeState(uint256 _orderId) external view returns (uint256) {
        return tradeStates[_orderId];
    }

    function toggleActive(uint256 _tokenId, bool status) external onlyOwner {
        Order storage order = tokenIdToOrder[_tokenId];
        order.isActive = status;
    }

    function updateDeadline(uint256 _tokenId, uint256 _deadline) external onlyOwner {
        Order storage order = tokenIdToOrder[_tokenId];
        order.deadline = _deadline;
    }
}
