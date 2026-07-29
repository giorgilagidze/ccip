// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.17;

import { Test } from "forge-std/Test.sol";
import { console } from "forge-std/console.sol";

import { Action } from "@aragon/osx-commons-contracts/src/executors/IExecutor.sol";
import { Transaction, TransactionLib } from "@src/lib/Transaction.sol";

/// @dev Measures the gas cost of `MessageExecutionFailed` for a realistic
///      worst-case envelope: 15 actions, each carrying >=50 bytes of calldata.
contract EmitGasProbe is Test {
    /// @dev Same signature as `ICrossChainController.MessageExecutionFailed`.
    event MessageExecutionFailed(
        uint256 indexed originChainId, uint256 indexed messageId, bytes32 indexed txId, bytes transaction, bytes reason
    );

    function test_emitCost() public {
        // 15 actions, each with 50 bytes of `data`.
        Action[] memory actions = new Action[](15);
        for (uint256 i = 0; i < actions.length; i++) {
            bytes memory data = new bytes(50);
            for (uint256 j = 0; j < 50; j++) {
                // Non-zero bytes: calldata content does not affect LOG pricing,
                // but keep it realistic rather than an all-zero blob.
                data[j] = bytes1(uint8(1 + ((i + j) % 255)));
            }
            actions[i] = Action({ to: address(uint160(0x1000 + i)), value: 0, data: data });
        }

        Transaction memory transaction = Transaction({
            nonce: 1,
            origin: address(0xA11CE),
            controller: address(this),
            originChainId: 1,
            destinationChainId: 8453,
            message: abi.encode(actions)
        });

        bytes memory encodedTx = TransactionLib.encode(transaction);
        bytes32 txId = TransactionLib.id(transaction);

        // A typical revert reason: Error(string) with a short message.
        bytes memory reason = abi.encodeWithSignature("Error(string)", "SomeTarget: execution reverted");

        console.log("inner message (Action[]) length", transaction.message.length);
        console.log("encodedTx length", encodedTx.length);
        console.log("reason length", reason.length);

        uint256 before = gasleft();
        emit MessageExecutionFailed(1, 12345, txId, encodedTx, reason);
        uint256 afterEmit = gasleft();

        console.log("GAS USED BY EMIT", before - afterEmit);

        // For comparison: the same event without the envelope bytes.
        uint256 beforeSlim = gasleft();
        emit MessageExecutionFailed(1, 12345, txId, "", reason);
        uint256 afterSlim = gasleft();

        console.log("GAS USED BY EMIT (no envelope)", beforeSlim - afterSlim);
    }
}
