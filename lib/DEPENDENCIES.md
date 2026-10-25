# Vendored dependencies

All build dependencies are ordinary Solidity source files; no network, package manager,
submodule or installation step is needed to build or test.

- OpenZeppelin Contracts v5.1.0: the unmodified ERC20 implementation and its four
  transitive imports, plus its MIT LICENSE. Source archive:
  https://github.com/OpenZeppelin/openzeppelin-contracts/releases/tag/v5.1.0
- forge-std v1.9.7: unmodified `src/` and the upstream Apache/MIT licenses.
  Used only by tests. Source archive:
  https://github.com/foundry-rs/forge-std/releases/tag/v1.9.7
