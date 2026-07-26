// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.17;

import { Action, IExecutor } from "@aragon/osx-commons-contracts/src/executors/IExecutor.sol";

/// @notice An `IExecutor` whose `execute` can be made to revert on demand.
/// @dev DO NOT USE IN PRODUCTION! Test-only.
///
///      `DAOMock.execute` always succeeds, so it cannot drive `BaseAdapter`'s
///      deliver-but-fail path. This mock exists to flip execution between
///      success and failure so the `Delivered` state, `MessageExecutionFailed`
///      event, and `retryMessage` / `cancelMessage` flows can be exercised.
contract ExecutorMock is IExecutor {
    /// @notice Thrown by `execute` while `shouldRevert` is set.
    error ExecutionFailed();

    /// @notice Whether the next `execute` call reverts.
    bool public shouldRevert;

    /// @notice Number of times `execute` was called (including reverted ones
    ///         that were caught by the caller).
    uint256 public executeCallCount;

    /// @notice The `callId` of the most recent `execute` call.
    bytes32 public lastCallId;

    /// @notice Sets whether `execute` reverts.
    function setShouldRevert(bool _shouldRevert) external {
        shouldRevert = _shouldRevert;
    }

    /// @inheritdoc IExecutor
    function execute(bytes32 _callId, Action[] memory _actions, uint256 _allowFailureMap)
        external
        override
        returns (bytes[] memory execResults, uint256 failureMap)
    {
        if (shouldRevert) revert ExecutionFailed();

        executeCallCount++;
        lastCallId = _callId;

        emit Executed(msg.sender, _callId, _actions, _allowFailureMap, failureMap, execResults);
    }
}
