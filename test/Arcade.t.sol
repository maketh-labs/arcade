// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "forge-std/mocks/MockERC20.sol";
import {stdError} from "forge-std/StdError.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Arcade, IArcade} from "../src/Arcade.sol";
import {MulRewardPolicy} from "../src/MulRewardPolicy.sol";
import {GiveawayPolicy} from "../src/GiveawayPolicy.sol";
import {WETH9} from "../src/external/WETH9.sol";
import {VerifySig} from "../src/external/UniversalSigValidator.sol";

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
    address public verifySig;
    address public mulPolicy;
    address public giveawayPolicy;

    address public protocol = makeAddr("protocol");
    address public creator;
    uint256 public creatorPrivateKey;
    address public gamer1 = makeAddr("1");
    address public gamer2 = makeAddr("2");

    uint256 private constant TOLL1 = 0.1 ether;
    uint256 private constant TOLL2 = 0.15 ether;
    uint256 private constant TOLL3 = 0.2 ether;

    function setUp() public {
        weth = address(new WETH9());
        verifySig = address(new VerifySig());
        arcade = new Arcade(protocol, weth, verifySig);
        token = new Token();
        mulPolicy = address(new MulRewardPolicy());
        giveawayPolicy = address(new GiveawayPolicy());
        (creator, creatorPrivateKey) = makeAddrAndKey("creator");

        _deposit(address(token), creator, 100_000_000 ether);
    }

    function testDeposit() public {
        _deposit(address(token), gamer1, 0.1 ether);
        _deposit(address(token), gamer1, 0.2 ether);
        _depositETH(gamer1, 0.3 ether);
        _depositETH(gamer1, 0.4 ether);
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

        (IArcade.Puzzle memory puzzle, bytes memory signature, bytes32 payoutData, bytes memory payoutSignature) =
            _basicPuzzle();

        token.mint(gamer1, TOLL1);
        vm.startPrank(gamer1);
        token.approve(address(arcade), TOLL1);
        arcade.coin(puzzle, signature, TOLL1);
        vm.stopPrank();

        (uint256 creatorAvailable, uint256 creatorLocked) = arcade.balance(address(token), creator);
        (uint256 gamerAvailable, uint256 gamerLocked) = arcade.balance(address(token), gamer1);

        assertEq(creatorAvailable, prevCreatorAvailable + TOLL1 - TOLL1 / 100 - TOLL1 * 3, "Creator available 1");
        assertEq(creatorLocked, prevCreatorLocked + TOLL1 * 3, "Creator locked 1");
        assertEq(gamerAvailable, 0, "Gamer available 1");
        assertEq(gamerLocked, 0, "Gamer locked 1");

        /// Pay with deposits.
        (prevCreatorAvailable, prevCreatorLocked) = arcade.balance(address(token), creator);

        (puzzle, signature, payoutData, payoutSignature) = _basicPuzzle();

        _deposit(address(token), gamer1, 0.3 ether);
        vm.startPrank(gamer1);
        token.approve(address(arcade), TOLL3);
        arcade.coin(puzzle, signature, TOLL3);
        vm.stopPrank();

        (creatorAvailable, creatorLocked) = arcade.balance(address(token), creator);
        (gamerAvailable, gamerLocked) = arcade.balance(address(token), gamer1);

        assertEq(creatorAvailable, prevCreatorAvailable + TOLL3 - TOLL3 / 100 - TOLL3 * 3, "Creator available 2");
        assertEq(creatorLocked, prevCreatorLocked + TOLL3 * 3, "Creator locked 2");
        assertEq(gamerAvailable, 0.1 ether, "Gamer available 2");
        assertEq(gamerLocked, 0, "Gamer locked 2");

        /// Pay with a mix of both.
        (prevCreatorAvailable, prevCreatorLocked) = arcade.balance(address(token), creator);
        (puzzle, signature, payoutData, payoutSignature) = _basicPuzzle();

        token.mint(gamer1, TOLL2);
        vm.startPrank(gamer1);
        token.approve(address(arcade), TOLL2);
        arcade.coin(puzzle, signature, TOLL2);
        vm.stopPrank();

        (creatorAvailable, creatorLocked) = arcade.balance(address(token), creator);
        (gamerAvailable, gamerLocked) = arcade.balance(address(token), gamer1);

        assertEq(creatorAvailable, prevCreatorAvailable + TOLL2 - TOLL2 / 100 - TOLL2 * 3, "Creator available 3");
        assertEq(creatorLocked, prevCreatorLocked + TOLL2 * 3, "Creator locked 3");
        assertEq(gamerAvailable, 0, "Gamer available 3");
        assertEq(gamerLocked, 0, "Gamer locked 3");
    }

    function testCoinETH() public {
        vm.deal(creator, 1 ether);
        vm.prank(creator);
        arcade.depositETH{value: 1 ether}(creator, 1 ether);

        (IArcade.Puzzle memory puzzle, bytes memory signature,,) = _basicPuzzleETH();

        uint256 toll = 0.1 ether;
        vm.deal(gamer1, toll);
        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeWithSelector(IArcade.depositETH.selector, gamer1, toll);
        data[1] = abi.encodeWithSelector(IArcade.coin.selector, puzzle, signature, toll);
        vm.prank(gamer1);
        arcade.multicall{value: 0.1 ether}(data);
    }

    function testSolve() public {
        (IArcade.Puzzle memory puzzle, bytes memory signature, bytes32 payoutData, bytes memory payoutSignature) =
            _basicPuzzle();

        uint256 toll = 0.1 ether;
        uint256 reward = 0.3 ether;
        uint256 protocolFee = reward * 4 / 100;
        token.mint(gamer1, toll);
        vm.startPrank(gamer1);
        token.approve(address(arcade), toll);
        arcade.coin(puzzle, signature, toll);
        arcade.solve(puzzle, payoutData, payoutSignature);
        vm.stopPrank();

        (uint256 gamerAvailable, uint256 gamerLocked) = arcade.balance(address(token), gamer1);
        (, uint256 creatorLocked) = arcade.balance(address(token), creator);

        assertEq(creatorLocked, 0, "Creator should have no locked balance");
        assertEq(gamerAvailable, reward - protocolFee, "Gamer should receive reward minus protocol fee");
        assertEq(gamerLocked, 0, "Gamer should have no locked balance");
    }

    function testSolvePartialPayout() public {
        (IArcade.Puzzle memory puzzle, bytes memory signature, bytes32 payoutData, bytes memory payoutSignature) =
            _partialPayoutPuzzle(30_000);

        (uint256 prevCreatorAvailable, uint256 prevCreatorLocked) = arcade.balance(address(token), creator);

        token.mint(gamer1, 0.1 ether);
        vm.startPrank(gamer1);
        token.approve(address(arcade), 0.1 ether);
        arcade.coin(puzzle, signature, 0.1 ether);
        vm.stopPrank();

        (uint256 gamerAvailable, uint256 gamerLocked) = arcade.balance(address(token), gamer1);
        (uint256 creatorAvailable, uint256 creatorLocked) = arcade.balance(address(token), creator);

        assertEq(prevCreatorAvailable + 0.1 ether - 0.001 ether - 0.3 ether, creatorAvailable);
        assertEq(creatorLocked, 0.3 ether);
        assertEq(gamerAvailable, 0, "Gamer should receive 30% of the reward minus protocol fee");
        assertEq(gamerLocked, 0, "Gamer should have no locked balance");

        (prevCreatorAvailable, prevCreatorLocked) = arcade.balance(address(token), creator);

        vm.prank(gamer1);
        arcade.solve(puzzle, bytes32(uint256(30_000)), payoutSignature);

        uint256 payout = 0.3 ether * 30_000 / 100_000;
        (gamerAvailable, gamerLocked) = arcade.balance(address(token), gamer1);
        (creatorAvailable, creatorLocked) = arcade.balance(address(token), creator);

        assertEq(creatorAvailable, prevCreatorAvailable + 0.3 ether - payout);
        assertEq(creatorLocked, 0, "Creator should have no locked balance");
        assertEq(gamerAvailable, payout - payout * 4 / 100);
        assertEq(gamerLocked, 0, "Gamer should have no locked balance");
    }

    function testExpireOutOfLives() public {
        (IArcade.Puzzle memory puzzle, bytes memory signature, bytes32 payoutData, bytes memory payoutSignature) =
            _livesPuzzle(2);

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
        (IArcade.Puzzle memory puzzle, bytes memory signature,,) = _basicPuzzle();

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
        (IArcade.Puzzle memory puzzle1, bytes memory signature1,,) = _basicPuzzle();
        (IArcade.Puzzle memory puzzle2, bytes memory signature2,,) = _basicPuzzle();

        uint256 toll = 0.1 ether;
        token.mint(gamer1, toll * 2);
        vm.startPrank(gamer1);
        token.approve(address(arcade), toll * 2);
        arcade.coin(puzzle1, signature1, toll);
        arcade.coin(puzzle2, signature2, toll);
        assert(arcade.expire(puzzle1));
        assert(!arcade.expire(puzzle1));
        vm.stopPrank();
    }

    function testDuplicateSolve() public {
        (IArcade.Puzzle memory puzzle, bytes memory signature, bytes32 payoutData, bytes memory payoutSignature) =
            _basicPuzzle();

        uint256 toll = 0.1 ether;
        token.mint(gamer1, toll);
        vm.startPrank(gamer1);
        token.approve(address(arcade), toll);
        arcade.coin(puzzle, signature, toll);
        arcade.solve(puzzle, payoutData, payoutSignature);
        vm.expectRevert("Arcade: Puzzle invalidated");
        arcade.solve(puzzle, payoutData, payoutSignature);
        vm.stopPrank();
    }

    function testExpireAfterSolve() public {
        (IArcade.Puzzle memory puzzle, bytes memory signature, bytes32 payoutData, bytes memory payoutSignature) =
            _basicPuzzle();

        uint256 toll = 0.1 ether;
        token.mint(gamer1, toll);
        vm.startPrank(gamer1);
        token.approve(address(arcade), toll);
        arcade.coin(puzzle, signature, toll);
        arcade.solve(puzzle, payoutData, payoutSignature);
        assert(!arcade.expire(puzzle));
        vm.stopPrank();
    }

    function testSolveAfterExpire() public {
        (IArcade.Puzzle memory puzzle, bytes memory signature, bytes32 payoutData, bytes memory payoutSignature) =
            _basicPuzzle();

        uint256 toll = 0.1 ether;
        token.mint(gamer1, toll);
        vm.startPrank(gamer1);
        token.approve(address(arcade), toll);
        arcade.coin(puzzle, signature, toll);
        arcade.expire(puzzle);
        vm.expectRevert("Arcade: Puzzle invalidated");
        arcade.solve(puzzle, payoutData, payoutSignature);
        vm.stopPrank();
    }

    function testSolveIncorrect() public {
        (IArcade.Puzzle memory puzzle, bytes memory signature, bytes32 payoutData, bytes memory payoutSignature) =
            _basicPuzzle();

        uint256 toll = 0.1 ether;
        token.mint(gamer1, toll);
        vm.startPrank(gamer1);
        token.approve(address(arcade), toll);
        arcade.coin(puzzle, signature, toll);
        // Solve with incorrect solution.
        (, uint256 wrongPrivateKey) = makeAddrAndKey("WRONG");
        bytes memory wrongPayoutSignature = _signPayout(payoutData, wrongPrivateKey);
        vm.expectRevert("Arcade: Incorrect solution");
        arcade.solve(puzzle, payoutData, wrongPayoutSignature);
        vm.stopPrank();

        // Solve with different player.
        vm.startPrank(gamer2);
        vm.expectRevert("Arcade: Only player can solve the puzzle");
        arcade.solve(puzzle, payoutData, payoutSignature);
        vm.stopPrank();

        // Solve after expiry.
        vm.warp(block.timestamp + 2 hours);
        vm.prank(gamer1);
        vm.expectRevert("Arcade: Puzzle has expired");
        arcade.solve(puzzle, payoutData, payoutSignature);
    }

    function testInvalidate() public {
        (IArcade.Puzzle memory puzzle, bytes memory signature, bytes32 payoutData, bytes memory payoutSignature) =
            _basicPuzzle();

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

        (puzzle, signature, payoutData, payoutSignature) = _basicPuzzle();
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
        (IArcade.Puzzle memory puzzle, bytes memory signature, bytes32 payoutData, bytes memory payoutSignature) =
            _basicPuzzle();

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
        (puzzle, signature, payoutData, payoutSignature) = _basicPuzzle();
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
        (IArcade.Puzzle memory puzzle, bytes memory signature,,) = _basicPuzzle();

        vm.warp(puzzle.deadline + 1);
        vm.expectRevert("Arcade: Puzzle deadline exceeded");
        arcade.coin(puzzle, signature, 0.1 ether);
    }

    function testGiveaway() public {
        (IArcade.Puzzle memory puzzle, bytes memory signature, bytes32 payoutData, bytes memory payoutSignature) =
            _giveawayPuzzle(100 ether);

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
        arcade.solve(puzzle, payoutData, payoutSignature);

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
        uint256 prevBalance = IERC20(currency).balanceOf(address(arcade));
        (uint256 prevAvailable, uint256 prevLocked) = arcade.balance(currency, gamer);
        token.mint(gamer, amount);
        vm.startPrank(gamer);
        token.approve(address(arcade), amount);
        arcade.deposit(currency, gamer, amount);
        vm.stopPrank();
        uint256 balance = IERC20(currency).balanceOf(address(arcade));
        assertEq(balance, prevBalance + amount);
        (available, locked) = arcade.balance(currency, gamer);
        assertEq(available, prevAvailable + amount);
        assertEq(locked, prevLocked);
    }

    function _depositETH(address gamer, uint256 amount) internal returns (uint256 available, uint256 locked) {
        uint256 prevBalance = IERC20(weth).balanceOf(address(arcade));
        (uint256 prevAvailable, uint256 prevLocked) = arcade.balance(weth, gamer);
        vm.deal(gamer, amount);
        vm.startPrank(gamer);
        arcade.depositETH{value: amount}(gamer, amount);
        vm.stopPrank();
        uint256 balance = IERC20(weth).balanceOf(address(arcade));
        assertEq(balance, prevBalance + amount);
        (available, locked) = arcade.balance(weth, gamer);
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

    function _withdrawETH(address gamer, uint256 amount) internal returns (uint256 available, uint256 locked) {
        uint256 prevArcadeBalance = IERC20(weth).balanceOf(address(arcade));
        uint256 prevGamerBalance = gamer.balance;
        (uint256 prevAvailable, uint256 prevLocked) = arcade.balance(weth, gamer);
        vm.prank(gamer);
        arcade.withdrawETH(amount);
        (available, locked) = arcade.balance(weth, gamer);
        assertEq(available, prevAvailable - amount);
        assertEq(locked, prevLocked);
        assertEq(gamer.balance, prevGamerBalance + amount);
        assertEq(IERC20(weth).balanceOf(address(arcade)), prevArcadeBalance - amount);
    }

    function _basicPuzzle()
        internal
        returns (IArcade.Puzzle memory puzzle, bytes memory signature, bytes32 payoutData, bytes memory payoutSignature)
    {
        return _puzzle(
            1, 3600, address(token), mulPolicy, abi.encode(300_000, 0.1 ether, 0.2 ether), bytes32(uint256(100_000))
        );
    }

    function _basicPuzzleETH()
        internal
        returns (IArcade.Puzzle memory puzzle, bytes memory signature, bytes32 payoutData, bytes memory payoutSignature)
    {
        return _puzzle(1, 3600, weth, mulPolicy, abi.encode(300_000, 0.1 ether, 0.2 ether), bytes32(uint256(100_000)));
    }

    function _partialPayoutPuzzle(uint256 payout)
        internal
        returns (IArcade.Puzzle memory puzzle, bytes memory signature, bytes32 payoutData, bytes memory payoutSignature)
    {
        return _puzzle(
            1, 3600, address(token), mulPolicy, abi.encode(300_000, 0.1 ether, 0.2 ether), bytes32(uint256(payout))
        );
    }

    function _giveawayPuzzle(uint256 reward)
        internal
        returns (IArcade.Puzzle memory puzzle, bytes memory signature, bytes32 payoutData, bytes memory payoutSignature)
    {
        return _puzzle(1, 3600, address(token), giveawayPolicy, abi.encode(reward), bytes32(uint256(100_000)));
    }

    function _livesPuzzle(uint32 lives)
        internal
        returns (IArcade.Puzzle memory puzzle, bytes memory signature, bytes32 payoutData, bytes memory payoutSignature)
    {
        return _puzzle(
            lives, 3600, address(token), mulPolicy, abi.encode(300_000, 0.1 ether, 0.2 ether), bytes32(uint256(100_000))
        );
    }

    uint256 private _puzzle_nonce = 0;

    function _puzzle(
        uint32 lives,
        uint64 timeLimit,
        address currency,
        address rewardPolicy,
        bytes memory rewardData,
        bytes32 _payoutData
    )
        internal
        returns (IArcade.Puzzle memory puzzle, bytes memory signature, bytes32 payoutData, bytes memory payoutSignature)
    {
        payoutData = _payoutData;
        string memory problemText = string(abi.encodePacked("What is 2+", Strings.toString(_puzzle_nonce), "?"));
        (address answer, uint256 answerPrivateKey) = makeAddrAndKey(problemText);

        _puzzle_nonce++;

        puzzle = IArcade.Puzzle({
            creator: creator,
            answer: answer,
            lives: lives,
            timeLimit: timeLimit,
            currency: currency,
            deadline: uint96(block.timestamp + 3600),
            rewardPolicy: rewardPolicy,
            rewardData: rewardData
        });

        signature = _signPuzzle(puzzle);
        payoutSignature = _signPayout(payoutData, answerPrivateKey);
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

    function _signPayout(bytes32 payoutData, uint256 privateKey) internal pure returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, payoutData);
        return abi.encodePacked(r, s, v);
    }
}
