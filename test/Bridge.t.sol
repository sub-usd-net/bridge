// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import "../lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import "../src/Bridge.sol";
import "./mocks/MockToken.sol";

struct DI {
    address user;
    uint amount;
}

contract BridgeTest is Test {
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
    Bridge bridge;

    function setUp() public {
        vm.prank(tokenAdmin);
        mockToken = new MockToken("Mock", "MO");

        vm.prank(bridgeAdmin);
        bridge = new Bridge(address(mockToken));

        assertEq(address(bridge.stableToken()), address(mockToken));
    }

    function fundUserWithToken(address user_, uint amt) private {
        vm.prank(tokenAdmin);
        mockToken.transfer(user_, amt);
    }

    function approveTokenOnBridge(uint amt) private {
        IERC20(mockToken).approve(address(bridge), amt);
    }

    function testDeposit() public {
        assertEq(mockToken.balanceOf(address(bridge)), 0);
        assertEq(bridge.depositId(), 0);

        fundUserWithToken(testUserDepositor, depositAmount);
        vm.startPrank(testUserDepositor);
        approveTokenOnBridge(depositAmount);
        vm.expectEmit(true, true, false, true);
        emit Deposit(testUserDepositor, 1, depositAmount);
        bridge.deposit(depositAmount);
        vm.stopPrank();

        assertEq(bridge.depositId(), 1);
        assertEq(mockToken.balanceOf(address(bridge)), depositAmount);
    }

    function testDepositAndDepositInfo() public {
        assertEq(bridge.depositId(), 0);
        testDeposit();
        assertEq(bridge.depositId(), 1);
        assertEq(mockToken.balanceOf(address(bridge)), depositAmount);
        assertEq(mockToken.balanceOf(testUserReceiver), 0);

        Bridge.DepositInfo memory info = bridge.getDepositInfo(1);
        assertEq(info.user, testUserDepositor);
        assertEq(info.amount, depositAmount);
    }

    function testDepositInsufficientBalance() public {
        approveTokenOnBridge(depositAmount);
        vm.startPrank(testUserDepositor);
        vm.expectRevert(abi.encodeWithSelector(Bridge.InsufficientBalance.selector, 0, depositAmount));
        bridge.deposit(depositAmount);
        vm.stopPrank();
    }

    function testDepositInsufficientAllowance() public {
        fundUserWithToken(testUserDepositor, depositAmount);
        vm.startPrank(testUserDepositor);
        vm.expectRevert(abi.encodeWithSelector(Bridge.InsufficientAllowance.selector, 0, depositAmount));
        bridge.deposit(depositAmount);
        vm.stopPrank();
    }

    function testDepositZero() public {
        approveTokenOnBridge(depositAmount);
        vm.startPrank(testUserDepositor);
        vm.expectRevert(Bridge.MustNotBeZero.selector);
        bridge.deposit(0);
        vm.stopPrank();
    }

    function testOwnerBorrow() public {
        assertEq(mockToken.balanceOf(address(bridge)), 0);
        testDeposit();
        assertEq(mockToken.balanceOf(bridgeAdmin), 0);
        assertEq(mockToken.balanceOf(address(bridge)), depositAmount);

        uint borrowAmount = depositAmount;

        vm.startPrank(bridgeAdmin);
        vm.expectEmit(true, false, false, true);
        emit OwnerBorrow(bridgeAdmin, borrowAmount);
        bridge.ownerBorrow(borrowAmount);
        assertEq(mockToken.balanceOf(address(bridge)), 0);
        assertEq(mockToken.balanceOf(bridgeAdmin), borrowAmount);
        vm.stopPrank();
    }

    function testOwnerBorrowNotOwner() public {
        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        bridge.ownerBorrow(depositAmount);
    }

    function testOwnerBorrowZero() public {
        vm.startPrank(bridgeAdmin);
        vm.expectRevert(Bridge.MustNotBeZero.selector);
        bridge.ownerBorrow(0);
        vm.stopPrank();
    }

    function testOwnerReturn() public {
        assertEq(bridge.ownerWithdrawals(bridgeAdmin), 0);
        testOwnerBorrow();
        assertEq(bridge.ownerWithdrawals(bridgeAdmin), depositAmount);

        vm.startPrank(bridgeAdmin);
        approveTokenOnBridge(depositAmount);

        vm.expectEmit(true, false, false, true);
        emit OwnerReturn(bridgeAdmin, depositAmount / 2);
        bridge.ownerReturn(depositAmount / 2);
        assertEq(bridge.ownerWithdrawals(bridgeAdmin), depositAmount / 2);

        vm.expectEmit(true, false, false, true);
        emit OwnerReturn(bridgeAdmin, depositAmount / 2);
        bridge.ownerReturn(depositAmount / 2);
        assertEq(bridge.ownerWithdrawals(bridgeAdmin), 0);
        vm.stopPrank();
    }

    function testOwnerReturnInsufficientAllowance() public {
        assertEq(bridge.ownerWithdrawals(bridgeAdmin), 0);
        testOwnerBorrow();
        assertEq(bridge.ownerWithdrawals(bridgeAdmin), depositAmount);

        vm.startPrank(bridgeAdmin);
        vm.expectRevert(abi.encodeWithSelector(Bridge.InsufficientAllowance.selector, 0, depositAmount));
        bridge.ownerReturn(depositAmount);
    }

    function testOwnerReturnUnderflow() public {
        fundUserWithToken(bridgeAdmin, 1);
        vm.startPrank(bridgeAdmin);
        approveTokenOnBridge(depositAmount);
        vm.expectRevert(stdError.arithmeticError);
        bridge.ownerReturn(1);
        vm.stopPrank();
    }

    function testCompleteTransfer() public {
        assertEq(bridge.depositId(), 0);
        testDeposit();
        assertEq(bridge.depositId(), 1);
        assertEq(mockToken.balanceOf(address(bridge)), depositAmount);
        assertEq(mockToken.balanceOf(testUserReceiver), 0);

        vm.startPrank(bridgeAdmin);
        vm.expectEmit(true, true, false, true);
        emit CompleteTransfer(testUserReceiver, 1, depositAmount / 2);
        bridge.completeTransfer(testUserReceiver, 1, depositAmount / 2);
        vm.stopPrank();

        assertEq(mockToken.balanceOf(address(bridge)), depositAmount / 2);
        assertEq(mockToken.balanceOf(testUserReceiver), depositAmount / 2);
    }

    function testCompleteTransferZero() public {
        assertEq(bridge.depositId(), 0);
        testDeposit();
        assertEq(bridge.depositId(), 1);
        assertEq(mockToken.balanceOf(address(bridge)), depositAmount);
        assertEq(mockToken.balanceOf(testUserReceiver), 0);

        vm.startPrank(bridgeAdmin);
        vm.expectRevert(Bridge.MustNotBeZero.selector);
        bridge.completeTransfer(testUserReceiver, 1, 0);
    }

    function testCompleteTransferInvalidId() public {
        testDeposit();
        vm.startPrank(bridgeAdmin);
        vm.expectRevert(abi.encodeWithSelector(Bridge.MustBeSequential.selector, 0, 2));
        bridge.completeTransfer(testUserDepositor, 2, depositAmount);
    }

    function testCompleteTransferNotOwner() public {
        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        bridge.completeTransfer(testUserDepositor, 0, depositAmount);
    }

}
