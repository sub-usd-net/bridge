// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import "../lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import "../src/SubnetBridge.sol";

import "./mocks/MockContractWithoutReceive.sol";
import "./mocks/MockMinter.sol";

contract SubnetBridgeTest is Test {
    event Deposit(address indexed depositor, uint indexed id, uint amount);
    event CompleteTransfer(address indexed beneficiary, uint indexed id, uint amount);
    event FundNonReceiver(address indexed beneficiary, uint amount);
    event MintNative(address indexed beneficiary, uint amount);
    event OwnerBorrow(address indexed owner, uint amount);
    event OwnerReturn(address indexed owner, uint amount);

    address bridgeAdmin = address(0x5001);
    address testUser = address(0x5002);

    uint depositAmount = 1000 * 1e18;

    SubnetBridge subnetBridge;

    function setUp() public {
        vm.prank(bridgeAdmin);
        subnetBridge = new SubnetBridge();

        // Mock the minter and transfer ownership to the contract;
        vm.etch(subnetBridge.minter(), address(new MockMinter()).code);
    }

    function testOwner() public {
        assertEq(subnetBridge.owner(), bridgeAdmin);
    }

    function testDeposit() public {
        uint bn = 500;
        vm.roll(bn);
        vm.deal(testUser, depositAmount);
        vm.startPrank(testUser);

        vm.expectEmit(true, true, false, true);
        emit Deposit(testUser, 0, depositAmount);
        subnetBridge.deposit{value: depositAmount}();

        assertEq(subnetBridge.depositIdToBlock(0), 500);
        assertEq(address(subnetBridge).balance, depositAmount);
        assertEq(subnetBridge.depositId(), 1);
        vm.stopPrank();
    }

    function testDepositAndDepositInfo() public {
        assertEq(address(subnetBridge).balance, 0);
        testDeposit();
        assertEq(address(bridgeAdmin).balance, 0);
        assertEq(subnetBridge.ownerWithdrawal(bridgeAdmin), 0);
        assertEq(address(subnetBridge).balance, depositAmount);

        SubnetBridge.DepositInfo memory info = subnetBridge.getDepositInfo(0);
        assertEq(info.user, testUser);
        assertEq(info.amount, depositAmount);
    }

    function testDepositZero() public {
        vm.startPrank(testUser);
        vm.expectRevert(SubnetBridge.MustNotBeZero.selector);
        subnetBridge.deposit{value: 0}();
        vm.stopPrank();
    }

    function testOwnerBorrow() public {
        assertEq(address(subnetBridge).balance, 0);
        testDeposit();
        assertEq(address(bridgeAdmin).balance, 0);
        assertEq(subnetBridge.ownerWithdrawal(bridgeAdmin), 0);
        assertEq(address(subnetBridge).balance, depositAmount);

        vm.startPrank(bridgeAdmin);
        vm.expectEmit(true, false, false, true);
        emit OwnerBorrow(bridgeAdmin, depositAmount);
        subnetBridge.ownerBorrow(depositAmount);
        vm.stopPrank();

        assertEq(subnetBridge.ownerWithdrawal(bridgeAdmin), depositAmount);
        assertEq(address(bridgeAdmin).balance, depositAmount);
        assertEq(address(subnetBridge).balance, 0);
    }

    function testOwnerBorrowNotOwner() public {
        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        subnetBridge.ownerBorrow(depositAmount);

        vm.startPrank(testUser);
        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        subnetBridge.ownerBorrow(depositAmount);
        vm.stopPrank();
    }

    function testOwnerBorrowZero() public {
        vm.startPrank(bridgeAdmin);
        vm.expectRevert(SubnetBridge.MustNotBeZero.selector);
        subnetBridge.ownerBorrow(0);
        vm.stopPrank();
    }

    function testOwnerBorrowInsufficientBalance() public {
        vm.startPrank(bridgeAdmin);
        vm.expectRevert(abi.encodeWithSelector(SubnetBridge.InsufficientBalance.selector, 0, depositAmount));
        subnetBridge.ownerBorrow(depositAmount);
        vm.stopPrank();
    }

    function testOwnerReturn() public {
        assertEq(address(bridgeAdmin).balance, 0);
        assertEq(address(subnetBridge).balance, 0);
        assertEq(subnetBridge.ownerWithdrawal(bridgeAdmin), 0);

        testOwnerBorrow();
        assertEq(address(bridgeAdmin).balance, depositAmount);
        assertEq(subnetBridge.ownerWithdrawal(bridgeAdmin), depositAmount);
        assertEq(address(subnetBridge).balance, 0);

        vm.startPrank(bridgeAdmin);
        vm.expectEmit(true, false, false, true);
        emit OwnerReturn(bridgeAdmin, depositAmount);
        subnetBridge.ownerReturn{value: depositAmount}();

        assertEq(address(bridgeAdmin).balance, 0);
        assertEq(subnetBridge.ownerWithdrawal(bridgeAdmin), 0);
    }

    function testOwnerReturnUnderflow() public {
        vm.deal(bridgeAdmin, depositAmount);
        vm.startPrank(bridgeAdmin);
        vm.expectRevert(stdError.arithmeticError);
        subnetBridge.ownerReturn{value: depositAmount}();
    }

    function testCompleteTransfer() public {
        vm.startPrank(bridgeAdmin);
        vm.expectEmit(true, true, false, true);
        emit CompleteTransfer(address(testUser), 0, depositAmount);
        subnetBridge.completeTransfer(testUser, 0, depositAmount);
        assertEq(address(testUser).balance, depositAmount);
        assertEq(subnetBridge.crossChainDepositId(), 1);
        vm.stopPrank();
    }

    // The SubnetBridge uses the selfdestruct method to transfer native tokens
    // if the receiver is a contract that did not implement receive()
    function testCompleteTransferToNonReceiver() public {
        MockContractWithoutReceive contractWithoutReceive = new MockContractWithoutReceive();
        assertEq(address(contractWithoutReceive).balance, 0);
        vm.startPrank(bridgeAdmin);
        vm.expectEmit(true, false, false, true);
        emit FundNonReceiver(address(contractWithoutReceive), depositAmount);
        subnetBridge.completeTransfer(address(contractWithoutReceive), 0, depositAmount);
        assertEq(address(contractWithoutReceive).balance, depositAmount);
    }

    function testCompleteTransferZero() public {
        vm.startPrank(bridgeAdmin);
        vm.expectRevert(SubnetBridge.MustNotBeZero.selector);
        subnetBridge.completeTransfer(testUser, 0, 0);
    }

    function testCompleteTransferInvalidId() public {
        vm.startPrank(bridgeAdmin);
        vm.expectRevert(abi.encodeWithSelector(SubnetBridge.MustBeSequential.selector, 0, 1));
        subnetBridge.completeTransfer(testUser, 1, depositAmount);
    }

    function testCompleteTransferNotOwner() public {
        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        subnetBridge.completeTransfer(testUser, 0, depositAmount);
    }

    function testCompleteTransferRequireMintNative() public {
        vm.startPrank(bridgeAdmin);
        vm.expectEmit(true, false, false, true);
        emit MintNative(address(subnetBridge),  depositAmount);
        subnetBridge.completeTransfer(testUser, 0, depositAmount);
        assertEq(address(testUser).balance, depositAmount);
    }
}
