// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IArcade} from "./interface/IArcade.sol";
import {Multicall} from "@openzeppelin/contracts/utils/Multicall.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract Arcade is IArcade, Multicall {
    using SafeERC20 for IERC20;

    mapping(address currency => mapping(address user => uint256)) public availableBalanceOf;
    mapping(address currency => mapping(address user => uint256)) public lockedBalanceOf;
    mapping(bytes32 puzzleId => uint256) public statusOf; // player + expiry timestamp
    mapping(bytes32 puzzleId => uint256) public rewardOf;

    function balance(address currency, address user) external view returns (uint256 available, uint256 locked) {
        available = availableBalanceOf[currency][user];
        locked = lockedBalanceOf[currency][user];
    }

    function deposit(address currency, address user, uint256 amount) external {
        IERC20(currency).safeTransferFrom(msg.sender, address(this), amount);
        availableBalanceOf[currency][user] += amount;
    }

    function withdraw(address currency, uint256 amount) external {
        availableBalanceOf[currency][msg.sender] -= amount;
        IERC20(currency).safeTransfer(msg.sender, amount);
    }

    function lock(Puzzle calldata puzzle, Signature calldata signature, uint256 toll) external {}

    function unlock(Puzzle calldata puzzle, Signature calldata signature) external {}

    function solve(Puzzle calldata puzzle, Signature calldata signature, uint256 solution) external {}
}
