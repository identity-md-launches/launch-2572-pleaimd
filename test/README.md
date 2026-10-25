# Pleaimd test coverage

The original `Pleaimd.t.sol` tests remain intact. They cover the specified
Pleaimd / PLEA metadata, 18 decimals, constructor-only mint of 10^27 base units
to the immediate deployer, CREATE2 factory deployment, exact launch-style
distribution, ERC-20 events and failure paths, and unavailable admin entrypoints.

`Pleaimd.adversarial.t.sol` adds explicit one-unit and maximum-uint boundaries,
self-spending and delegated self-transfers, finite versus unlimited allowance
transitions, revocation, contract recipients, and rejected-call atomicity.
Five fuzz properties run 1,000 cases each, with bounded inputs:

- A repeated balance failure preserves the original approval; funding the
  shortage then lets the very same transfer succeed.
- Replacing an approval overwrites its permission instead of accumulating it.
- Approvals remain independent across owners and spenders.
- Splitting a delegated transfer has the same balance effect as a direct transfer.
- Transfers out and back restore preexisting balances exactly, without fees or dust.

`Pleaimd.invariant.t.sol` extends the original handler to eleven actions over five
funded actors, including rejected transfers and approvals. The invariant runs
256 sequences of 96 calls, with unexpected reverts treated as failures. It checks
after each call that:

- Total supply and the sum of tracked balances are exactly 10^27 base units.
- Each balance equals its initial allocation plus cumulative authorized receipts
  minus cumulative authorized sends, independently of the token's reported balance.
- All 25 owner/spender allowances match explicit approvals less successful finite
  spending; unlimited approvals remain unchanged until replaced or revoked.
- Rejected calls leave balances and allowances intact, and the zero address,
  deployer, handler, and token contract gain no unaccounted balance.

The handler bounds valid actions using ghost accounting rather than live token
balances. It explicitly generates zero, one-unit, full-supply, max-minus-one and
unlimited approvals. Expected reverts are matched against complete ERC-6093 error
data. A deterministic sequence exercises nonzero direct and delegated transfers
and every rejection action. At the end of each random sequence, all holders must
still be able to transfer their full balances to one actor, without affecting any
allowance. Tests never mint extra PLEA or write the token's storage with cheatcodes.

Run from the repository root with the existing vendored dependencies:

```sh
forge build
FOUNDRY_FUZZ_SEED=0xd305a318ff5cfcdb2aa5dc80de40516b3d1aa41d664bc6ea203c9b955c3eea5a forge test
```

For a workspace restricted to test-path writes, set `FOUNDRY_OUT=test/scratch/out`
and `FOUNDRY_CACHE_PATH=test/scratch/cache` on both commands. These only redirect
generated artifacts. No delivered test imports anything from `test/scratch/`.

All checks are offline. The token makes no calls to Uniswap itself. Contract
recipient and launch-style transfer tests establish exact ERC-20 delivery, but do
not simulate v4 price formation, liquidity positions, unlock settlement, or swaps.
The supplied protected v4 harness depends on factory contracts and v4 dependencies
not present here and is run separately by the launch verifier. No live-chain fork
test was run; end-to-end launch and swap verification remains with that harness.
