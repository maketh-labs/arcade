// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.28;

import {IMulticall4} from "./interfaces/IMulticall4.sol";

/// @title Multicall4
/// @notice Enables calling multiple methods in a single call to the contract
abstract contract Multicall4 is IMulticall4 {
    function multicall(bytes[] calldata data) external payable returns (bytes[] memory results) {
        results = new bytes[](data.length);
        for (uint256 i = 0; i < data.length; i++) {
            (bool success, bytes memory result) = address(this).delegatecall(data[i]);

            if (!success) {
                // bubble up the revert reason
                assembly {
                    revert(add(result, 0x20), mload(result))
                }
            }

            results[i] = result;
        }
    }
}
