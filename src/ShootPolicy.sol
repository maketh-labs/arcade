// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IRewardPolicy} from "./interfaces/IRewardPolicy.sol";

contract ShootPolicy is IRewardPolicy {
    function escrow(uint256 toll, address, bytes calldata data) external pure returns (uint256 amount) {
        return 0;
    }

    function payout(uint256 max, bytes32 payoutData) external pure returns (uint256) {
        return 0;
    }
}
