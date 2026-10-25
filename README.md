# Pleaimd (PLEA)

Pleaimd is a standard, immutable ERC-20 meme token intended for the IdentityMD
Uniswap v4 launch on Ethereum (chain ID 1).

| Property | Value |
| --- | --- |
| Solidity contract | `Pleaimd` in `src/Pleaimd.sol` |
| Token name | `Pleaimd` |
| Symbol | `PLEA` |
| Decimals | `18` |
| Whole-token supply | `1,000,000,000` |
| Base-unit supply | `1000000000000000000000000000` (`10^27`) |
| Constructor arguments | None |
| Constructor value | None (nonpayable) |
| Initial recipient | Immediate deployer (`msg.sender`) |

The constructor mints the entire supply once and emits one `Transfer` from the
zero address. It makes no external calls. Through the launch factory, the factory
receives the supply; it does not go to the transaction origin. There is no owner,
mint entrypoint, burn entrypoint, pause, blacklist, tax, wallet limit, trading
switch, proxy, upgrade mechanism, or dependency on a configured external address.
`INITIAL_SUPPLY` is the named constant for the fixed supply in base units.

## Transfer behavior and assumptions

The implementation inherits unmodified OpenZeppelin Contracts v5.1.0 `ERC20`.
Transfers deliver exactly the requested amount, including transfers to and from
contracts. Zero-value transfers are valid and emit `Transfer`; self-transfers
preserve balances but still require sufficient funds. Transfers to the zero
address are rejected, so they cannot burn supply.

Allowances follow standard ERC-20 semantics. `approve` replaces the current
allowance, and approval of the zero address reverts. Finite allowances decrease
on `transferFrom`; an allowance of `type(uint256).max` does not decrease.
OpenZeppelin v5 does not emit `Approval` when spending an allowance.
An insufficient balance or allowance reverts atomically with ERC-6093 errors.
There is no privileged bypass, even for the deployer. Applications should request
only necessary allowances; holders can revoke them with `approve(spender, 0)`.
When replacing a nonzero allowance, revoke it first and wait for confirmation to
reduce the usual ERC-20 allowance replacement race.

“On Uniswap v4” is implemented as unrestricted ERC-20 compatibility. The token
does not create pools, implement hooks, quote prices, route trades or hold LP
positions. Those actions belong to the launch infrastructure. There are no
token-specific exemptions or post-deployment configuration requirements.

## Deployment and operational responsibilities

Build `src/Pleaimd.sol:Pleaimd` with the root Foundry configuration. The launch
service deploys its creation bytecode with **no constructor arguments**, **zero
ETH value**, and expected supply **1000000000000000000000000000**. Deployment
requires no other contracts to exist. This repository does not broadcast any
transactions or provide a launch manifest; the separate manifest step supplies
the chain-specific launch configuration.

The assignment specifies these external launch economics (they are not token
transfer fees or allocations performed in the constructor):

- The factory forwards 10% (100,000,000 PLEA) to the launch Merkle distributor.
- It allocates 20% (200,000,000 PLEA) to pool liquidity and forwards the remaining
  70% (700,000,000 PLEA) to `0xee2aaa315cf7ed169f93148d30d24af9318dbb66`.
- The paired currency is IMD at
  `0xd34a99bc0f67ae1bbd63c660e6d0b0dd03e263b7`, with 18 decimals.
- The launch pool fee is `12500` (1.25%) and tick spacing is `60`.
  The requested initial whole-supply market cap is
  `3000000000000000000000` IMD base units (3,000 IMD).
- The reference pool price field is `79228162514264337593543950336` (sqrtPriceX96);
  the launch service derives the actual opening price from the economics,
  supply, and final currency ordering.

These addresses and parameters come from the assignment; the token neither
stores nor calls them. The launch service is responsible for resolving and
validating live protocol addresses, deploying the token, distributing the supply,
initializing and seeding the correct v4 pool, and publishing/verifying deployment
artifacts. Contributors claim through the external distributor. No owner needs
to configure this token after launch, and no ongoing keeper or operator is
required for ERC-20 transfers. Sending tokens directly to the token contract or
another contract without a withdrawal path can lock them permanently; this token
has no recovery power.

## Build and checks

Requires Foundry and Solidity **0.8.26**. All Solidity dependencies and their
licenses are vendored as ordinary files in `lib/`; see `lib/DEPENDENCIES.md`.
No dependency download is needed. The verifier provides the pinned compiler.
The root `foundry.toml` enables optimization, targets Cancun, and sets
`bytecode_hash = "none"` for reproducible launch bytecode. FFI and filesystem
permissions are not enabled.

```sh
forge build
FOUNDRY_FUZZ_SEED=0xd305a318ff5cfcdb2aa5dc80de40516b3d1aa41d664bc6ea203c9b955c3eea5a forge test
forge fmt --check
```

The tests cover metadata, constructor mint logs, CREATE2 factory deployment,
exact launch-style distribution and claim transfers, transfer and approval
events, zero and full amounts, self-transfers, invalid addresses, insufficient
balances and allowances, revocation, infinite approvals, failed-operation
atomicity, and absence of administrative entrypoints. Fuzz tests cover valid
transfers, delegated transfers, and overspending. A stateful invariant handler
exercises arbitrary sequences of transfers, approvals and delegated transfers
among five holders while checking conservation of every base unit and supply.
Tests use no environment variables, RPC, time delays or shared external state.

The local launch-flow test uses ordinary addresses for settlement recipients; it
is not an end-to-end Uniswap simulation. The supplied protected integration
harness independently checks actual v4 initialization, seed settlement and swaps
in both directions during launch verification. Those pinned harness files
depend on verifier infrastructure not supplied in this repository.

Foundry tests are not a security audit. Independent adversarial review and
post-deployment source verification remain release responsibilities. Slither
and Mythril were not run in this assignment.
