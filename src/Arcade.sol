// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Ownable, Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Multicall} from "@openzeppelin/contracts/utils/Multicall.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import {IArcade} from "./interface/IArcade.sol";
import {IRewardPolicy} from "./interface/IRewardPolicy.sol";

contract Arcade is IArcade, Ownable2Step, Multicall, EIP712 {
    using SafeERC20 for IERC20;

    uint256 public constant FEE_PRECISION = 100000;
    bytes32 public constant PUZZLE_TYPEHASH = keccak256(
        "Puzzle(address creator,bytes32 problem,bytes32 answer,uint96 timeLimit,address currency,address rewardPolicy,bytes rewardData)"
    );

    uint256 public fee = 1000; // initial fee 100 bps
    mapping(address currency => mapping(address user => uint256)) public availableBalanceOf;
    mapping(address currency => mapping(address user => uint256)) public lockedBalanceOf;
    mapping(bytes32 puzzleId => uint256) public statusOf; // player + expiry timestamp
    mapping(bytes32 puzzleId => uint256) public rewardOf;

    modifier validatePuzzle(Puzzle calldata puzzle, bytes calldata signature) {
        if (
            !SignatureChecker.isValidSignatureNow(
                puzzle.creator,
                _hashTypedDataV4(
                    keccak256(
                        abi.encode(
                            PUZZLE_TYPEHASH,
                            puzzle.creator,
                            puzzle.problem,
                            puzzle.answer,
                            puzzle.timeLimit,
                            puzzle.currency,
                            puzzle.rewardPolicy,
                            keccak256(puzzle.rewardData)
                        )
                    )
                ),
                signature
            )
        ) {
            revert();
        }
        _;
    }

    constructor(address _owner) Ownable(_owner) EIP712("Arcade", "1") {}

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

    function coin(Puzzle calldata puzzle, bytes calldata signature, uint256 toll)
        external
        validatePuzzle(puzzle, signature)
    {
        // Collect toll from player.
        uint256 available = availableBalanceOf[puzzle.currency][msg.sender];
        if (toll > available) {
            IERC20(puzzle.currency).transferFrom(msg.sender, address(this), toll - available);
            availableBalanceOf[puzzle.currency][msg.sender] = 0;
        } else {
            availableBalanceOf[puzzle.currency][msg.sender] -= toll;
        }

        uint256 protocolFee = toll * fee / FEE_PRECISION;
        availableBalanceOf[puzzle.currency][owner()] += protocolFee;
        availableBalanceOf[puzzle.currency][puzzle.creator] += toll - protocolFee;

        bytes32 puzzleId = keccak256(abi.encode(puzzle));

        // Make sure same game isn't created twice. Also checking if someone else is playing.
        if (statusOf[puzzleId] != 0) {
            revert();
        }

        // Handle reward. Lock reward amount.
        uint256 reward = IRewardPolicy(puzzle.rewardPolicy).reward(toll, puzzle.rewardData);
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
        address player;
        assembly {
            player := shr(96, status)
        }

        // Make sure game has expired or it's being initiated by the player.
        if (uint96(block.timestamp) > uint96(status) && msg.sender != player) {
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
        uint256 protocolFee = reward * fee / FEE_PRECISION;
        lockedBalanceOf[puzzle.currency][puzzle.creator] -= reward;
        availableBalanceOf[puzzle.currency][owner()] += protocolFee;
        availableBalanceOf[puzzle.currency][player] += reward - protocolFee;
    }

    function invalidate(Puzzle calldata puzzle, bytes calldata signature) external validatePuzzle(puzzle, signature) {
        // Make sure the creator is invalidating the puzzle.
        if (msg.sender != puzzle.creator) {
            revert();
        }
        bytes32 puzzleId = keccak256(abi.encode(puzzle));
        // Make sure the game isn't being played.
        if (statusOf[puzzleId] != 0) {
            revert();
        }
        // `coin` and `solve` will revert.
        statusOf[puzzleId] = 1;
    }

    function setFee(uint256 _fee) external onlyOwner {
        if (_fee < FEE_PRECISION) {
            revert();
        }
        fee = _fee;
    }
}
