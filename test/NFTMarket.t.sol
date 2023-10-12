// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test, console2} from "../lib/forge-std/src/Test.sol";
import {NFTMarketplace} from "../src/NFTMarketPlace.sol";

import "../lib/openzeppelin-contracts/contracts/token/ERC721/IERC721.sol";
import "../src/ERC721Mock.sol";
import "./Helpers.sol";


contract NFTMarketplaceTest is Test {
    // uint256 user
    function mkaddr(
        string memory name
    ) public returns (address addr, uint256 privateKey) {
        privateKey = uint256(keccak256(abi.encodePacked(name)));
        // address addr = address(uint160(uint256(keccak256(abi.encodePacked(name)))))
        addr = vm.addr(privateKey);
        vm.label(addr, name);
    }

    function constructSig(
        address _token,
        uint256 _tokenId,
        uint256 _price,
        uint256 _deadline,
        uint256 privKey
    ) public pure returns (bytes memory sig) {
        bytes32 mHash = keccak256(
            abi.encodePacked(_token, _tokenId, _price, _deadline)
        );

        mHash = keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n32", mHash)
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privKey, mHash);
        sig = getSig(v, r, s);
    }

    function getSig(
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public pure returns (bytes memory sig) {
        sig = bytes.concat(r, s, bytes1(v));
    }

    function switchSigner(address _newSigner) public {
        vm.startPrank(_newSigner);
        vm.deal(_newSigner, 4 ether);
    }
    struct Order {
        address seller;
        uint256 tokenId;
        uint256 price;
        uint256 deadline;
        bool isActive;
        bytes signature;
        address nftContractAddress;
    }

    NFTMarketplace public nftMarketPlaceContract;
    OurNFT nft;

    address userA;
    address userB;
    address userC;

    uint256 privKeyA;
    uint256 privKeyB;

    uint256 price_;
    // address nftContractAddress = 0x168Ca561E63C868b0F6cC10a711d0b4455864f17;
    uint256 tokenId_;
    uint256 _tradeState;

    NFTMarketplace.Order order;

    function setUp() public {
        (userA, privKeyA) = mkaddr("USERA");
        (userB, privKeyB) = mkaddr("USERB");

        switchSigner(userA);

        nftMarketPlaceContract = new NFTMarketplace( price_);

        nft = new OurNFT();

        tokenId_ = 1;
        price_ = 2 ether;

        order = NFTMarketplace.Order({
            seller: msg.sender,
            tokenId: tokenId_,
            price: price_,
            deadline: 0,
            isActive: false,
            signature: bytes(""),
            nftContractAddress: address(nft)
        });

        // mint NFT
        nft.mint(userA, 1);
    }

    function testUpdateTradeState() public {
        switchSigner(userA);
        nftMarketPlaceContract.updateTradeState(0, 1);
        assertEq(nftMarketPlaceContract.tradeStates(0), 1);
    }

    function testOwnerCannotCreateOrder() public {
        order.seller = userA;
        switchSigner(userA);

        vm.expectRevert(NFTMarketplace.OnlySellerError.selector);
        nftMarketPlaceContract.createOrder(order.tokenId, order.price, order.deadline, order.signature, order.nftContractAddress);
    }

    function testValidTradeStateBeforeCreating() public {
        switchSigner(userA);

        nftMarketPlaceContract.updateTradeState(order.tokenId, 1);

        switchSigner(userB);
        vm.expectRevert(NFTMarketplace.InvalidTradeStateError.selector);
        nftMarketPlaceContract.createOrder(order.tokenId, order.price, order.deadline, order.signature, order.nftContractAddress);
    }

    function testActiveOrderBeforeCreating() public {
        switchSigner(userA);

        nftMarketPlaceContract.toggleActive(order.tokenId, true);

        switchSigner(userB);
        vm.expectRevert(NFTMarketplace.NFTAlreadyListedError.selector);
        nftMarketPlaceContract.createOrder(order.tokenId, order.price, order.deadline, order.signature, order.nftContractAddress);
    }

    function testListingFeeBeforeCreating() public {
        switchSigner(userB);
        vm.expectRevert(NFTMarketplace.IncorrectListingFeeError.selector);
        nftMarketPlaceContract.createOrder{value: 1}(order.tokenId, order.price, order.deadline, order.signature, order.nftContractAddress);
    }

    function testDeadlineBeforeCreating() public {
        switchSigner(userB);
        order.deadline = block.timestamp - 1;
        vm.expectRevert(NFTMarketplace.DeadlineInPastError.selector);
        nftMarketPlaceContract.createOrder(order.tokenId, order.price, order.deadline, order.signature, order.nftContractAddress);
    }

    function testPriceNotZeroErrorBeforeCreating() public {
        switchSigner(userB);
        order.price = 0;
        vm.expectRevert(NFTMarketplace.PriceZeroError.selector);
        nftMarketPlaceContract.createOrder(order.tokenId, order.price, order.deadline + 500, order.signature, order.nftContractAddress);
    }

    function testApprovedBeforeCreating() public {
        switchSigner(userB);
        vm.expectRevert(NFTMarketplace.ContractNotApprovedError.selector);
        nftMarketPlaceContract.createOrder(order.tokenId, order.price, order.deadline + 500, order.signature, order.nftContractAddress);
    }

    function testCreateOrder() public {
        switchSigner(userB);
        nft.setApprovalForAll(address(nftMarketPlaceContract), true);
        nftMarketPlaceContract.createOrder(order.tokenId, order.price, order.deadline + 500, order.signature, order.nftContractAddress);
        assertEq(nftMarketPlaceContract.orderCounter(), 1);
        assertEq(nftMarketPlaceContract.tradeStates(0), 1);
    }

    function testGetOrder() public {
        switchSigner(userB);
        nft.setApprovalForAll(address(nftMarketPlaceContract), true);
        nftMarketPlaceContract.createOrder(order.tokenId, order.price, order.deadline + 500, order.signature, order.nftContractAddress);
        assertEq(nftMarketPlaceContract.orderCounter(), 1);
        assertEq(nftMarketPlaceContract.tradeStates(0), 1);

        (address seller, uint256 price, uint256 deadline, bool isActive, bytes memory signature) = nftMarketPlaceContract.getOrder(order.tokenId);
        assertEq(seller, userB);
        assertEq(price, order.price);
        assertEq(deadline, order.deadline + 500);
        assertEq(isActive, true);
        assertEq(signature, order.signature);
    }

    function testTradeStateBeforExecuting() public {
        switchSigner(userA);
        vm.expectRevert(NFTMarketplace.InvalidTradeStateError.selector);
        nftMarketPlaceContract.executeOrder(0);
    }

    function testPriceValueBeforeExecuting() public {
        switchSigner(userB);
        nft.setApprovalForAll(address(nftMarketPlaceContract), true);
        nftMarketPlaceContract.createOrder(order.tokenId, order.price, order.deadline + 500, order.signature, order.nftContractAddress);
        assertEq(nftMarketPlaceContract.orderCounter(), 1);
        assertEq(nftMarketPlaceContract.tradeStates(0), 1);


        vm.expectRevert(NFTMarketplace.PriceZeroError.selector);
        nftMarketPlaceContract.executeOrder{value: 0.4 ether}(0);
    }

    function testOrderActiveBeforeExecuting() public {
        switchSigner(userB);
        nft.setApprovalForAll(address(nftMarketPlaceContract), true);
        nftMarketPlaceContract.createOrder(order.tokenId, order.price, order.deadline + 500, order.signature, order.nftContractAddress);
        assertEq(nftMarketPlaceContract.orderCounter(), 1);
        assertEq(nftMarketPlaceContract.tradeStates(0), 1);

        // toggle active
        switchSigner(userA);
        nftMarketPlaceContract.toggleActive(order.tokenId, false);

        vm.expectRevert(NFTMarketplace.NFTAlreadyListedError.selector);
        nftMarketPlaceContract.executeOrder(0);
    }

    function testValidOrderIdBeforeExecuting() public {
        switchSigner(userB);
        vm.expectRevert(NFTMarketplace.InvalidOrderIdError.selector);
        nftMarketPlaceContract.executeOrder(4);
    }

    function testExecuteOrder() public {
        switchSigner(userB);
        nft.setApprovalForAll(address(nftMarketPlaceContract), true);

        //create a valid signature;
        order.signature = constructSig(order.nftContractAddress, order.tokenId, order.price, order.deadline + 500, privKeyB);
        nftMarketPlaceContract.createOrder(order.tokenId, order.price, order.deadline + 500, order.signature, order.nftContractAddress);
        assertEq(nftMarketPlaceContract.orderCounter(), 1);
        assertEq(nftMarketPlaceContract.tradeStates(0), 1);

        nftMarketPlaceContract.executeOrder(0);
        assertEq(nftMarketPlaceContract.tradeStates(0), 2);

    }
}
