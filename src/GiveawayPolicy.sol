// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IRewardPolicy} from "./interface/IRewardPolicy.sol";

contract GiveawayPolicy is IRewardPolicy {
    function reward(uint256 toll, bytes calldata rewardData) external pure returns (uint256) {
        if (toll != 0) {
            revert("GiveawayPolicy: Toll must be zero");
        }
        return abi.decode(rewardData, (uint256));
    }
}
