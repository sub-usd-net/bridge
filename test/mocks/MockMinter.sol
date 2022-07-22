// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "../../lib/forge-std/src/Test.sol";

contract MockMinter is Test {
    function mintNativeCoin(address beneficiary, uint256 amount) external {
        vm.deal(beneficiary, amount);
    }
}
