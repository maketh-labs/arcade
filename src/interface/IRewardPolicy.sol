// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IRewardPolicy {
    function reward(uint256 toll, bytes calldata data) external returns (uint256 amount);
}
