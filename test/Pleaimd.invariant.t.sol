// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Pleaimd} from "../src/Pleaimd.sol";

/// @dev All supply stays within the actor set. Ghost accounting uses requested amounts, never
/// copies token balances, and is unchanged by rejected calls. Allowances are tracked for every pair.
contract TokenHandler is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 ether;
    Pleaimd public immutable token;
    address[5] public actors;
    mapping(address => uint256) public received;
    mapping(address => uint256) public sent;
    mapping(address => mapping(address => uint256)) public expectedAllowance;
    uint256 public nonzeroTransfers;
    uint256 public nonzeroDelegatedTransfers;
    uint256 public rejectedCalls;

    constructor(Pleaimd token_) {
        token = token_;
        for (uint256 i; i < actors.length; ++i) {
            actors[i] = address(uint160(uint256(keccak256(abi.encode("PLEA invariant actor", i)))));
            received[actors[i]] = SUPPLY / actors.length;
        }
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        _transfer(from, to, bound(amount, 0, expectedBalance(from)));
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        _approve(owner, spender, amount);
    }

    function approveBoundary(uint256 ownerSeed, uint256 spenderSeed, uint256 mode) external {
        uint256[5] memory values = [uint256(0), 1, SUPPLY, type(uint256).max - 1, type(uint256).max];
        _approve(actors[ownerSeed % actors.length], actors[spenderSeed % actors.length], values[mode % 5]);
    }

    function transferFrom(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 allowance = expectedAllowance[owner][spender];
        uint256 balance = expectedBalance(owner);
        amount = bound(amount, 0, allowance < balance ? allowance : balance);
        vm.prank(spender);
        assertTrue(token.transferFrom(owner, to, amount));
        _recordTransfer(owner, to, amount);
        if (amount > 0) ++nonzeroDelegatedTransfers;
        if (allowance != type(uint256).max) expectedAllowance[owner][spender] -= amount;
        assertEq(token.allowance(owner, spender), allowance == type(uint256).max ? allowance : allowance - amount);
    }

    function transferAll(uint256 fromSeed, uint256 toSeed) external {
        address from = actors[fromSeed % actors.length];
        _transfer(from, actors[toSeed % actors.length], expectedBalance(from));
    }

    function rejectOverspend(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address from = actors[fromSeed % actors.length];
        uint256 balance = expectedBalance(from);
        amount = bound(amount, balance + 1, type(uint256).max);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, balance, amount));
        vm.prank(from);
        token.transfer(actors[toSeed % actors.length], amount);
        ++rejectedCalls;
    }

    function rejectOverAllowance(uint256 ownerSeed, uint256 spenderSeed, uint256 approved, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        // Finite approvals only: an unlimited allowance cannot be exceeded.
        approved = bound(approved, 0, type(uint256).max - 1);
        _approve(owner, spender, approved);
        amount = bound(amount, approved + 1, type(uint256).max);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, approved, amount)
        );
        vm.prank(spender);
        token.transferFrom(owner, spender, amount);
        ++rejectedCalls;
    }

    function rejectDelegatedOverBalance(uint256 ownerSeed, uint256 spenderSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        uint256 balance = expectedBalance(owner);
        amount = bound(amount, balance + 1, type(uint256).max);
        _approve(owner, spender, amount);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, owner, balance, amount));
        vm.prank(spender);
        token.transferFrom(owner, spender, amount);
        // A failing transfer must roll back any allowance debit as well as balances.
        ++rejectedCalls;
    }

    function rejectZeroRecipient(uint256 ownerSeed, uint256 spenderSeed, uint256 amount, bool delegated) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        uint256 limit = expectedBalance(owner);
        uint256 allowance = expectedAllowance[owner][spender];
        if (delegated && allowance < limit) limit = allowance;
        amount = bound(amount, 0, limit);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        if (delegated) {
            vm.prank(spender);
            token.transferFrom(owner, address(0), amount);
        } else {
            vm.prank(owner);
            token.transfer(address(0), amount);
        }
        ++rejectedCalls;
    }

    function rejectZeroSpender(uint256 ownerSeed, uint256 amount) external {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        vm.prank(actors[ownerSeed % actors.length]);
        token.approve(address(0), amount);
        ++rejectedCalls;
    }

    function revokeAndReject(uint256 ownerSeed, uint256 spenderSeed) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        _approve(owner, spender, 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(owner, spender, 1);
        ++rejectedCalls;
    }

    function expectedBalance(address actor) public view returns (uint256) {
        return received[actor] - sent[actor];
    }

    function _approve(address owner, address spender, uint256 amount) internal {
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        expectedAllowance[owner][spender] = amount;
    }

    function _transfer(address from, address to, uint256 amount) internal {
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        _recordTransfer(from, to, amount);
        if (amount > 0) ++nonzeroTransfers;
    }

    function _recordTransfer(address from, address to, uint256 amount) internal {
        sent[from] += amount;
        received[to] += amount;
    }
}

