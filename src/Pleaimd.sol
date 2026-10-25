// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title Pleaimd (PLEA)
/// @notice Fixed-supply meme token with standard ERC-20 transfers and allowances.
/// @dev The immediate deployer receives the entire supply. For an IMD launch this is the factory.
contract Pleaimd is ERC20 {
    uint256 public constant INITIAL_SUPPLY = 1_000_000_000 * 10 ** 18;

    constructor() ERC20("Pleaimd", "PLEA") {
        _mint(msg.sender, INITIAL_SUPPLY);
    }
}
