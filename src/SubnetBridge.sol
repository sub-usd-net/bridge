// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "../lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import "../lib/openzeppelin-contracts/contracts/access/Ownable.sol";

interface INativeMinter {
    function mintNativeCoin(address beneficiary, uint256 amount) external;
}

// if receiver is a contract that did not implement receive()
// we use the selfdestruct approach to force send value
contract FundNonReceivers {
    constructor(address target) payable  {
        selfdestruct(payable(target));
    }
}


contract SubnetBridge is Ownable {
    error MustNotBeZero();
    error MustBeSequential(uint curr, uint requested);
    error InsufficientBalance(uint avail, uint requested);

    event Deposit(address indexed depositor, uint indexed id, uint amount);
    event CompleteTransfer(address indexed beneficiary, uint indexed id, uint amount);
    event FundNonReceiver(address indexed beneficiary, uint amount);
    event MintNative(address indexed beneficiary, uint amount);
    event OwnerBorrow(address indexed owner, uint amount);
    event OwnerReturn(address indexed owner, uint amount);

    struct DepositInfo {
        address user;
        uint amount;
    }

    uint public depositId = 0;
    uint public crossChainDepositId = 0;
    mapping(address => uint) public ownerWithdrawal;
    address public immutable minter = 0x0200000000000000000000000000000000000001;

    // utils for bridging service to make it unnecessary to maintain an off-chain index
    mapping(uint => DepositInfo) public depositIdToDepositInfo;

    function deposit() external payable {
        if (msg.value == 0) {
            revert MustNotBeZero();
        }
        depositId++;
        emit Deposit(msg.sender, depositId, msg.value);
        depositIdToDepositInfo[depositId] = DepositInfo({
            user: msg.sender,
            amount: msg.value
        });
    }

    function completeTransfer(address beneficiary, uint targetId, uint amount) public onlyOwner {
        if (amount == 0) {
            revert MustNotBeZero();
        } else if (crossChainDepositId + 1 != targetId) {
            revert MustBeSequential(crossChainDepositId, targetId);
        }

        if (amount > address(this).balance) {
            _mintNative(address(this), amount - address(this).balance);
        }

        bool ok = payable(beneficiary).send(amount);
        if (!ok) {
            new FundNonReceivers{value: amount}(beneficiary);
            emit FundNonReceiver(beneficiary, amount);
        }
        crossChainDepositId++;
        emit CompleteTransfer(beneficiary, crossChainDepositId, amount);
    }

    function ownerReturn() public payable onlyOwner {
        ownerWithdrawal[msg.sender] -= msg.value;
        emit OwnerReturn(msg.sender, msg.value);
    }

    function ownerBorrow(uint amount) public onlyOwner {
        if (amount == 0) {
            revert MustNotBeZero();
        } else if (amount > address(this).balance) {
            // intentionally disallow 'borrowing' via minting
            revert InsufficientBalance(address(this).balance, amount);
        }

        ownerWithdrawal[msg.sender] += amount;
        payable(address(msg.sender)).transfer(amount);
        emit OwnerBorrow(msg.sender, amount);
    }

    function _mintNative(address beneficiary, uint amount) private {
        INativeMinter(minter).mintNativeCoin(beneficiary, amount);
        emit MintNative(beneficiary, amount);
    }

    function currentIds() public view returns (uint, uint) {
        return (depositId, crossChainDepositId);
    }

    function getDepositInfo(uint depositId_) public view returns (DepositInfo memory) {
        return depositIdToDepositInfo[depositId_];
    }
}

