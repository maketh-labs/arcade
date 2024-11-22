// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IRewardPolicy} from "./interfaces/IRewardPolicy.sol";

contract GiveawayPolicy is IRewardPolicy {
    function escrow(uint256 toll, address player, bytes calldata rewardData) external pure returns (uint256) {
        if (toll != 0) {
            revert("GiveawayPolicy: Toll must be zero");
        }

        (address whitelistedPlayer, uint256 amount) = abi.decode(rewardData, (address, uint256));
        if (player != whitelistedPlayer) {
            revert("GiveawayPolicy: Player must be whitelisted");
        }
        return amount;
    }

    function payout(uint256 max, bytes32) external pure returns (uint256) {
        return max;
    }
}
