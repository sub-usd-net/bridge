// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "../lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

/**
FakeStablecoin is a fake stablecoin intended for use on the Fuji C-Chain testnet

** !! Only for Testnet !! **

This represents a stablecoin token that users can bridge from the Fuji C-Chain
to the stablecoin subnet

*/
contract FakeStablecoin is Ownable, ERC20 {
    mapping (address => bool) public minters;

    modifier onlyMinters {
        require(minters[msg.sender], "Not an approved minter");
        _;
    }

    constructor() ERC20("FST", "FakeStablecoin") {
        _mint(msg.sender, 10000000000 * 10 ** 6);
    }

    function decimals() public view virtual override returns (uint8) {
        return 6;
    }

    function mint(uint amount) external onlyMinters {
        _mint(msg.sender, amount);
    }

    function setMinterStatus(address minter, bool canMint) external onlyOwner {
        minters[minter] = canMint;
    }

}
