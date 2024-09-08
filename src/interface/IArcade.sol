// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

interface IArcade {
    // @notice Puzzles are created via intents. Derive creator through `ecrecover`.
    struct Puzzle {
        bytes32 problem;
        bytes32 answer;
        address rewardPolicy;
        uint96 timeLimit;
    }

    struct Signature {
        address signer;
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    function deposit(address currency, address user, uint256 amount) external;
    function withdraw(address currency, address user, uint256 amount) external;
    function lock(Puzzle calldata puzzle, Signature calldata signature, uint256 toll) external;
    function unlock(Puzzle calldata puzzle, Signature calldata signature) external;
    function solve(Puzzle calldata puzzle, Signature calldata signature, uint256 solution) external;
}
