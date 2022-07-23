pragma solidity ^0.8.13;

import "../lib/forge-std/src/Script.sol";
import "../src/SubnetBridge.sol";

contract SubnetBridgeDeployment is Script {

    function run() public {
        vm.startBroadcast();

        address admin = vm.envAddress("ADMIN");
        assert(admin != address(0));

        SubnetBridge sb = new SubnetBridge();
        sb.transferOwnership(admin);

        console.log("Deployed SubnetBridge", address(sb));

        vm.stopBroadcast();
    }
}
