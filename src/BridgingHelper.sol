pragma solidity ^0.8.0;

import "../lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import "forge-std/console.sol";

interface IStablecoin {
    function mint(uint amount) external;
    function approve(address spender, uint amount) external;
    function decimals() external returns (uint8);
}

interface IBridge {
    function depositOnBehalfOf(address forUser, uint amount) external;
}

/**
BridgingHelper makes the bridging process on the stablecoin subnet simpler

** !! Only for Testnet !! **

Instead of users needing to:
(1) obtain the test stablecoin
(2) approve the bridge to transfer the stablecoin on their behalf
(3) call `deposit` on the bridge,

With this users can simply send AVAX to this contract
and it will take care of the rest. The funds can
then be bridged over to the testnet stablecoin subnet
*/
contract BridgingHelper is Ownable  {
    address public stablecoin;
    address public bridge;

    // for conversions (avax -> stablecoin)
    uint public avaxPrice = 25; // obv not a real stablecoin...
    uint8 public avaxDecimals = 18;
    uint8 public stablecoinDecimals;

    receive() external payable {
        require(stablecoin != address(0), "owner must set stablecoin first");
        require(bridge != address(0), "owner must set bridge first");

        require(msg.value > 0, "zero value");
        uint amount = equivalentStablecoinsForAvax(msg.value);
        IStablecoin(stablecoin).mint(amount);
        IBridge(bridge).depositOnBehalfOf(msg.sender, amount);
    }

    function equivalentStablecoinsForAvax(uint amount) public view returns (uint) {
        return avaxPrice * amount * 10 ** stablecoinDecimals / 10 ** avaxDecimals;
    }

    // manual oracle. Remember these contracts are just for testnet; to make onboarding to the *test* subnet
    function updatePrice(uint newPrice) external onlyOwner {
        avaxPrice = newPrice;
    }

    function setAddresses(address stablecoin_, address bridge_) external onlyOwner {
        require(stablecoin_ != address(0) && bridge_ != address(0), "cannot be zero address");

        stablecoin = stablecoin_;
        bridge = bridge_;
        stablecoinDecimals = IStablecoin(stablecoin_).decimals();

        IStablecoin(stablecoin_).approve(bridge_, type(uint256).max);
    }

    function withdraw() external onlyOwner {
        payable(msg.sender).transfer(address(this).balance);
    }

}
