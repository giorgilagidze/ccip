// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.8;

/// @title Errors
/// @notice The errors thrown across the cross-chain contracts.
/// @custom:security-contact sirt@aragon.org
library Errors {
    // ---------------------------------------------------------------------
    // Generic / configuration
    // ---------------------------------------------------------------------

    /// @notice Thrown when a chain id of `0` is used. `0` is reserved as the
    ///         "unset" marker of the remote address maps.
    error INVALID_CHAIN_ID();

    /// @notice Thrown when the executor being set has no deployed code.
    error EXECUTOR_HAS_NO_CODE(address executor);

    /// @notice Thrown when a zero address is supplied where one is not allowed.
    error ZERO_ADDRESS();

    // ---------------------------------------------------------------------
    // Authorization
    // ---------------------------------------------------------------------

    /// @notice Thrown when `ccipReceive` is called by anything other than the
    ///         configured CCIP router.
    error CALLER_NOT_CCIP_ROUTER();

    /// @notice Thrown when the internal self-call entry point is called
    ///         externally.
    error CALLER_NOT_SELF(address caller);

    // ---------------------------------------------------------------------
    // Trusted remotes
    // ---------------------------------------------------------------------

    /// @notice Thrown when an inbound message originates from an address that is
    ///         not the trusted remote for its origin chain.
    error REMOTE_NOT_TRUSTED();

    /// @notice Thrown when the receiver for the destination chain is unset.
    error RECEIVER_ADDRESS_ZERO();

    // ---------------------------------------------------------------------
    // Chain id mapping
    // ---------------------------------------------------------------------

    /// @notice Thrown when a standard chain id has no bridge-native counterpart.
    error UNKNOWN_CHAIN_ID(uint256 chainId);

    /// @notice Thrown when a bridge-native chain id has no standard counterpart.
    error UNKNOWN_NATIVE_CHAIN_ID(uint256 nativeChainId);

    // ---------------------------------------------------------------------
    // Fees
    // ---------------------------------------------------------------------

    /// @notice Thrown when the pre-funded fee balance is below the quoted fee.
    /// @dev Distinct on purpose: ops alerts on exactly this to know when the
    ///      fee-paying contract must be topped up.
    error INSUFFICIENT_FEE_BALANCE(address feeToken, uint256 required, uint256 available);

    /// @notice Thrown when native value is sent while an ERC20 fee token is
    ///         configured (the value would be stranded).
    error UNEXPECTED_NATIVE_VALUE();

    /// @notice Thrown when a native currency transfer to the recipient failed.
    error NATIVE_TRANSFER_FAILED(address to, uint256 amount);

    // ---------------------------------------------------------------------
    // Defensive receive / retry
    // ---------------------------------------------------------------------

    /// @notice Thrown on the receive path when an inbound message reuses a
    ///         message id whose state is no longer `None`, i.e. it was already
    ///         delivered, executed or cancelled.
    error MESSAGE_ALREADY_DELIVERED_OR_EXECUTED(bytes32 messageId);

    /// @notice Thrown by `retryMessage` and `cancelMessage` when the message id
    ///         is not in the `Delivered` state. Only a delivered-but-failed
    ///         message can be retried or cancelled, so this covers a message
    ///         that was never delivered as well as one already executed or
    ///         cancelled.
    error MESSAGE_ALREADY_EXECUTED_OR_NOT_EXISTS(bytes32 messageId);

    /// @notice Thrown when the payload supplied to a retry does not match the
    ///         payload that was originally delivered for that message id.
    error PAYLOAD_MISMATCH(bytes32 messageId);
}
