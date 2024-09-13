// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "forge-std/mocks/MockERC20.sol";
import {stdError} from "forge-std/StdError.sol";
import {Arcade, IArcade} from "../src/Arcade.sol";
import {MulRewardPolicy} from "../src/MulRewardPolicy.sol";

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
    address public rewardPolicy;

    address public protocol = makeAddr("protocol");
    address public creator;
    uint256 public creatorPrivateKey;
    address public gamer1 = makeAddr("1");

    function setUp() public {
        arcade = new Arcade(protocol);
        token = new Token();
        rewardPolicy = address(new MulRewardPolicy());
        (creator, creatorPrivateKey) = makeAddrAndKey("creator");
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

    function testCoin() public {
        uint256 amount = 1 ether;
        uint256 toll = 0.1 ether;
        token.mint(creator, amount);
        vm.startPrank(creator);
        token.approve(address(arcade), amount);
        arcade.deposit(address(token), creator, amount);
        vm.stopPrank();
        token.mint(gamer1, toll);
        vm.prank(gamer1);
        token.approve(address(arcade), toll);

        bytes32 problem = keccak256("What is 2+2?");
        bytes32 solution = keccak256(abi.encode(4));
        bytes32 answer = keccak256(abi.encode(problem, solution));

        IArcade.Puzzle memory puzzle = IArcade.Puzzle({
            creator: creator,
            problem: problem,
            answer: answer,
            timeLimit: 3600,
            currency: address(token),
            rewardPolicy: rewardPolicy,
            rewardData: abi.encode(3 * 100_000, 0.1 ether, 0.2 ether)
        });

        bytes memory signature = _signPuzzle(puzzle);

        vm.prank(gamer1);
        arcade.coin(puzzle, signature, toll);

        (uint256 creatorAvailable, uint256 creatorLocked) = arcade.balance(address(token), creator);
        uint256 protocolFee = toll / 100;
        assertEq(creatorAvailable, amount + toll - toll * 3 - protocolFee);
        assertEq(creatorLocked, toll * 3);
    }

    function _deposit(address currency, address gamer, uint256 amount)
        internal
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
        internal
        returns (uint256 available, uint256 locked)
    {
        (uint256 prevAvailable, uint256 prevLocked) = arcade.balance(currency, gamer);
        vm.prank(gamer);
        arcade.withdraw(currency, amount);
        (available, locked) = arcade.balance(currency, gamer);
        assertEq(available, prevAvailable - amount);
        assertEq(locked, prevLocked);
    }

    function _getDomainSeparator() internal view returns (bytes32) {
        return keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes("Arcade")),
                keccak256(bytes("1")),
                block.chainid,
                address(arcade)
            )
        );
    }

    function _signPuzzle(IArcade.Puzzle memory puzzle) internal view returns (bytes memory) {
        bytes32 domainSeparator = _getDomainSeparator();
        bytes32 structHash = keccak256(
            abi.encode(
                arcade.PUZZLE_TYPEHASH(),
                puzzle.creator,
                puzzle.problem,
                puzzle.answer,
                puzzle.timeLimit,
                puzzle.currency,
                puzzle.rewardPolicy,
                keccak256(puzzle.rewardData)
            )
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(creatorPrivateKey, digest);
        return abi.encodePacked(r, s, v);
    }
}
