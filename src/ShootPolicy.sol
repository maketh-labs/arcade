// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IRewardPolicy} from "./interfaces/IRewardPolicy.sol";

contract ShootPolicy is IRewardPolicy {
    function escrow(uint256, address, bytes calldata) external pure returns (uint256 amount) {
        return 0;
    }

    function payout(uint256, bytes32) external pure returns (uint256) {
        return 0;
    }
}
