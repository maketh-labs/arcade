// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable, Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Multicall} from "@openzeppelin/contracts/utils/Multicall.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import {IArcade} from "./interface/IArcade.sol";
import {IRewardPolicy} from "./interface/IRewardPolicy.sol";
import {IWETH} from "./interface/IWETH.sol";

contract Arcade is IArcade, Ownable2Step, Multicall, EIP712 {
    using SafeERC20 for IERC20;

    address public immutable WETH;
    uint256 public constant FEE_PRECISION = 100000;
    bytes32 public constant PUZZLE_TYPEHASH = keccak256(
        "Puzzle(address creator,bytes32 problem,bytes32 answer,uint32 lives,uint64 timeLimit,address currency,uint96 deadline,address rewardPolicy,bytes rewardData)"
    );
    uint256 private constant INVALIDATED = type(uint256).max;

    uint256 public creatorFee = 1000; // Initial fee 100 bps. Paid by creator from the toll.
    uint256 public rewardFee = 4000; // Initial fee 400 bps. Paid by player from the reward.
    mapping(address currency => mapping(address user => uint256)) public availableBalanceOf;
    mapping(address currency => mapping(address user => uint256)) public lockedBalanceOf;
    mapping(bytes32 puzzleId => uint256) public statusOf; // player (160) + plays (32) + expiry timestamp (64)
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
                            puzzle.lives,
                            puzzle.timeLimit,
                            puzzle.currency,
                            puzzle.deadline,
                            puzzle.rewardPolicy,
                            keccak256(puzzle.rewardData)
                        )
                    )
                ),
                signature
            )
        ) {
            revert("Arcade: Invalid puzzle");
        }
        _;
    }

    constructor(address _owner, address _weth) Ownable(_owner) EIP712("Arcade", "1") {
        WETH = _weth;
    }

    function balance(address currency, address user) external view returns (uint256 available, uint256 locked) {
        available = availableBalanceOf[currency][user];
        locked = lockedBalanceOf[currency][user];
    }

    function deposit(address currency, address user, uint256 amount) external {
        IERC20(currency).safeTransferFrom(msg.sender, address(this), amount);
        availableBalanceOf[currency][user] += amount;
        emit Deposit(user, currency, amount);
    }

    function depositETH(address user) external payable {
        IWETH(WETH).deposit{value: msg.value}();
        availableBalanceOf[WETH][user] += msg.value;
        emit Deposit(user, WETH, msg.value);
    }

    receive() external payable {
        require(msg.sender == WETH, "Arcade: Not WETH");
    }

    function withdraw(address currency, uint256 amount) external {
        availableBalanceOf[currency][msg.sender] -= amount;
        IERC20(currency).safeTransfer(msg.sender, amount);
        emit Withdraw(msg.sender, currency, amount);
    }

    function withdrawETH(uint256 amount) external {
        availableBalanceOf[WETH][msg.sender] -= amount;
        IWETH(WETH).withdraw(amount);
        (bool success,) = msg.sender.call{value: amount}("");
        require(success, "Arcade: ETH transfer failed");
        emit Withdraw(msg.sender, WETH, amount);
    }

    function coin(Puzzle calldata puzzle, bytes calldata signature, uint256 toll)
        external
        validatePuzzle(puzzle, signature)
    {
        bytes32 puzzleId = keccak256(abi.encode(puzzle));

        // Make sure same game isn't created twice. Also checking if someone else is playing.
        uint256 status = statusOf[puzzleId];
        address player;
        uint32 plays;
        assembly {
            player := shr(96, status)
            plays := shr(64, status)
        }
        if (status == INVALIDATED) {
            revert("Arcade: Puzzle invalidated");
        }
        if (player != address(0)) {
            revert("Arcade: Puzzle being played");
        }
        if (uint96(block.timestamp) > puzzle.deadline) {
            revert("Arcade: Puzzle deadline exceeded");
        }

        address currency = puzzle.currency;
        // Collect toll from player.
        {
            uint256 available = availableBalanceOf[currency][msg.sender];
            if (toll > available) {
                IERC20(currency).transferFrom(msg.sender, address(this), toll - available);
                availableBalanceOf[currency][msg.sender] = 0;
            } else {
                availableBalanceOf[currency][msg.sender] -= toll;
            }
        }

        {
            uint256 protocolFee = toll * creatorFee / FEE_PRECISION;
            availableBalanceOf[currency][owner()] += protocolFee;
            availableBalanceOf[currency][puzzle.creator] += toll - protocolFee;
        }

        // Handle reward. Lock reward amount.
        uint256 reward = IRewardPolicy(puzzle.rewardPolicy).reward(toll, puzzle.rewardData);
        rewardOf[puzzleId] = reward;
        availableBalanceOf[currency][puzzle.creator] -= reward;
        lockedBalanceOf[currency][puzzle.creator] += reward;

        // Handle status. Pack player, plays, and expiry timestamp.
        player = msg.sender;
        uint64 expiryTimestamp = uint64(block.timestamp) + puzzle.timeLimit;
        {
            assembly {
                status := add(shl(96, player), add(shl(64, plays), expiryTimestamp))
            }
            statusOf[puzzleId] = status;
        }
        emit Coin(puzzleId, puzzle.creator, player, toll, reward, expiryTimestamp, currency);
    }

    function expire(Puzzle calldata puzzle) external {
        bytes32 puzzleId = keccak256(abi.encode(puzzle));
        uint256 status = statusOf[puzzleId];
        address player;
        uint32 plays;
        if (status == INVALIDATED) {
            revert("Arcade: Puzzle invalidated");
        }
        assembly {
            player := shr(96, status)
            plays := add(shr(64, status), 1)
        }
        if (player == address(0)) {
            revert("Arcade: Puzzle not being played");
        }

        // Make sure game has expired or it's being initiated by the player.
        if (uint64(status) > uint64(block.timestamp) && msg.sender != player) {
            revert("Arcade: Only player can expire the puzzle before expiry");
        }

        if (plays < puzzle.lives) {
            statusOf[puzzleId] = uint256(plays) << 64;
        } else {
            statusOf[puzzleId] = INVALIDATED;
        }

        // Unfreeze assets.
        uint256 reward = rewardOf[puzzleId];
        lockedBalanceOf[puzzle.currency][puzzle.creator] -= reward;
        availableBalanceOf[puzzle.currency][puzzle.creator] += reward;

        emit Expire(puzzleId);
    }

    function solve(Puzzle calldata puzzle, bytes32 solution) external {
        bytes32 puzzleId = keccak256(abi.encode(puzzle));
        uint256 status = statusOf[puzzleId];
        if (status == INVALIDATED) {
            revert("Arcade: Puzzle invalidated");
        }

        // Make sure game hasn't expired.
        if (uint64(block.timestamp) > uint64(status)) {
            revert("Arcade: Puzzle has expired");
        }

        address player;
        assembly {
            player := shr(96, status)
        }

        // Invalidate the puzzle
        statusOf[puzzleId] = INVALIDATED;

        // Make sure the player is solving the puzzle.
        if (player != msg.sender) {
            revert("Arcade: Only player can solve the puzzle");
        }

        // Make sure the solution is correct.
        if (puzzle.answer != keccak256(abi.encode(puzzle.problem, solution))) {
            revert("Arcade: Incorrect solution");
        }

        // Settle reward.
        uint256 reward = rewardOf[puzzleId];
        uint256 protocolFee = reward * rewardFee / FEE_PRECISION;
        lockedBalanceOf[puzzle.currency][puzzle.creator] -= reward;
        availableBalanceOf[puzzle.currency][owner()] += protocolFee;
        availableBalanceOf[puzzle.currency][player] += reward - protocolFee;

        emit Solve(puzzleId, reward);
    }

    function invalidate(Puzzle calldata puzzle) external {
        // Make sure the creator is invalidating the puzzle.
        if (msg.sender != puzzle.creator) {
            revert("Arcade: Only creator can invalidate the puzzle");
        }
        bytes32 puzzleId = keccak256(abi.encode(puzzle));
        // Make sure the game isn't being played.
        if (statusOf[puzzleId] != 0) {
            revert("Arcade: Puzzle already coined");
        }
        // `coin` and `solve` will revert.
        statusOf[puzzleId] = INVALIDATED;

        emit Invalidate(puzzleId);
    }

    function setCreatorFee(uint256 _newFee) external onlyOwner {
        if (_newFee > FEE_PRECISION) {
            revert("Arcade: Fee cannot be greater than or equal to 100%");
        }
        uint256 oldFee = creatorFee;
        creatorFee = _newFee;
        emit CreatorFeeUpdated(oldFee, _newFee);
    }

    function setRewardFee(uint256 _newFee) external onlyOwner {
        if (_newFee > FEE_PRECISION) {
            revert("Arcade: Fee cannot be greater than or equal to 100%");
        }
        uint256 oldFee = rewardFee;
        rewardFee = _newFee;
        emit RewardFeeUpdated(oldFee, _newFee);
    }
}
