// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.8;

/// @title IBaseAdapter
interface IBaseAdapter {
    /// @notice A standard chain id paired with a remote address.
    /// @dev Used for both directions: as a trusted sender when receiving, and
    ///      as the receiver when sending. Which one is meant is determined by
    ///      the setter it is passed to.
    /// @param standardChainId The standard chain id of remote chain.
    /// @param remote The remote address for that chain.
    struct ChainAddressConfig {
        uint256 standardChainId;
        address remote;
    }

    /// @notice Emitted when a trusted remote is set or cleared.
    event TrustedRemoteSet(uint256 indexed chainId, address trustedRemote);

    /// @notice Emitted when a remote receiver is set or cleared.
    event RemoteReceiverSet(uint256 indexed chainId, address remoteReceiver);

    /// @notice Emitted when the executor is set or repointed.
    event ExecutorUpdated(address indexed oldExecutor, address indexed newExecutor);

    /// @notice Emitted when pre-funded fee assets are moved out of this contract.
    /// @param token The asset moved; `address(0)` for native currency.
    /// @param to The recipient.
    /// @param amount The amount moved.
    event Swept(address indexed token, address indexed to, uint256 amount);

    /// @notice Emitted when an inbound message executed successfully.
    event MessageReceived(uint256 indexed originChainId, bytes32 indexed messageId, bytes payload);

    /// @notice Emitted when an inbound message was delivered but its execution
    ///         reverted. The payload is included so a retry can re-supply it.
    event MessageExecutionFailed(uint256 indexed originChainId, bytes32 indexed messageId, bytes payload, bytes reason);

    /// @notice Emitted when a previously failed message executed on retry.
    event MessageRetried(bytes32 indexed messageId);

    /// @notice Emitted when a delivered-but-failed message is cancelled.
    event MessageCancelled(bytes32 indexed messageId);

    /// @notice Transforms standard chain id into adapter's own custom chain Ids.
    /// @param _chainId The standard chain Id.
    /// @return The transformed chain id into adapter's custom id.
    /// @dev MUST revert for unmapped chain ids instead of returning `0`.
    function toNativeChainId(uint256 _chainId) external view returns (uint256);

    /// @notice Transforms adapter's own custom chain Id into standard chain id.
    /// @param _chainId The custom chain id of adapter.
    /// @return The transformed chain id into standard chain id.
    /// @dev MUST revert for unmapped chain ids instead of returning `0`.
    function fromNativeChainId(uint256 _chainId) external view returns (uint256);

    /// @notice Quotes the bridge fee for a given message.
    /// @dev Quotes the exact message `sendMessage` would send: the receiver is
    ///      resolved from the adapter's own remote-receiver config for
    ///      `_destinationChainId`, so the quote always matches the send.
    /// @param _destinationChainId The standard destination chain id; the adapter
    ///        converts it to its own native chain id internally.
    /// @param _gasLimit The gas limit for cross-chain execution.
    /// @param _message Encoded message.
    /// @return feeToken The token the fee is denominated in. `address(0)`
    ///         means the chain's native currency.
    /// @return fee The amount of `feeToken` required to send the message.
    function quoteFee(uint256 _destinationChainId, uint256 _gasLimit, bytes calldata _message)
        external
        view
        returns (address feeToken, uint256 fee);

    /// @notice Sends a message over the bridge.
    /// @dev The receiver is resolved from the adapter's own remote-receiver
    ///      config for `_destinationChainId`. The fee is paid out of this
    ///      adapter's own pre-funded balance.
    /// @param _destinationChainId The standard destination chain id; the adapter
    ///        converts it to its own native chain id internally.
    /// @param _gasLimit The gas limit for cross-chain execution.
    /// @param _message Encoded message.
    /// @return messageId The bridge's message identifier.
    /// @return fee The amount actually paid, for event reporting.
    function sendMessage(uint256 _destinationChainId, uint256 _gasLimit, bytes calldata _message)
        external
        payable
        returns (bytes32 messageId, uint256 fee);
}
