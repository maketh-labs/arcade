// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IRewardPolicy} from "./interfaces/IRewardPolicy.sol";

contract ShootPolicy is IRewardPolicy {
    function escrow(uint256 toll, address, bytes calldata data) external pure returns (uint256 amount) {
        (uint256 tollMinimum, uint256 tollMaximum) = abi.decode(data, (uint256, uint256));
        if (toll < tollMinimum || toll > tollMaximum) {
            revert("ShootPolicy: toll is out of range");
        }
        return 0;
    }

    function payout(uint256, bytes32) external pure returns (uint256) {
        return 0;
    }
}
