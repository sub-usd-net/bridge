// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "../lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "../lib/openzeppelin-contracts/contracts/access/Ownable.sol";


contract Bridge is Ownable {
    using SafeERC20 for IERC20;

    error MustBeSequential(uint curr, uint requested);
    error MustNotBeZero();
    error InsufficientAllowance(uint avail, uint requested);
    error InsufficientBalance(uint avail, uint requested);

    event Deposit(address indexed depositor, uint indexed id, uint amount);
    event CompleteTransfer(address indexed beneficiary, uint indexed id, uint amount);
    event OwnerBorrow(address indexed owner, uint amount);
    event OwnerReturn(address indexed owner, uint amount);

    struct DepositInfo {
        address user;
        uint amount;
    }

    // depositId is incremented after each deposit to this side of the bridge
    // and it should be used when fulfilling the transfer on the other side of the bridge
    uint public depositId = 0;

    // crossChainDepositId is incremented after each completed transfer to this side of the bridge
    // it must correspond to the depositId on the other side of the bridge. The contract
    // requires that this increases sequentially; hence no gaps are allowed in fulfilling transfers
    uint public crossChainDepositId = 0;

    // ownerWithdrawals tracks owner borrow balance
    mapping(address => uint) public ownerWithdrawals;


    // stableToken points to the C-Chain stable coin token (such as USDC) that is accepted
    // by this contract and is then expected to be minted on the other side of the bridge
    IERC20 public stableToken;

    // utils for bridging service to make it unnecessary to maintain an off-chain index
    mapping(uint => uint) public depositIdToBlock;
    mapping(uint => DepositInfo) public depositIdToDepositInfo;

    constructor(address _stableToken) {
        stableToken = IERC20(_stableToken);
    }

    function deposit(uint amount) public {
        _validateBalance(msg.sender, amount);
        _validateAllowance(msg.sender, amount);

        stableToken.safeTransferFrom(msg.sender, address(this), amount);
        emit Deposit(msg.sender, depositId, amount);
        depositIdToBlock[depositId] = block.number;
        depositIdToDepositInfo[depositId] = DepositInfo({
            user: msg.sender,
            amount: amount
        });
        depositId++;
    }

    function completeTransfer(address beneficiary, uint targetId, uint amount) public onlyOwner {
        if (crossChainDepositId != targetId) {
            revert MustBeSequential(crossChainDepositId, targetId);
        }
        _validateBalance(address(this), amount);

        stableToken.safeTransfer(beneficiary, amount);
        emit CompleteTransfer(beneficiary, crossChainDepositId, amount);
        crossChainDepositId++;
    }

    function ownerBorrow(uint amount) public onlyOwner {
        _validateBalance(address(this), amount);

        ownerWithdrawals[owner()] += amount;
        stableToken.safeTransfer(owner(), amount);
        emit OwnerBorrow(owner(), amount);
    }

    function ownerReturn(uint amount) external onlyOwner {
        _validateBalance(msg.sender, amount);
        _validateAllowance(msg.sender, amount);

        stableToken.safeTransferFrom(msg.sender, address(this), amount);
        ownerWithdrawals[msg.sender] -= amount;
        emit OwnerReturn(msg.sender, amount);
    }

    function _validateBalance(address from, uint amount) private view {
        if (amount == 0) {
            revert MustNotBeZero();
        }
        uint balance = stableToken.balanceOf(from);
        if (balance < amount) {
            revert InsufficientBalance(balance, amount);
        }
    }

    function _validateAllowance(address from, uint amount) private view {
        uint allowance = stableToken.allowance(from, address(this));
        if (allowance < amount) {
            revert InsufficientAllowance(allowance, amount);
        }
    }

    function currentIds() public view returns (uint, uint) {
        return (depositId, crossChainDepositId);
    }

    function getDepositInfo(uint depositId_) public view returns (DepositInfo memory) {
        return depositIdToDepositInfo[depositId_];
    }
}
