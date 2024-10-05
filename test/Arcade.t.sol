// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "forge-std/mocks/MockERC20.sol";
import {stdError} from "forge-std/StdError.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {Arcade, IArcade} from "../src/Arcade.sol";
import {MulRewardPolicy} from "../src/MulRewardPolicy.sol";
import {GiveawayPolicy} from "../src/GiveawayPolicy.sol";
import {WETH9} from "../src/WETH9.sol";

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
    address public weth;
    address public rewardPolicy;
    address public giveawayPolicy;

    address public protocol = makeAddr("protocol");
    address public creator;
    uint256 public creatorPrivateKey;
    address public gamer1 = makeAddr("1");
    address public gamer2 = makeAddr("2");

    function setUp() public {
        weth = address(new WETH9());
        arcade = new Arcade(protocol, weth);
        token = new Token();
        rewardPolicy = address(new MulRewardPolicy());
        giveawayPolicy = address(new GiveawayPolicy());
        (creator, creatorPrivateKey) = makeAddrAndKey("creator");

        _deposit(address(token), creator, 100_000_000 ether);
    }

    function testDeposit() public {
        (uint256 available, uint256 locked) = _deposit(address(token), gamer1, 1 ether);
        assertEq(locked, 0);

        // Deposit some more
        (available, locked) = _deposit(address(token), gamer1, 0.1 ether);
        (available, locked) = _deposit(address(token), gamer1, 0.2 ether);
    }

    function testDepositWithdrawETH() public {
        vm.deal(gamer1, 1 ether);
        vm.prank(gamer1);
        arcade.depositETH{value: 1 ether}(gamer1);
        (uint256 available, uint256 locked) = arcade.balance(weth, gamer1);
        assertEq(available, 1 ether);
        assertEq(locked, 0);

        assertEq(gamer1.balance, 0);
        vm.prank(gamer1);
        arcade.withdrawETH(1 ether);
        assertEq(gamer1.balance, 1 ether);
    }

    function testWithdraw() public {
        _deposit(address(token), gamer1, 1 ether);
        _withdraw(address(token), gamer1, 1 ether);
        vm.expectRevert(stdError.arithmeticError);
        vm.prank(gamer1);
        arcade.withdraw(address(token), 1 ether);
    }

    function testCoin() public {
        /// Pay with token transfer.
        // Setup.
        (uint256 prevCreatorAvailable, uint256 prevCreatorLocked) = arcade.balance(address(token), creator);

        (IArcade.Puzzle memory puzzle, bytes memory signature, bytes32 solution) =
            _createPuzzle(300_000, 0.1 ether, 0.2 ether);

        uint256 toll = 0.1 ether;
        uint256 protocolFee = toll / 100;
        token.mint(gamer1, toll);
        vm.startPrank(gamer1);
        token.approve(address(arcade), toll);
        arcade.coin(puzzle, signature, toll);
        vm.stopPrank();

        (uint256 creatorAvailable, uint256 creatorLocked) = arcade.balance(address(token), creator);
        (uint256 gamerAvailable, uint256 gamerLocked) = arcade.balance(address(token), gamer1);

        assertEq(creatorAvailable, prevCreatorAvailable + toll - protocolFee - toll * 3, "Creator available 1");
        assertEq(creatorLocked, prevCreatorLocked + toll * 3, "Creator locked 1");
        assertEq(gamerAvailable, 0, "Gamer available 1");
        assertEq(gamerLocked, 0, "Gamer locked 1");

        /// Pay with deposits.
        (prevCreatorAvailable, prevCreatorLocked) = arcade.balance(address(token), creator);

        (puzzle, signature, solution) = _createPuzzle(300_000, 0.1 ether, 0.2 ether);

        toll = 0.2 ether;
        protocolFee = toll / 100;
        _deposit(address(token), gamer1, 0.3 ether);
        vm.startPrank(gamer1);
        token.approve(address(arcade), toll);
        arcade.coin(puzzle, signature, toll);
        vm.stopPrank();

        (creatorAvailable, creatorLocked) = arcade.balance(address(token), creator);
        (gamerAvailable, gamerLocked) = arcade.balance(address(token), gamer1);

        assertEq(creatorAvailable, prevCreatorAvailable + toll - protocolFee - toll * 3, "Creator available 2");
        assertEq(creatorLocked, prevCreatorLocked + toll * 3, "Creator locked 2");
        assertEq(gamerAvailable, 0.1 ether, "Gamer available 2");
        assertEq(gamerLocked, 0, "Gamer locked 2");

        /// Pay with a mix of both.
        (prevCreatorAvailable, prevCreatorLocked) = arcade.balance(address(token), creator);
        (puzzle, signature, solution) = _createPuzzle(300_000, 0.1 ether, 0.2 ether);

        toll = 0.15 ether;
        protocolFee = toll / 100;
        token.mint(gamer1, 0.05 ether);
        vm.startPrank(gamer1);
        token.approve(address(arcade), toll);
        arcade.coin(puzzle, signature, toll);
        vm.stopPrank();

        (creatorAvailable, creatorLocked) = arcade.balance(address(token), creator);
        (gamerAvailable, gamerLocked) = arcade.balance(address(token), gamer1);

        assertEq(creatorAvailable, prevCreatorAvailable + toll - protocolFee - toll * 3, "Creator available 3");
        assertEq(creatorLocked, prevCreatorLocked + toll * 3, "Creator locked 3");
        assertEq(gamerAvailable, 0, "Gamer available 3");
        assertEq(gamerLocked, 0, "Gamer locked 3");
    }

    function testSolve() public {
        (IArcade.Puzzle memory puzzle, bytes memory signature, bytes32 solution) =
            _createPuzzle(300_000, 0.1 ether, 0.2 ether);

        uint256 toll = 0.1 ether;
        uint256 reward = 0.3 ether;
        uint256 protocolFee = reward * 4 / 100;
        token.mint(gamer1, toll);
        vm.startPrank(gamer1);
        token.approve(address(arcade), toll);
        arcade.coin(puzzle, signature, toll);
        arcade.solve(puzzle, solution);
        vm.stopPrank();

        (uint256 gamerAvailable, uint256 gamerLocked) = arcade.balance(address(token), gamer1);
        (, uint256 creatorLocked) = arcade.balance(address(token), creator);

        assertEq(creatorLocked, 0, "Creator should have no locked balance");
        assertEq(gamerAvailable, reward - protocolFee, "Gamer should receive reward minus protocol fee");
        assertEq(gamerLocked, 0, "Gamer should have no locked balance");
    }

    function testExpireOutOfLives() public {
        string memory problemText = string(abi.encodePacked("What is it"));
        bytes32 problem = keccak256(bytes(problemText));
        bytes32 solution = keccak256(abi.encode(123456789));
        bytes32 answer = keccak256(abi.encode(problem, solution));

        IArcade.Puzzle memory puzzle = IArcade.Puzzle({
            creator: creator,
            problem: problem,
            answer: answer,
            lives: 2,
            timeLimit: 3600,
            currency: address(token),
            deadline: uint96(block.timestamp + 3600),
            rewardPolicy: rewardPolicy,
            rewardData: abi.encode(300_000, 0.1 ether, 0.2 ether)
        });

        bytes memory signature = _signPuzzle(puzzle);

        (uint256 prevCreatorAvailable, uint256 prevCreatorLocked) = arcade.balance(address(token), creator);

        uint256 toll = 0.1 ether;
        token.mint(gamer1, toll * 3);
        vm.startPrank(gamer1);
        token.approve(address(arcade), toll * 3);
        arcade.coin(puzzle, signature, toll);
        arcade.expire(puzzle);
        arcade.coin(puzzle, signature, toll);
        arcade.expire(puzzle);
        vm.expectRevert("Arcade: Puzzle invalidated");
        arcade.coin(puzzle, signature, toll);
        vm.stopPrank();

        uint256 protocolFee = toll / 100;
        (uint256 gamerAvailable, uint256 gamerLocked) = arcade.balance(address(token), gamer1);
        assertEq(gamerAvailable, 0);
        assertEq(gamerLocked, 0);
        (uint256 creatorAvailable, uint256 creatorLocked) = arcade.balance(address(token), creator);
        assertEq(creatorAvailable, prevCreatorAvailable + (toll - protocolFee) * 2);
        assertEq(creatorLocked, prevCreatorLocked);
    }

    function testDuplicateCoin() public {
        (IArcade.Puzzle memory puzzle, bytes memory signature,) = _createPuzzle(300_000, 0.1 ether, 0.2 ether);

        uint256 toll = 0.1 ether;
        token.mint(gamer1, toll * 2);
        vm.startPrank(gamer1);
        token.approve(address(arcade), toll * 2);
        arcade.coin(puzzle, signature, toll);
        vm.expectRevert("Arcade: Puzzle being played");
        arcade.coin(puzzle, signature, toll);
        vm.stopPrank();
    }

    function testDuplicateExpire() public {
        (IArcade.Puzzle memory puzzle1, bytes memory signature1,) = _createPuzzle(300_000, 0.1 ether, 0.2 ether);
        (IArcade.Puzzle memory puzzle2, bytes memory signature2,) = _createPuzzle(300_000, 0.1 ether, 0.2 ether);

        uint256 toll = 0.1 ether;
        token.mint(gamer1, toll * 2);
        vm.startPrank(gamer1);
        token.approve(address(arcade), toll * 2);
        arcade.coin(puzzle1, signature1, toll);
        arcade.coin(puzzle2, signature2, toll);
        arcade.expire(puzzle1);
        vm.expectRevert("Arcade: Puzzle invalidated");
        arcade.expire(puzzle1);
        vm.stopPrank();
    }

    function testDuplicateSolve() public {
        (IArcade.Puzzle memory puzzle, bytes memory signature, bytes32 solution) =
            _createPuzzle(300_000, 0.1 ether, 0.2 ether);

        uint256 toll = 0.1 ether;
        token.mint(gamer1, toll);
        vm.startPrank(gamer1);
        token.approve(address(arcade), toll);
        arcade.coin(puzzle, signature, toll);
        arcade.solve(puzzle, solution);
        vm.expectRevert("Arcade: Puzzle invalidated");
        arcade.solve(puzzle, solution);
        vm.stopPrank();
    }

    function testExpireAfterSolve() public {
        (IArcade.Puzzle memory puzzle, bytes memory signature, bytes32 solution) =
            _createPuzzle(300_000, 0.1 ether, 0.2 ether);

        uint256 toll = 0.1 ether;
        token.mint(gamer1, toll);
        vm.startPrank(gamer1);
        token.approve(address(arcade), toll);
        arcade.coin(puzzle, signature, toll);
        arcade.solve(puzzle, solution);
        vm.expectRevert("Arcade: Puzzle invalidated");
        arcade.expire(puzzle);
        vm.stopPrank();
    }

    function testSolveAfterExpire() public {
        (IArcade.Puzzle memory puzzle, bytes memory signature, bytes32 solution) =
            _createPuzzle(300_000, 0.1 ether, 0.2 ether);

        uint256 toll = 0.1 ether;
        token.mint(gamer1, toll);
        vm.startPrank(gamer1);
        token.approve(address(arcade), toll);
        arcade.coin(puzzle, signature, toll);
        arcade.expire(puzzle);
        vm.expectRevert("Arcade: Puzzle invalidated");
        arcade.solve(puzzle, solution);
        vm.stopPrank();
    }

    function testSolveIncorrect() public {
        (IArcade.Puzzle memory puzzle, bytes memory signature, bytes32 solution) =
            _createPuzzle(300_000, 0.1 ether, 0.2 ether);

        uint256 toll = 0.1 ether;
        token.mint(gamer1, toll);
        vm.startPrank(gamer1);
        token.approve(address(arcade), toll);
        arcade.coin(puzzle, signature, toll);
        // Solve with incorrect solution.
        bytes32 incorrectSolution = keccak256(abi.encode(42));
        vm.expectRevert("Arcade: Incorrect solution");
        arcade.solve(puzzle, incorrectSolution);
        vm.stopPrank();

        // Solve with different player.
        vm.startPrank(gamer2);
        vm.expectRevert("Arcade: Only player can solve the puzzle");
        arcade.solve(puzzle, solution);
        vm.stopPrank();

        // Solve after expiry.
        vm.warp(block.timestamp + 2 hours);
        vm.prank(gamer1);
        vm.expectRevert("Arcade: Puzzle has expired");
        arcade.solve(puzzle, solution);
    }

    function testInvalidate() public {
        (IArcade.Puzzle memory puzzle, bytes memory signature, bytes32 solution) =
            _createPuzzle(300_000, 0.1 ether, 0.2 ether);

        vm.prank(gamer1);
        vm.expectRevert("Arcade: Only creator can invalidate the puzzle");
        arcade.invalidate(puzzle);

        uint256 toll = 0.1 ether;
        token.mint(gamer1, toll);
        vm.startPrank(gamer1);
        token.approve(address(arcade), toll);
        arcade.coin(puzzle, signature, toll);
        vm.stopPrank();

        vm.prank(creator);
        vm.expectRevert("Arcade: Puzzle already coined");
        arcade.invalidate(puzzle);

        (puzzle, signature, solution) = _createPuzzle(300_000, 0.1 ether, 0.2 ether);
        vm.prank(creator);
        arcade.invalidate(puzzle);

        token.mint(gamer1, toll);
        vm.startPrank(gamer1);
        token.approve(address(arcade), toll);
        vm.expectRevert("Arcade: Puzzle invalidated");
        arcade.coin(puzzle, signature, toll);
        vm.stopPrank();
    }

    function testExpire() public {
        // Test expire after timelapse.
        (uint256 prevCreatorAvailable, uint256 prevCreatorLocked) = arcade.balance(address(token), creator);
        (IArcade.Puzzle memory puzzle, bytes memory signature, bytes32 solution) =
            _createPuzzle(300_000, 0.1 ether, 0.2 ether);

        uint256 toll = 0.1 ether;
        token.mint(gamer1, toll);
        vm.startPrank(gamer1);
        token.approve(address(arcade), toll);
        arcade.coin(puzzle, signature, toll);
        vm.stopPrank();

        vm.warp(block.timestamp + 2 hours);
        arcade.expire(puzzle);

        (uint256 creatorAvailable, uint256 creatorLocked) = arcade.balance(address(token), creator);
        assertEq(creatorAvailable, prevCreatorAvailable + toll - toll / 100, "Creator available");
        assertEq(creatorLocked, prevCreatorLocked, "Creator locked");

        // Test expire by player.
        (prevCreatorAvailable, prevCreatorLocked) = arcade.balance(address(token), creator);
        (puzzle, signature, solution) = _createPuzzle(300_000, 0.1 ether, 0.2 ether);
        token.mint(gamer1, toll);
        vm.startPrank(gamer1);
        token.approve(address(arcade), toll);
        arcade.coin(puzzle, signature, toll);
        arcade.expire(puzzle);
        vm.stopPrank();
        (creatorAvailable, creatorLocked) = arcade.balance(address(token), creator);
        assertEq(creatorAvailable, prevCreatorAvailable + toll - toll / 100, "Creator available");
        assertEq(creatorLocked, prevCreatorLocked, "Creator locked");
    }

    function testDeadline() public {
        (IArcade.Puzzle memory puzzle, bytes memory signature,) = _createPuzzle(300_000, 0.1 ether, 0.2 ether);

        vm.warp(puzzle.deadline + 1);
        vm.expectRevert("Arcade: Puzzle deadline exceeded");
        arcade.coin(puzzle, signature, 0.1 ether);
    }

    function testGiveaway() public {
        string memory problemText = string(abi.encodePacked("Giveaway?"));
        bytes32 problem = keccak256(bytes(problemText));
        bytes32 solution = keccak256(abi.encodePacked("Yes!"));
        bytes32 answer = keccak256(abi.encode(problem, solution));

        IArcade.Puzzle memory puzzle = IArcade.Puzzle({
            creator: creator,
            problem: problem,
            answer: answer,
            lives: 1,
            timeLimit: 3600,
            currency: address(token),
            deadline: uint96(block.timestamp + 3600),
            rewardPolicy: giveawayPolicy,
            rewardData: abi.encode(100 ether)
        });

        bytes memory signature = _signPuzzle(puzzle);

        (uint256 prevCreatorAvailable, uint256 prevCreatorLocked) = arcade.balance(address(token), creator);

        vm.startPrank(gamer1);
        token.mint(gamer1, 0.1 ether);
        token.approve(address(arcade), 0.1 ether);
        vm.expectRevert("GiveawayPolicy: Toll must be zero");
        arcade.coin(puzzle, signature, 0.1 ether);
        arcade.coin(puzzle, signature, 0);
        vm.stopPrank();

        (uint256 creatorAvailable, uint256 creatorLocked) = arcade.balance(address(token), creator);
        assertEq(creatorAvailable, prevCreatorAvailable - 100 ether, "Reward should be deducted from available balance");
        assertEq(creatorLocked, prevCreatorLocked + 100 ether, "Reward should be added to locked balance");

        (prevCreatorAvailable, prevCreatorLocked) = arcade.balance(address(token), creator);
        (uint256 prevGamerAvailable, uint256 prevGamerLocked) = arcade.balance(address(token), gamer1);

        vm.prank(gamer1);
        arcade.solve(puzzle, solution);

        (creatorAvailable, creatorLocked) = arcade.balance(address(token), creator);
        (uint256 gamerAvailable, uint256 gamerLocked) = arcade.balance(address(token), gamer1);
        assertEq(creatorAvailable, prevCreatorAvailable, "Creator available balance should not change");
        assertEq(creatorLocked, prevCreatorLocked - 100 ether, "Creator locked balance should be deducted");
        assertEq(gamerAvailable, prevGamerAvailable + 96 ether, "Reward should be added to gamer available balance");
        assertEq(gamerLocked, prevGamerLocked, "Gamer locked balance should not change");
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

    uint256 private _puzzle_nonce = 0;

    function _createPuzzle(uint256 multiplier, uint256 tollMinimum, uint256 tollMaximum)
        internal
        returns (IArcade.Puzzle memory puzzle, bytes memory signature, bytes32 solution)
    {
        string memory problemText = string(abi.encodePacked("What is 2+", Strings.toString(_puzzle_nonce), "?"));
        bytes32 problem = keccak256(bytes(problemText));
        solution = keccak256(abi.encode(2 + _puzzle_nonce));
        bytes32 answer = keccak256(abi.encode(problem, solution));

        _puzzle_nonce++;

        puzzle = IArcade.Puzzle({
            creator: creator,
            problem: problem,
            answer: answer,
            lives: 1,
            timeLimit: 3600,
            currency: address(token),
            deadline: uint96(block.timestamp + 3600),
            rewardPolicy: rewardPolicy,
            rewardData: abi.encode(multiplier, tollMinimum, tollMaximum)
        });

        signature = _signPuzzle(puzzle);
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
                puzzle.lives,
                puzzle.timeLimit,
                puzzle.currency,
                puzzle.deadline,
                puzzle.rewardPolicy,
                keccak256(puzzle.rewardData)
            )
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(creatorPrivateKey, digest);
        return abi.encodePacked(r, s, v);
    }
}
