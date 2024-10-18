// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {MulRewardPolicy} from "../src/MulRewardPolicy.sol";

contract MulRewardPolicyTest is Test {
    MulRewardPolicy public policy;

    function setUp() public {
        policy = new MulRewardPolicy();
    }

    function testReward() public {
        bytes memory data = abi.encode(2 * policy.PRECISION(), 0.1 ether, 1 ether);
        uint256 amount = policy.reward(0.1 ether, data);
        assertEq(amount, 0.2 ether);

        vm.expectRevert("MulRewardPolicy: toll is out of range");
        policy.reward(0.09 ether, data);

        vm.expectRevert("MulRewardPolicy: toll is out of range");
        policy.reward(1.01 ether, data);

        bytes memory invalidData = abi.encode(1 * policy.PRECISION(), 0.1 ether, 1 ether);
        vm.expectRevert("MulRewardPolicy: multiple must be greater than 1");
        policy.reward(0.1 ether, invalidData);
    }
}
