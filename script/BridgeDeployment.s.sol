pragma solidity ^0.8.13;

import "../lib/forge-std/src/Script.sol";
import "../src/Bridge.sol";
import "../src/FakeStablecoin.sol";
import "../src/BridgingHelper.sol";

contract BridgeDeployment is Script {

    function run() public {
        vm.startBroadcast();

        address admin = vm.envAddress("ADMIN");
        assert(admin != address(0));

        BridgingHelper bh = new BridgingHelper();
        FakeStablecoin fst = new FakeStablecoin();

        Bridge b = new Bridge(address(fst));
        b.transferOwnership(admin);

        bh.setAddresses(address(fst), address(b));
        fst.setMinterStatus(address(bh), true);

        console.log("Bridge", address(b));
        console.log("FakeStablecoin", address(fst));
        console.log("BridgingHelper", address(bh));

        vm.stopBroadcast();
    }
}
