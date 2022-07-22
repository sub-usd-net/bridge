// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import "../lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import "../src/Bridge.sol";
import "./mocks/MockToken.sol";

contract BridgeContractTest is Test {
    event Deposit(address indexed depositor, uint indexed id, uint amount);
    event CompleteTransfer(address indexed beneficiary, uint indexed id, uint amount);
    event OwnerBorrow(address indexed owner, uint amount);
    event OwnerReturn(address indexed owner, uint amount);

    address tokenAdmin = address(0x5001);
    address bridgeAdmin = address(0x05002);
    address testUserDepositor = address(0x5003);
    address testUserReceiver = address(0x5004);

    uint depositAmount = 1000 * 1e6;

    MockToken mockToken;
    BridgeContract bridgeContract;

    function setUp() public {
        vm.prank(tokenAdmin);
        mockToken = new MockToken("Mock", "MO");

        vm.prank(bridgeAdmin);
        bridgeContract = new BridgeContract(address(mockToken));

        assertEq(address(bridgeContract.stableToken()), address(mockToken));
    }

    function fundUserWithToken(address user_, uint amt) private {
        vm.prank(tokenAdmin);
        mockToken.transfer(user_, amt);
    }

    function approveTokenOnBridge(uint amt) private {
        IERC20(mockToken).approve(address(bridgeContract), amt);
    }

    function testDeposit() public {
        uint bn = 500;
        vm.roll(500);

        assertEq(mockToken.balanceOf(address(bridgeContract)), 0);
        assertEq(bridgeContract.depositId(), 0);

        fundUserWithToken(testUserDepositor, depositAmount);
        vm.startPrank(testUserDepositor);
        approveTokenOnBridge(depositAmount);
        vm.expectEmit(true, true, false, true);
        emit Deposit(testUserDepositor, 0, depositAmount);
        bridgeContract.deposit(depositAmount);
        vm.stopPrank();

        assertEq(bridgeContract.depositIdToBlock(0), bn);
        assertEq(bridgeContract.depositId(), 1);
        assertEq(mockToken.balanceOf(address(bridgeContract)), depositAmount);
    }

    function testDepositInsufficientBalance() public {
        approveTokenOnBridge(depositAmount);
        vm.startPrank(testUserDepositor);
        vm.expectRevert(abi.encodeWithSelector(BridgeContract.InsufficientBalance.selector, 0, depositAmount));
        bridgeContract.deposit(depositAmount);
        vm.stopPrank();
    }

    function testDepositInsufficientAllowance() public {
        fundUserWithToken(testUserDepositor, depositAmount);
        vm.startPrank(testUserDepositor);
        vm.expectRevert(abi.encodeWithSelector(BridgeContract.InsufficientAllowance.selector, 0, depositAmount));
        bridgeContract.deposit(depositAmount);
        vm.stopPrank();
    }

    function testDepositZero() public {
        approveTokenOnBridge(depositAmount);
        vm.startPrank(testUserDepositor);
        vm.expectRevert(BridgeContract.MustNotBeZero.selector);
        bridgeContract.deposit(0);
        vm.stopPrank();
    }

    function testOwnerBorrow() public {
        assertEq(mockToken.balanceOf(address(bridgeContract)), 0);
        testDeposit();
        assertEq(mockToken.balanceOf(bridgeAdmin), 0);
        assertEq(mockToken.balanceOf(address(bridgeContract)), depositAmount);

        uint borrowAmount = depositAmount;

        vm.startPrank(bridgeAdmin);
        vm.expectEmit(true, false, false, true);
        emit OwnerBorrow(bridgeAdmin, borrowAmount);
        bridgeContract.ownerBorrow(borrowAmount);
        assertEq(mockToken.balanceOf(address(bridgeContract)), 0);
        assertEq(mockToken.balanceOf(bridgeAdmin), borrowAmount);
        vm.stopPrank();
    }

    function testOwnerBorrowNotOwner() public {
        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        bridgeContract.ownerBorrow(depositAmount);
    }

    function testOwnerBorrowZero() public {
        vm.startPrank(bridgeAdmin);
        vm.expectRevert(BridgeContract.MustNotBeZero.selector);
        bridgeContract.ownerBorrow(0);
        vm.stopPrank();
    }

    function testOwnerReturn() public {
        assertEq(bridgeContract.ownerWithdrawals(bridgeAdmin), 0);
        testOwnerBorrow();
        assertEq(bridgeContract.ownerWithdrawals(bridgeAdmin), depositAmount);

        vm.startPrank(bridgeAdmin);
        approveTokenOnBridge(depositAmount);

        vm.expectEmit(true, false, false, true);
        emit OwnerReturn(bridgeAdmin, depositAmount / 2);
        bridgeContract.ownerReturn(depositAmount / 2);
        assertEq(bridgeContract.ownerWithdrawals(bridgeAdmin), depositAmount / 2);

        vm.expectEmit(true, false, false, true);
        emit OwnerReturn(bridgeAdmin, depositAmount / 2);
        bridgeContract.ownerReturn(depositAmount / 2);
        assertEq(bridgeContract.ownerWithdrawals(bridgeAdmin), 0);
        vm.stopPrank();
    }

    function testOwnerReturnInsufficientAllowance() public {
        assertEq(bridgeContract.ownerWithdrawals(bridgeAdmin), 0);
        testOwnerBorrow();
        assertEq(bridgeContract.ownerWithdrawals(bridgeAdmin), depositAmount);

        vm.startPrank(bridgeAdmin);
        vm.expectRevert(abi.encodeWithSelector(BridgeContract.InsufficientAllowance.selector, 0, depositAmount));
        bridgeContract.ownerReturn(depositAmount);
    }

    function testOwnerReturnUnderflow() public {
        fundUserWithToken(bridgeAdmin, 1);
        vm.startPrank(bridgeAdmin);
        approveTokenOnBridge(depositAmount);
        vm.expectRevert(stdError.arithmeticError);
        bridgeContract.ownerReturn(1);
        vm.stopPrank();
    }

    function testCompleteTransfer() public {
        assertEq(bridgeContract.depositId(), 0);
        testDeposit();
        assertEq(bridgeContract.depositId(), 1);
        assertEq(mockToken.balanceOf(address(bridgeContract)), depositAmount);
        assertEq(mockToken.balanceOf(testUserReceiver), 0);

        vm.startPrank(bridgeAdmin);
        vm.expectEmit(true, true, false, true);
        emit CompleteTransfer(testUserReceiver, 0, depositAmount / 2);
        bridgeContract.completeTransfer(testUserReceiver, 0, depositAmount / 2);
        vm.stopPrank();

        assertEq(mockToken.balanceOf(address(bridgeContract)), depositAmount / 2);
        assertEq(mockToken.balanceOf(testUserReceiver), depositAmount / 2);
    }

    function testCompleteTransferZero() public {
        assertEq(bridgeContract.depositId(), 0);
        testDeposit();
        assertEq(bridgeContract.depositId(), 1);
        assertEq(mockToken.balanceOf(address(bridgeContract)), depositAmount);
        assertEq(mockToken.balanceOf(testUserReceiver), 0);

        vm.startPrank(bridgeAdmin);
        vm.expectRevert(BridgeContract.MustNotBeZero.selector);
        bridgeContract.completeTransfer(testUserReceiver, 0, 0);
    }

    function testCompleteTransferInvalidId() public {
        testDeposit();
        vm.startPrank(bridgeAdmin);
        vm.expectRevert(abi.encodeWithSelector(BridgeContract.MustBeSequential.selector, 0, 1));
        bridgeContract.completeTransfer(testUserDepositor, 1, depositAmount);
    }

    function testCompleteTransferNotOwner() public {
        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        bridgeContract.completeTransfer(testUserDepositor, 0, depositAmount);
    }

}
