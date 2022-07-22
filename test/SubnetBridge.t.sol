// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import "../lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import "../src/SubnetBridge.sol";

import "./mocks/MockContractWithoutReceive.sol";
import "./mocks/MockMinter.sol";

contract SubnetBridgeContractTest is Test {
    event Deposit(address indexed depositor, uint indexed id, uint amount);
    event CompleteTransfer(address indexed beneficiary, uint indexed id, uint amount);
    event FundNonReceiver(address indexed beneficiary, uint amount);
    event MintNative(address indexed beneficiary, uint amount);
    event OwnerBorrow(address indexed owner, uint amount);
    event OwnerReturn(address indexed owner, uint amount);

    address bridgeAdmin = address(0x5001);
    address testUser = address(0x5002);

    uint depositAmount = 1000 * 1e18;

    SubnetBridgeContract bridgeContract;
    MockContractWithoutReceive contractWithoutReceive = new MockContractWithoutReceive();

    function setUp() public {
        vm.prank(bridgeAdmin);
        bridgeContract = new SubnetBridgeContract();

        // Mock the minter and transfer ownership to the contract;
        vm.etch(bridgeContract.minter(), address(new MockMinter()).code);
    }

    function testOwner() public {
        assertEq(bridgeContract.owner(), bridgeAdmin);
    }

    function testDeposit() public {
        vm.deal(testUser, depositAmount);
        vm.startPrank(testUser);

        vm.expectEmit(true, true, false, true);
        emit Deposit(testUser, 0, depositAmount);
        bridgeContract.deposit{value: depositAmount}();

        assertEq(address(bridgeContract).balance, depositAmount);
        assertEq(bridgeContract.depositId(), 1);
        vm.stopPrank();
    }

    function testDepositZero() public {
        vm.startPrank(testUser);
        vm.expectRevert(bytes("must deposit greater than 0"));
        bridgeContract.deposit{value: 0}();
        vm.stopPrank();
    }

    function testOwnerBorrow() public {
        assertEq(address(bridgeContract).balance, 0);
        testDeposit();
        assertEq(address(bridgeAdmin).balance, 0);
        assertEq(bridgeContract.ownerWithdrawal(bridgeAdmin), 0);
        assertEq(address(bridgeContract).balance, depositAmount);

        vm.startPrank(bridgeAdmin);
        vm.expectEmit(true, false, false, true);
        emit OwnerBorrow(bridgeAdmin, depositAmount);
        bridgeContract.ownerBorrow(depositAmount);
        vm.stopPrank();

        assertEq(bridgeContract.ownerWithdrawal(bridgeAdmin), depositAmount);
        assertEq(address(bridgeAdmin).balance, depositAmount);
        assertEq(address(bridgeContract).balance, 0);
    }

    function testOwnerBorrowNotOwner() public {
        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        bridgeContract.ownerBorrow(depositAmount);

        vm.startPrank(testUser);
        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        bridgeContract.ownerBorrow(depositAmount);
        vm.stopPrank();
    }

    function testOwnerBorrowZero() public {
        vm.startPrank(bridgeAdmin);
        vm.expectRevert(SubnetBridgeContract.MustNotBeZero.selector);
        bridgeContract.ownerBorrow(0);
        vm.stopPrank();
    }

    function testOwnerBorrowInsufficientBalance() public {
        vm.startPrank(bridgeAdmin);
        vm.expectRevert(abi.encodeWithSelector(SubnetBridgeContract.InsufficientBalance.selector, 0, depositAmount));
        bridgeContract.ownerBorrow(depositAmount);
        vm.stopPrank();
    }

    function testOwnerReturn() public {
        assertEq(address(bridgeAdmin).balance, 0);
        assertEq(address(bridgeContract).balance, 0);
        assertEq(bridgeContract.ownerWithdrawal(bridgeAdmin), 0);

        testOwnerBorrow();
        assertEq(address(bridgeAdmin).balance, depositAmount);
        assertEq(bridgeContract.ownerWithdrawal(bridgeAdmin), depositAmount);
        assertEq(address(bridgeContract).balance, 0);

        vm.startPrank(bridgeAdmin);
        vm.expectEmit(true, false, false, true);
        emit OwnerReturn(bridgeAdmin, depositAmount);
        bridgeContract.ownerReturn{value: depositAmount}();

        assertEq(address(bridgeAdmin).balance, 0);
        assertEq(bridgeContract.ownerWithdrawal(bridgeAdmin), 0);
    }

    function testOwnerReturnUnderflow() public {
        vm.deal(bridgeAdmin, depositAmount);
        vm.startPrank(bridgeAdmin);
        vm.expectRevert(stdError.arithmeticError);
        bridgeContract.ownerReturn{value: depositAmount}();
    }

    function testCompleteTransfer() public {
        vm.startPrank(bridgeAdmin);
        vm.expectEmit(true, true, false, true);
        emit CompleteTransfer(address(testUser), 0, depositAmount);
        bridgeContract.completeTransfer(testUser, 0, depositAmount);
        assertEq(address(testUser).balance, depositAmount);
        assertEq(bridgeContract.crossChainDepositId(), 1);
        vm.stopPrank();
    }

    // The SubnetBridge uses the selfdestruct method to transfer native tokens
    // if the receiver is a contract that did not implement receive()
    function testCompleteTransferToNonReceiver() public {
        assertEq(address(contractWithoutReceive).balance, 0);
        vm.startPrank(bridgeAdmin);
        vm.expectEmit(true, false, false, true);
        emit FundNonReceiver(address(contractWithoutReceive), depositAmount);
        bridgeContract.completeTransfer(address(contractWithoutReceive), 0, depositAmount);
        assertEq(address(contractWithoutReceive).balance, depositAmount);
    }

    function testCompleteTransferZero() public {
        vm.startPrank(bridgeAdmin);
        vm.expectRevert(SubnetBridgeContract.MustNotBeZero.selector);
        bridgeContract.completeTransfer(testUser, 0, 0);
    }

    function testCompleteTransferInvalidId() public {
        vm.startPrank(bridgeAdmin);
        vm.expectRevert(abi.encodeWithSelector(SubnetBridgeContract.MustBeSequential.selector, 0, 1));
        bridgeContract.completeTransfer(testUser, 1, depositAmount);
    }

    function testCompleteTransferNotOwner() public {
        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        bridgeContract.completeTransfer(testUser, 0, depositAmount);
    }

    function testCompleteTransferRequireMintNative() public {
        vm.startPrank(bridgeAdmin);
        vm.expectEmit(true, false, false, true);
        emit MintNative(address(bridgeContract),  depositAmount);
        bridgeContract.completeTransfer(testUser, 0, depositAmount);
        assertEq(address(testUser).balance, depositAmount);
    }
}
