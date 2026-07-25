// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.8;

/// @title Permissions
/// @notice The permission ids used across the cross-chain contracts.
/// @custom:security-contact sirt@aragon.org
library Permissions {
    /// @notice Permission to forward a message to a remote chain.
    bytes32 internal constant FORWARD_MESSAGE_PERMISSION_ID = keccak256("FORWARD_MESSAGE_PERMISSION");

    /// @notice Permission to (re)configure the config.
    bytes32 internal constant UPDATE_CONFIG_PERMISSION_ID = keccak256("UPDATE_CONFIG_PERMISSION");

    /// @notice Permission to retry a message whose execution reverted on
    ///         arrival. Intended for the DAO and/or an ops multisig, since the
    ///         payload itself was already authenticated by the bridge.
    bytes32 internal constant RETRY_MESSAGE_PERMISSION_ID = keccak256("RETRY_MESSAGE_PERMISSION");

    /// @notice Permission to cancel a delivered-but-failed message so it can
    ///         never be retried. Intended for the DAO and/or an ops multisig.
    bytes32 internal constant CANCEL_MESSAGE_PERMISSION_ID = keccak256("CANCEL_MESSAGE_PERMISSION");

    /// @notice Permission to move pre-funded fee assets out of this contract.
    bytes32 internal constant SWEEP_PERMISSION_ID = keccak256("SWEEP_PERMISSION");

    /// @notice Permission to pause and unpause the message paths
    ///         (forward / receive / retry / cancel).
    bytes32 internal constant PAUSE_PERMISSION_ID = keccak256("PAUSE_PERMISSION");

    /// @notice Permission to repoint this controller at a different executor.
    bytes32 internal constant UPDATE_EXECUTOR_PERMISSION_ID = keccak256("UPDATE_EXECUTOR_PERMISSION");

    /// @notice Permission to permanently freeze the controller's implementation,
    ///         making every future upgrade impossible. One-way and irreversible.
    bytes32 internal constant FREEZE_UPGRADE_PERMISSION_ID = keccak256("FREEZE_UPGRADE_PERMISSION");

    /// @notice The DAO's own execute permission. Held BY the controller ON the
    ///         DAO, so inbound messages can be executed when the DAO itself is
    ///         the configured executor.
    /// @dev Mirrors `DAO.EXECUTE_PERMISSION_ID`; redeclared here so the plugin
    ///      setup does not have to import the full `DAO` contract.
    bytes32 internal constant EXECUTE_PERMISSION_ID = keccak256("EXECUTE_PERMISSION");
}
