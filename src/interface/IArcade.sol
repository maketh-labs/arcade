// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IArcade {
    event Deposit(address user, address currency, uint256 amount);
    event Withdraw(address user, address currency, uint256 amount);
    event Coin(
        bytes32 puzzleId,
        address creator,
        address player,
        uint256 toll,
        uint256 escrow,
        uint96 expiryTimestamp,
        address currency
    );
    event Expire(bytes32 puzzleId);
    event Solve(bytes32 puzzleId, uint256 payout);
    event Invalidate(bytes32 puzzleId);
    event CreatorFeeUpdated(uint256 oldFee, uint256 newFee);
    event PayoutFeeUpdated(uint256 oldFee, uint256 newFee);

    // @notice Puzzles are created via intents.
    struct Puzzle {
        address creator;
        address answer;
        uint32 lives;
        uint64 timeLimit;
        address currency;
        uint96 deadline;
        address rewardPolicy;
        bytes rewardData;
    }

    function balance(address currency, address user) external view returns (uint256 available, uint256 locked);
    function deposit(address currency, address user, uint256 amount) external;
    function depositETH(address user, uint256 amount) external payable;
    function withdraw(address currency, uint256 amount) external;
    function withdrawETH(uint256 amount) external;
    function coin(Puzzle calldata puzzle, bytes calldata signature, uint256 toll) external payable;
    function expire(Puzzle calldata puzzle) external payable returns (bool success);
    function solve(Puzzle calldata puzzle, bytes32 payoutData, bytes calldata payoutSignature) external;
    function invalidate(Puzzle calldata puzzle) external;
}
