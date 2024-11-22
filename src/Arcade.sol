// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IArcade} from "./interfaces/IArcade.sol";
import {Ownable, Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Multicall4} from "./Multicall4.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IRewardPolicy} from "./interfaces/IRewardPolicy.sol";
import {IWETH} from "./interfaces/IWETH.sol";
import {IVerifySig} from "./interfaces/IVerifySig.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract Arcade is IArcade, Ownable2Step, Multicall4, EIP712 {
    using SafeERC20 for IERC20;

    address public immutable WETH;
    address public immutable VERIFY_SIG;
    uint256 public constant FEE_PRECISION = 100000;
    bytes32 public constant PUZZLE_TYPEHASH = keccak256(
        "Puzzle(address creator,address answer,uint32 lives,uint64 timeLimit,address currency,uint96 deadline,address rewardPolicy,bytes rewardData)"
    );
    bytes32 public constant PAYOUT_TYPEHASH = keccak256("Payout(bytes32 puzzleId,address solver,bytes32 payoutData)");
    uint256 private constant INVALIDATED = type(uint256).max;

    uint256 public creatorFee = 1000; // Initial fee 100 bps. Paid by creator from the toll.
    uint256 public payoutFee = 4000; // Initial fee 400 bps. Paid by player from the payout.
    mapping(address currency => mapping(address user => uint256)) public availableBalanceOf;
    mapping(address currency => mapping(address user => uint256)) public lockedBalanceOf;
    mapping(bytes32 puzzleId => uint256) public statusOf; // player (160) + plays (32) + expiry timestamp (64)
    mapping(bytes32 puzzleId => uint256) public escrowOf;

    modifier validatePuzzle(Puzzle calldata puzzle, bytes calldata signature) {
        if (
            !IVerifySig(VERIFY_SIG).isValidSig(
                puzzle.creator,
                _hashTypedDataV4(
                    keccak256(
                        abi.encode(
                            PUZZLE_TYPEHASH,
                            puzzle.creator,
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

    constructor(address _owner, address _weth, address _verifySig) Ownable(_owner) EIP712("Arcade", "1") {
        WETH = _weth;
        VERIFY_SIG = _verifySig;
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

    function depositETH(address user, uint256 amount) external payable {
        IWETH(WETH).deposit{value: amount}();
        availableBalanceOf[WETH][user] += amount;
        emit Deposit(user, WETH, amount);
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
        payable
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
        if (puzzle.lives == 0) {
            revert("Arcade: Puzzle lives cannot be 0");
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
        uint256 escrow = IRewardPolicy(puzzle.rewardPolicy).escrow(toll, puzzle.rewardData);
        escrowOf[puzzleId] = escrow;
        availableBalanceOf[currency][puzzle.creator] -= escrow;
        lockedBalanceOf[currency][puzzle.creator] += escrow;

        // Handle status. Pack player, plays, and expiry timestamp.
        player = msg.sender;
        uint64 expiryTimestamp = uint64(block.timestamp) + puzzle.timeLimit;
        {
            assembly {
                status := add(shl(96, player), add(shl(64, plays), expiryTimestamp))
            }
            statusOf[puzzleId] = status;
        }
        emit Coin(puzzleId, puzzle.creator, player, toll, escrow, expiryTimestamp, currency);
    }

    function expire(Puzzle calldata puzzle) external payable returns (bool success) {
        bytes32 puzzleId = keccak256(abi.encode(puzzle));
        uint256 status = statusOf[puzzleId];
        address player;
        uint32 plays;
        if (status == INVALIDATED) {
            return false;
        }
        assembly {
            player := shr(96, status)
            plays := add(shr(64, status), 1)
        }
        if (player == address(0)) {
            return false;
        }

        // Make sure game has expired or it's being initiated by the player.
        if (uint64(status) > uint64(block.timestamp) && msg.sender != player) {
            return false;
        }

        if (plays < puzzle.lives) {
            statusOf[puzzleId] = uint256(plays) << 64;
        } else {
            statusOf[puzzleId] = INVALIDATED;
        }

        // Unfreeze assets.
        uint256 escrow = escrowOf[puzzleId];
        lockedBalanceOf[puzzle.currency][puzzle.creator] -= escrow;
        availableBalanceOf[puzzle.currency][puzzle.creator] += escrow;

        emit Expire(puzzleId);
        return true;
    }

    function solve(Puzzle calldata puzzle, bytes32 payoutData, bytes calldata payoutSignature) external {
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

        // Make sure the solution is correct. Use EIP-712 domain separator.
        if (
            !IVerifySig(VERIFY_SIG).isValidSig(
                puzzle.answer,
                _hashTypedDataV4(keccak256(abi.encode(PAYOUT_TYPEHASH, puzzleId, player, payoutData))),
                payoutSignature
            )
        ) {
            revert("Arcade: Incorrect solution");
        }

        // Settle reward.
        uint256 escrow = escrowOf[puzzleId];
        uint256 payout = IRewardPolicy(puzzle.rewardPolicy).payout(escrow, payoutData);
        if (escrow < payout) {
            revert("Arcade: Payout is greater than escrow");
        }
        uint256 protocolFee = payout * payoutFee / FEE_PRECISION;
        lockedBalanceOf[puzzle.currency][puzzle.creator] -= escrow;
        availableBalanceOf[puzzle.currency][owner()] += protocolFee;
        availableBalanceOf[puzzle.currency][puzzle.creator] += escrow - payout;
        availableBalanceOf[puzzle.currency][player] += payout - protocolFee;

        emit Solve(puzzleId, payout);
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
        if (_newFee > FEE_PRECISION / 20) {
            revert("Arcade: Fee cannot be greater than 5%");
        }
        uint256 oldFee = creatorFee;
        creatorFee = _newFee;
        emit CreatorFeeUpdated(oldFee, _newFee);
    }

    function setPayoutFee(uint256 _newFee) external onlyOwner {
        if (_newFee > FEE_PRECISION / 20) {
            revert("Arcade: Fee cannot be greater than 5%");
        }
        uint256 oldFee = payoutFee;
        payoutFee = _newFee;
        emit PayoutFeeUpdated(oldFee, _newFee);
    }
}
