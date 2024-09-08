// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IArcade} from "./interface/IArcade.sol";
import {Multicall} from "@openzeppelin/contracts/utils/Multicall.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import {IRewardPolicy} from "./interface/IRewardPolicy.sol";

contract Arcade is IArcade, Multicall {
    using SafeERC20 for IERC20;
    using MessageHashUtils for bytes32;

    mapping(address currency => mapping(address user => uint256)) public availableBalanceOf;
    mapping(address currency => mapping(address user => uint256)) public lockedBalanceOf;
    mapping(bytes32 puzzleId => uint256) public statusOf; // player + expiry timestamp
    mapping(bytes32 puzzleId => uint256) public rewardOf;

    modifier validatePuzzle(Puzzle calldata puzzle, bytes calldata signature) {
        if (
            !SignatureChecker.isValidSignatureNow(
                puzzle.creator, keccak256(abi.encode(puzzle)).toEthSignedMessageHash(), signature
            )
        ) {
            revert();
        }
        _;
    }

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

    function lock(Puzzle calldata puzzle, bytes calldata signature, uint256 toll, bytes calldata data)
        external
        validatePuzzle(puzzle, signature)
    {
        // Collect toll from player. TODO: use availableBalanceOf first.
        IERC20(puzzle.currency).transferFrom(msg.sender, address(this), toll);
        bytes32 puzzleId = keccak256(abi.encode(puzzle));

        // Make sure same game isn't created twice. Also checking if someone else is playing.
        if (statusOf[puzzleId] != 0) {
            revert();
        }

        // Handle reward. Lock reward amount.
        uint256 reward = IRewardPolicy(puzzle.rewardPolicy).reward(toll, data);
        rewardOf[puzzleId] = reward;
        availableBalanceOf[puzzle.currency][puzzle.creator] -= reward;
        lockedBalanceOf[puzzle.currency][puzzle.creator] += reward;

        // Handle status. Pack player and expiry timestamp.
        uint256 status;
        address player = msg.sender;
        uint96 expiryTimestamp = uint96(block.timestamp) + puzzle.timeLimit;
        assembly {
            status := add(shl(96, player), expiryTimestamp)
        }
        statusOf[puzzleId] = status;
    }

    function expire(Puzzle calldata puzzle, bytes calldata signature) external validatePuzzle(puzzle, signature) {
        bytes32 puzzleId = keccak256(abi.encode(puzzle));
        uint256 status = statusOf[puzzleId];

        // Make sure game has expired.
        if (uint96(block.timestamp) > uint96(status)) {
            revert();
        }

        // Unfreeze assets.
        uint256 reward = rewardOf[puzzleId];
        lockedBalanceOf[puzzle.currency][puzzle.creator] -= reward;
        availableBalanceOf[puzzle.currency][puzzle.creator] += reward;
    }

    function solve(Puzzle calldata puzzle, bytes calldata signature, uint256 solution)
        external
        validatePuzzle(puzzle, signature)
    {
        bytes32 puzzleId = keccak256(abi.encode(puzzle));
        uint256 status = statusOf[puzzleId];

        // Make sure game hasn't expired.
        if (uint96(block.timestamp) > uint96(status)) {
            revert();
        }

        address player;
        assembly {
            player := shr(96, status)
        }

        // Make sure the solution is correct.
        if (puzzle.answer != keccak256(abi.encode(solution, puzzle.problem))) {
            revert();
        }

        // Settle reward.
        uint256 reward = rewardOf[puzzleId];
        lockedBalanceOf[puzzle.currency][puzzle.creator] -= reward;
        availableBalanceOf[puzzle.currency][player] += reward;
    }

    // TODO: cancel intent.
}
