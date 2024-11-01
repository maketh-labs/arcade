// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IRewardPolicy {
    // The maximum amount that can be paid out.
    function escrow(uint256 toll, bytes calldata data) external returns (uint256 amount);
    // The actual amount that will be paid out.
    function payout(uint256 reward, bytes32 data) external returns (uint256 amount);
}
