// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "forge-std/mocks/MockERC20.sol";
import {stdError} from "forge-std/StdError.sol";
import {Arcade} from "../src/Arcade.sol";

contract Token is MockERC20 {
    constructor() {
        initialize("Arcade", "ARC", 18);
    }

    function mint(address to, uint256 value) public virtual {
        _mint(to, value);
    }

    function burn(address from, uint256 value) public virtual {
        _burn(from, value);
    }
}

contract ArcadeTest is Test {
    Arcade public arcade;
    Token public token;

    address public gamer1 = makeAddr("1");

    function setUp() public {
        arcade = new Arcade();
        token = new Token();
    }

    function testDeposit() public {
        (uint256 available, uint256 locked) = _deposit(address(token), gamer1, 1 ether);
        assertEq(locked, 0);

        // Deposit some more
        (available, locked) = _deposit(address(token), gamer1, 0.1 ether);
        (available, locked) = _deposit(address(token), gamer1, 0.2 ether);
    }

    function testWithdraw() public {
        _deposit(address(token), gamer1, 1 ether);
        _withdraw(address(token), gamer1, 1 ether);
        vm.expectRevert(stdError.arithmeticError);
        vm.prank(gamer1);
        arcade.withdraw(address(token), 1 ether);
    }

    function _deposit(address currency, address gamer, uint256 amount)
        private
        returns (uint256 available, uint256 locked)
    {
        (uint256 prevAvailable, uint256 prevLocked) = arcade.balance(currency, gamer);
        token.mint(gamer, amount);
        vm.startPrank(gamer);
        token.approve(address(arcade), amount);
        arcade.deposit(currency, gamer, amount);
        vm.stopPrank();
        (available, locked) = arcade.balance(currency, gamer);
        assertEq(available, prevAvailable + amount);
        assertEq(locked, prevLocked);
    }

    function _withdraw(address currency, address gamer, uint256 amount)
        private
        returns (uint256 available, uint256 locked)
    {
        (uint256 prevAvailable, uint256 prevLocked) = arcade.balance(currency, gamer);
        vm.prank(gamer);
        arcade.withdraw(currency, amount);
        (available, locked) = arcade.balance(currency, gamer);
        assertEq(available, prevAvailable - amount);
        assertEq(locked, prevLocked);
    }
}
