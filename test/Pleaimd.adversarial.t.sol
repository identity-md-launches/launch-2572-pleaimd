// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Pleaimd} from "../src/Pleaimd.sol";

/// @dev A receiver that rejects callbacks must still be able to receive ordinary ERC-20 transfers.
contract PleaimdContractHolder {
    address private immutable controller = msg.sender;

    fallback() external {
        revert("ERC20 must not require a receiver callback");
    }

    function send(Pleaimd token, address to, uint256 amount) external returns (bool) {
        require(msg.sender == controller);
        return token.transfer(to, amount);
    }

    function approve(Pleaimd token, address spender, uint256 amount) external returns (bool) {
        require(msg.sender == controller);
        return token.approve(spender, amount);
    }
}

/// @notice Additional adversarial properties complement the original deployment and ERC-20 tests.
contract PleaimdAdversarialTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 ether;
    Pleaimd internal token;
    address internal alice = makeAddr("adversarial alice");
    address internal bob = makeAddr("adversarial bob");
    address internal spender = makeAddr("adversarial spender");

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function setUp() public {
        token = new Pleaimd();
    }

    function test_oneBaseUnitCanMoveAndReturnWithoutRounding() public {
        assertTrue(token.transfer(alice, 1));
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
        vm.prank(alice);
        assertTrue(token.approve(spender, 1));
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, address(this), 1));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_ownerCallingTransferFromStillNeedsSelfApproval() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1));
        token.transferFrom(address(this), alice, 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);

        assertTrue(token.approve(address(this), 1));
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertEq(token.allowance(address(this), address(this)), 0);
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
    }

    function test_delegatedSelfTransferConsumesAllowanceAndEmits() public {
        assertTrue(token.approve(spender, 7));
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), address(this), 7);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), address(this), 7));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.totalSupply(), SUPPLY);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), address(this), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_maxMinusOneAllowanceIsFinite() public {
        uint256 approved = type(uint256).max - 1;
        assertTrue(token.approve(spender, approved));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), spender, 1));
        assertEq(token.allowance(address(this), spender), approved - 1);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), spender, SUPPLY - 1));
        assertEq(token.allowance(address(this), spender), approved - SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(spender), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_infiniteApprovalCanBeReplacedRevokedAndGrantedAgain() public {
        assertTrue(token.approve(spender, type(uint256).max));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertEq(token.allowance(address(this), spender), type(uint256).max);

        assertTrue(token.approve(spender, 2));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertEq(token.allowance(address(this), spender), 1);

        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(address(this), spender, 0);
        assertTrue(token.approve(spender, 0));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), alice, 1);
        assertEq(token.balanceOf(alice), 2);
        assertEq(token.allowance(address(this), spender), 0);

        assertTrue(token.approve(spender, type(uint256).max));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, SUPPLY - 2));
        assertEq(token.allowance(address(this), spender), type(uint256).max);
        assertEq(token.balanceOf(alice), SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
    }

    function test_maximumTransferIsRejectedWithoutOverflowOrAllowanceLoss() public {
        uint256 maximum = type(uint256).max;
        bytes memory reason =
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, maximum);
        vm.expectRevert(reason);
        token.transfer(alice, maximum);

        assertTrue(token.approve(spender, maximum));
        vm.expectRevert(reason);
        vm.prank(spender);
        token.transferFrom(address(this), alice, maximum);
        assertEq(token.allowance(address(this), spender), maximum);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_zeroTransferFromEmitsAndPreservesAnExistingAllowance() public {
        vm.prank(alice);
        assertTrue(token.approve(spender, 17));
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(alice, bob, 0);
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 0));
        assertEq(token.allowance(alice, spender), 17);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_zeroReceiverRejectsZeroAndFullAmountWithInfiniteApproval() public {
        assertTrue(token.approve(spender, type(uint256).max));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(address(this), address(0), 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(address(this), address(0), SUPPLY);
        assertEq(token.allowance(address(this), spender), type(uint256).max);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_approvalToZeroIsInvalidEvenForRevocation() public {
        assertTrue(token.approve(spender, 23));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 0);
        assertEq(token.allowance(address(this), spender), 23);
        assertEq(token.allowance(address(this), address(0)), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_contractHolderReceivesApprovesAndReturnsExactSupply() public {
        PleaimdContractHolder holder = new PleaimdContractHolder();
        assertTrue(token.transfer(address(holder), SUPPLY));
        assertEq(token.balanceOf(address(holder)), SUPPLY);
        assertTrue(holder.approve(token, spender, SUPPLY - 1));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(holder), address(this), SUPPLY - 1));
        assertEq(token.balanceOf(address(holder)), 1);
        assertEq(token.allowance(address(holder), spender), 0);
        assertTrue(holder.send(token, address(this), 1));
        assertEq(token.balanceOf(address(holder)), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_failedTransferFromRestoresFiniteAllowanceAndCanBeRetried(uint256 held, uint256 requested) public {
        held = bound(held, 0, SUPPLY - 1);
        requested = bound(requested, held + 1, SUPPLY);
        assertTrue(token.transfer(alice, held));
        vm.prank(alice);
        assertTrue(token.approve(spender, requested));

        // Repeat the same failing call: neither failure is allowed to eat the approval.
        for (uint256 i; i < 2; ++i) {
            vm.expectRevert(
                abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, held, requested)
            );
            vm.prank(spender);
            token.transferFrom(alice, bob, requested);
            assertEq(token.allowance(alice, spender), requested);
            assertEq(token.balanceOf(alice), held);
            assertEq(token.balanceOf(bob), 0);
        }

        // Fund the shortage using real transfers; the original approval must still work.
        assertTrue(token.transfer(alice, requested - held));
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, requested));
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), requested);
        assertEq(token.balanceOf(address(this)), SUPPLY - requested);
        assertEq(token.totalSupply(), SUPPLY);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_replacingApprovalDoesNotAddToTheOldPermission(uint256 oldApproval, uint256 newApproval) public {
        newApproval = bound(newApproval, 0, SUPPLY - 1);
        assertTrue(token.approve(spender, oldApproval));
        assertTrue(token.approve(spender, newApproval));
        assertEq(token.allowance(address(this), spender), newApproval);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, spender, newApproval, newApproval + 1
            )
        );
        vm.prank(spender);
        token.transferFrom(address(this), alice, newApproval + 1);
        assertEq(token.allowance(address(this), spender), newApproval);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, newApproval));
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(alice), newApproval);
        assertEq(token.balanceOf(address(this)), SUPPLY - newApproval);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_ownerAndSpenderAllowancesAreIndependent(uint256 amount) public {
        amount = bound(amount, 1, SUPPLY / 2);
        assertTrue(token.transfer(alice, amount));
        assertTrue(token.transfer(bob, amount));
        vm.prank(alice);
        assertTrue(token.approve(spender, amount));
        vm.prank(alice);
        assertTrue(token.approve(bob, type(uint256).max));
        vm.prank(bob);
        assertTrue(token.approve(spender, type(uint256).max - 1));

        // Alice's grant to Bob does not let Alice spend Bob's balance.
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, alice, 0, 1));
        vm.prank(alice);
        token.transferFrom(bob, alice, 1);
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, spender, amount));
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.allowance(alice, bob), type(uint256).max);
        assertEq(token.allowance(bob, spender), type(uint256).max - 1);
        assertEq(token.allowance(bob, alice), 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), amount);
        assertEq(token.balanceOf(spender), amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_splitDelegatedTransferMatchesSingleDirectTransfer(uint256 amount, uint256 firstPart) public {
        amount = bound(amount, 0, SUPPLY);
        firstPart = bound(firstPart, 0, amount);
        Pleaimd splitToken = new Pleaimd();
        assertTrue(token.transfer(alice, amount));
        assertTrue(splitToken.approve(spender, amount));
        vm.prank(spender);
        assertTrue(splitToken.transferFrom(address(this), alice, firstPart));
        vm.prank(spender);
        assertTrue(splitToken.transferFrom(address(this), alice, amount - firstPart));
        assertEq(splitToken.balanceOf(alice), token.balanceOf(alice));
        assertEq(splitToken.balanceOf(address(this)), token.balanceOf(address(this)));
        assertEq(splitToken.balanceOf(spender), 0);
        assertEq(splitToken.allowance(address(this), spender), 0);
        assertEq(splitToken.totalSupply(), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_transfersRoundTripWithPreexistingBalances(uint256 aliceBalance, uint256 amount) public {
        aliceBalance = bound(aliceBalance, 0, SUPPLY);
        amount = bound(amount, 0, SUPPLY - aliceBalance);
        assertTrue(token.transfer(alice, aliceBalance));
        assertTrue(token.transfer(bob, SUPPLY - aliceBalance));
        vm.prank(bob);
        assertTrue(token.approve(spender, amount));
        vm.prank(spender);
        assertTrue(token.transferFrom(bob, alice, amount));
        vm.prank(alice);
        assertTrue(token.transfer(bob, amount));
        assertEq(token.balanceOf(alice), aliceBalance);
        assertEq(token.balanceOf(bob), SUPPLY - aliceBalance);
        assertEq(token.balanceOf(spender), 0);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.allowance(bob, spender), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }
}
