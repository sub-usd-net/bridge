// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import "../src/Bridge.sol";
import "../src/BridgingHelper.sol";
import "../src/FakeStablecoin.sol";

contract BridgeHelper is Test {

    Bridge bridge;
    FakeStablecoin fst;
    BridgingHelper bridgeHelper;

    address tokenAdmin = address(0x5001);
    address bridgeAdmin = address(0x05002);
    address testUserDepositor = address(0x5003);

    function setUp() public {
        vm.prank(tokenAdmin);
        fst = new FakeStablecoin();

        vm.startPrank(bridgeAdmin);
        bridge = new Bridge(address(fst));
        bridgeHelper = new BridgingHelper();
        bridgeHelper.setAddresses(address(fst), address(bridge));
        vm.stopPrank();

        vm.prank(tokenAdmin);
        fst.setMinterStatus(address(bridgeHelper), true);
    }

    function testBridgeAvax() public {
        assertEq(fst.decimals(), 6);
        assertEq(bridgeHelper.stablecoinDecimals(), 6);
        assertEq(bridgeHelper.avaxPrice(), 25);

        uint avaxAmount = 2 ether;
        uint expectedUsdDepositAmount = 50 * 10 ** 6;
        vm.deal(testUserDepositor, avaxAmount);

        assertEq(fst.balanceOf(testUserDepositor), 0);
        assertEq(fst.balanceOf(address(bridge)), 0);
        assertEq(fst.balanceOf(address(bridgeHelper)), 0);
        assertEq(address(bridge).balance, 0);
        assertEq(address(bridgeHelper).balance, 0);
        assertEq(testUserDepositor.balance, avaxAmount);
        assertEq(bridge.depositId(), 0);

        vm.startPrank(testUserDepositor);
        (bool ok,) = address(bridgeHelper).call{value: avaxAmount}("");
        assert(ok);
        vm.stopPrank();

        assertEq(fst.balanceOf(testUserDepositor), 0);
        assertEq(fst.balanceOf(address(bridge)), expectedUsdDepositAmount);
        assertEq(fst.balanceOf(address(bridgeHelper)), 0);
        assertEq(address(bridge).balance, 0);
        assertEq(address(bridgeHelper).balance, avaxAmount);
        assertEq(testUserDepositor.balance, 0);
        assertEq(bridge.depositId(), 1);
    }

}
