// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.8;

/// @title Permissions
/// @notice The access control roles used across the cross-chain contracts.
/// @custom:security-contact sirt@aragon.org
library Permissions {
    /// @notice Role allowed to send a message to a remote chain.
    bytes32 internal constant SEND_MESSAGE_ROLE = keccak256("SEND_MESSAGE_ROLE");

    /// @notice Role allowed to (re)configure the per-chain routing config: the
    ///         trusted senders messages are accepted from, the receivers
    ///         messages are sent to, and the standard <-> bridge-native chain
    ///         id mappings.
    bytes32 internal constant UPDATE_CHAIN_CONFIG_ROLE = keccak256("UPDATE_CHAIN_CONFIG_ROLE");

    /// @notice Role allowed to retry a message whose execution reverted on
    ///         arrival. Intended for the DAO and/or an ops multisig, since the
    ///         payload itself was already authenticated by the bridge.
    bytes32 internal constant RETRY_MESSAGE_ROLE = keccak256("RETRY_MESSAGE_ROLE");

    /// @notice Role allowed to cancel a delivered-but-failed message so it can
    ///         never be retried. Intended for the DAO and/or an ops multisig.
    bytes32 internal constant CANCEL_MESSAGE_ROLE = keccak256("CANCEL_MESSAGE_ROLE");

    /// @notice Role allowed to move pre-funded fee assets out of this contract.
    bytes32 internal constant SWEEP_ROLE = keccak256("SWEEP_ROLE");

    /// @notice Role allowed to pause and unpause the message paths
    ///         (forward / receive / retry / cancel).
    bytes32 internal constant PAUSE_ROLE = keccak256("PAUSE_ROLE");

    /// @notice Role allowed to repoint this adapter at a different executor.
    bytes32 internal constant UPDATE_EXECUTOR_ROLE = keccak256("UPDATE_EXECUTOR_ROLE");
}
