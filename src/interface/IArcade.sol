// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

interface IArcade {
    // @notice Puzzles are created via intents.
    struct Puzzle {
        address creator;
        bytes32 problem;
        bytes32 answer;
        uint96 timeLimit;
        address currency;
        address rewardPolicy;
        bytes rewardData;
    }

    function balance(address currency, address user) external view returns (uint256 available, uint256 locked);
    function deposit(address currency, address user, uint256 amount) external;
    function withdraw(address currency, uint256 amount) external;
    function lock(Puzzle calldata puzzle, bytes calldata signature, uint256 toll, bytes calldata data) external;
    function expire(Puzzle calldata puzzle, bytes calldata signature) external;
    function solve(Puzzle calldata puzzle, bytes calldata signature, uint256 solution) external;
}