contract PleaimdInvariantTest is StdInvariant, Test {
    Pleaimd internal token;
    TokenHandler internal handler;

    function setUp() public {
        token = new Pleaimd();
        handler = new TokenHandler(token);
        for (uint256 i; i < 5; ++i) {
            assertTrue(token.transfer(handler.actors(i), 1_000_000_000 ether / 5));
            // Start with both finite and unlimited approvals so delegated transfers are reachable
            // immediately; random approve/revoke calls can then replace them independently.
            handler.approve(i, (i + 1) % 5, 1_000_000_000 ether / 5);
            handler.approve(i, (i + 2) % 5, type(uint256).max);
        }
        bytes4[] memory selectors = new bytes4[](11);
        selectors[0] = TokenHandler.transfer.selector;
        selectors[1] = TokenHandler.approve.selector;
        selectors[2] = TokenHandler.transferFrom.selector;
        selectors[3] = TokenHandler.approveBoundary.selector;
        selectors[4] = TokenHandler.transferAll.selector;
        selectors[5] = TokenHandler.rejectOverspend.selector;
        selectors[6] = TokenHandler.rejectOverAllowance.selector;
        selectors[7] = TokenHandler.rejectDelegatedOverBalance.selector;
        selectors[8] = TokenHandler.rejectZeroRecipient.selector;
        selectors[9] = TokenHandler.rejectZeroSpender.selector;
        selectors[10] = TokenHandler.revokeAndReject.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 96
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_supplyAndBalancesAreConserved() public view {
        uint256 sum;
        for (uint256 i; i < 5; ++i) {
            address actor = handler.actors(i);
            uint256 balance = token.balanceOf(actor);
            assertEq(balance, handler.expectedBalance(actor), "holder balance differs from authorized net receipts");
            sum += balance;
            for (uint256 j; j < 5; ++j) {
                address spender = handler.actors(j);
                assertEq(
                    token.allowance(actor, spender), handler.expectedAllowance(actor, spender), "allowance diverged"
                );
            }
            assertEq(token.allowance(actor, address(0)), 0);
        }
        assertEq(sum, 1_000_000_000 ether);
        assertEq(token.totalSupply(), 1_000_000_000 ether);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(handler)), 0);
        assertEq(token.balanceOf(address(token)), 0);
    }

    /// @dev Even after arbitrary rejected calls and approvals, every holder can move all its funds.
    /// This runs at the end of each invariant sequence, not between random operations.
    function afterInvariant() public {
        invariant_supplyAndBalancesAreConserved();
        for (uint256 i = 1; i < 5; ++i) {
            handler.transferAll(i, 0);
            assertEq(token.balanceOf(handler.actors(i)), 0);
        }
        assertEq(token.balanceOf(handler.actors(0)), 1_000_000_000 ether);
        invariant_supplyAndBalancesAreConserved();
    }

    function test_handlerExercisesPositiveAmountsAndEveryRejection() public {
        handler.transfer(0, 1, 1);
        handler.transferFrom(1, 2, 3, 1);
        handler.approveBoundary(3, 4, 4);
        handler.transferFrom(3, 4, 3, 1); // A delegated self-transfer still requires permission.
        invariant_supplyAndBalancesAreConserved();

        handler.rejectOverspend(0, 0, type(uint256).max);
        invariant_supplyAndBalancesAreConserved();
        handler.rejectOverAllowance(0, 1, 0, 1);
        invariant_supplyAndBalancesAreConserved();
        handler.rejectDelegatedOverBalance(1, 2, type(uint256).max);
        invariant_supplyAndBalancesAreConserved();
        handler.rejectZeroRecipient(3, 4, 1, true);
        invariant_supplyAndBalancesAreConserved();
        handler.rejectZeroRecipient(3, 4, 0, false);
        invariant_supplyAndBalancesAreConserved();
        handler.rejectZeroSpender(3, 0);
        invariant_supplyAndBalancesAreConserved();
        handler.revokeAndReject(3, 4);
        invariant_supplyAndBalancesAreConserved();

        assertEq(handler.nonzeroTransfers(), 1);
        assertEq(handler.nonzeroDelegatedTransfers(), 2);
        assertEq(handler.rejectedCalls(), 7);
        afterInvariant();
    }
}
