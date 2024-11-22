// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IRewardPolicy} from "./interfaces/IRewardPolicy.sol";

contract MulRewardPolicy is IRewardPolicy {
    uint256 public constant PRECISION = 100_000;

    function escrow(uint256 toll, address, bytes calldata data) external pure returns (uint256 amount) {
        (uint256 multiple, uint256 tollMinimum, uint256 tollMaximum) = abi.decode(data, (uint256, uint256, uint256));
        if (multiple <= PRECISION) {
            revert("MulRewardPolicy: multiple must be greater than 1");
        }
        if (toll < tollMinimum || toll > tollMaximum) {
            revert("MulRewardPolicy: toll is out of range");
        }
        amount = toll * multiple / PRECISION;
    }

    function payout(uint256 max, bytes32 payoutData) external pure returns (uint256) {
        return max * uint256(payoutData) / PRECISION;
    }
}
