// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {MulRewardPolicy} from "../src/MulRewardPolicy.sol";

contract MulRewardPolicyTest is Test {
    MulRewardPolicy public policy;

    function setUp() public {
        policy = new MulRewardPolicy();
    }

    function testEscrow() public {
        bytes memory data = abi.encode(2 * policy.PRECISION(), 0.1 ether, 1 ether);
        uint256 amount = policy.escrow(0.1 ether, data);
        assertEq(amount, 0.2 ether);

        vm.expectRevert("MulRewardPolicy: toll is out of range");
        policy.escrow(0.09 ether, data);

        vm.expectRevert("MulRewardPolicy: toll is out of range");
        policy.escrow(1.01 ether, data);

        bytes memory invalidData = abi.encode(1 * policy.PRECISION(), 0.1 ether, 1 ether);
        vm.expectRevert("MulRewardPolicy: multiple must be greater than 1");
        policy.escrow(0.1 ether, invalidData);
    }

    function testPayout() public {
        bytes memory data = abi.encode(2 * policy.PRECISION(), 0.1 ether, 1 ether);
        uint256 amount = policy.escrow(0.1 ether, data);
        assertEq(policy.payout(amount, bytes32(0)), 0);
        assertEq(policy.payout(amount, bytes32(uint256(1))), amount / policy.PRECISION());
        assertEq(policy.payout(amount, bytes32(policy.PRECISION() / 2)), amount / 2);
        assertEq(policy.payout(amount, bytes32(policy.PRECISION() * 3 / 4)), amount * 3 / 4);
        assertEq(policy.payout(amount, bytes32(policy.PRECISION() * 9 / 10)), amount * 9 / 10);
        assertEq(policy.payout(amount, bytes32(policy.PRECISION())), amount);
        assertEq(policy.payout(amount, bytes32(policy.PRECISION() * 11 / 10)), amount * 11 / 10);
    }
}
