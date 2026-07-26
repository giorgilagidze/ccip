// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.8;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { IDAO } from "@aragon/osx-commons-contracts/src/dao/IDAO.sol";
import { DaoAuthorizable } from "@aragon/osx-commons-contracts/src/permission/auth/DaoAuthorizable.sol";
import { Action, IExecutor } from "@aragon/osx-commons-contracts/src/executors/IExecutor.sol";

import { Errors } from "../lib/Errors.sol";
import { Permissions } from "../lib/Permissions.sol";
import { TransactionState } from "../lib/Transaction.sol";

import { IBaseAdapter } from "./IBaseAdapter.sol";

/// @title BaseAdapter
/// @notice Shared logic for bridge adapters.
/// @custom:security-contact sirt@aragon.org
abstract contract BaseAdapter is IBaseAdapter, DaoAuthorizable {
    using SafeERC20 for IERC20;

    /// @notice standard chain id -> remote trusted address allowed
    ///         to originate messages for that chain.
    mapping(uint256 => address) internal _trustedRemotes;

    /// @notice standard chain id -> remote adapter address that messages
    ///         bound for that chain are delivered to.
    mapping(uint256 => address) internal _remoteReceivers;

    /// @notice The executor that inbound payloads are executed on.
    address public executor;

    /// @notice bridge message id -> delivery/execution state.
    mapping(bytes32 => TransactionState) internal _messageState;

    /// @notice bridge message id -> hash of the delivered payload.
    /// @dev Only the hash is kept; a retry re-supplies the payload itself,
    ///      which is recoverable from the `MessageExecutionFailed` event.
    mapping(bytes32 => bytes32) internal _messagePayloadHash;

    /// @param _dao The DAO acting as this adapter's permission manager.
    /// @param _executor The executor inbound payloads are executed on. Pass the
    ///        DAO itself to keep execution on the DAO.
    /// @param _trustedRemoteConfigs The remote trusted config.
    /// @param _remoteReceiverConfigs The remote receiver config.
    constructor(
        IDAO _dao,
        address _executor,
        ChainAddressConfig[] memory _trustedRemoteConfigs,
        ChainAddressConfig[] memory _remoteReceiverConfigs
    )
        DaoAuthorizable(_dao)
    {
        _setExecutor(_executor);
        _setTrustedRemotes(_trustedRemoteConfigs);
        _setRemoteReceivers(_remoteReceiverConfigs);
    }

    /// @notice Allows the adapter to be pre-funded with native currency to pay
    ///         bridge fees, and to receive native refunds from the bridge.
    receive() external payable { }

    /// @notice Moves pre-funded fee assets out of this contract.
    /// @param _token The asset to move; `address(0)` for native currency.
    /// @param _to The recipient (typically the DAO).
    /// @param _amount The amount to move.
    function sweep(address _token, address _to, uint256 _amount) public virtual auth(Permissions.SWEEP_PERMISSION_ID) {
        if (_to == address(0)) revert Errors.ZERO_ADDRESS();

        if (_token == address(0)) {
            // solhint-disable-next-line avoid-low-level-calls
            (bool ok,) = _to.call{ value: _amount }("");
            if (!ok) revert Errors.NATIVE_TRANSFER_FAILED(_to, _amount);
        } else {
            IERC20(_token).safeTransfer(_to, _amount);
        }

        emit Swept(_token, _to, _amount);
    }

    /// @notice Repoints this adapter at a different executor.
    /// @dev Inbound payloads are routed to this executor address for execution.
    /// @param _executor The new executor address.
    function updateExecutor(address _executor) public virtual auth(Permissions.UPDATE_EXECUTOR_PERMISSION_ID) {
        _setExecutor(_executor);
    }

    /// @notice Sets or clears the remote addresses trusted to originate
    ///         messages for their respective chains.
    /// @param _trustedRemoteConfigs The remote trusted config.
    function updateTrustedRemotes(ChainAddressConfig[] memory _trustedRemoteConfigs)
        public
        virtual
        auth(Permissions.UPDATE_REMOTES_PERMISSION_ID)
    {
        _setTrustedRemotes(_trustedRemoteConfigs);
    }

    /// @notice Sets or clears the remote adapter addresses that messages bound
    ///         for their respective chains are delivered to.
    /// @param _remoteReceiverConfigs The remote receiver config.
    function updateRemoteReceivers(ChainAddressConfig[] memory _remoteReceiverConfigs)
        public
        virtual
        auth(Permissions.UPDATE_REMOTES_PERMISSION_ID)
    {
        _setRemoteReceivers(_remoteReceiverConfigs);
    }

    /// @notice Re-executes a message that was delivered but whose execution
    ///         reverted.
    /// @param _messageId The bridge message id of the failed message.
    /// @param _payload The payload originally delivered for `_messageId`,
    ///        recoverable from the `MessageExecutionFailed` event.
    function retryMessage(bytes32 _messageId, bytes memory _payload)
        public
        virtual
        auth(Permissions.RETRY_MESSAGE_PERMISSION_ID)
    {
        if (_messageState[_messageId] != TransactionState.Delivered) {
            revert Errors.MESSAGE_ALREADY_EXECUTED_OR_NOT_EXISTS(_messageId);
        }

        if (keccak256(_payload) != _messagePayloadHash[_messageId]) {
            revert Errors.PAYLOAD_MISMATCH(_messageId);
        }

        _messageState[_messageId] = TransactionState.Executed;
        delete _messagePayloadHash[_messageId];

        this.executeActions(_messageId, _payload);

        emit MessageRetried(_messageId);
    }

    /// @notice Cancels a delivered-but-failed message so it can never execute.
    /// @dev Only a `Delivered` (failed, pending-retry) message can be cancelled.
    ///      The message id stays occupied (state becomes `Cancelled`, not
    ///      `None`), so the same message can never be re-delivered or retried.
    /// @param _messageId The bridge message id to cancel.
    function cancelMessage(bytes32 _messageId) public virtual auth(Permissions.CANCEL_MESSAGE_PERMISSION_ID) {
        if (_messageState[_messageId] != TransactionState.Delivered) {
            revert Errors.MESSAGE_ALREADY_EXECUTED_OR_NOT_EXISTS(_messageId);
        }

        _messageState[_messageId] = TransactionState.Cancelled;
        delete _messagePayloadHash[_messageId];

        emit MessageCancelled(_messageId);
    }

    /// @notice Returns the state of a message.
    /// @param _messageId The bridge message id.
    /// @return The state of the message (None, Delivered, Executed, Cancelled).
    function getMessageState(bytes32 _messageId) public view virtual returns (TransactionState) {
        return _messageState[_messageId];
    }

    /// @notice The remote adapter trusted to originate messages for a chain.
    /// @param _chainId The standard chain id.
    /// @return The trusted remote adapter address, or zero if unset.
    function trustedRemote(uint256 _chainId) public view returns (address) {
        return _trustedRemotes[_chainId];
    }

    /// @notice The remote ADAPTER that messages bound for a chain are sent to.
    /// @param _chainId The standard chain id.
    /// @return The remote receiver address, or zero if unset.
    function remoteReceiver(uint256 _chainId) public view returns (address) {
        return _remoteReceivers[_chainId];
    }

    /// @notice Once adapter receives a message, this forwards it to the executor.
    /// @param _messageId The bridge-level message identifier.
    /// @param _payload The encoded `Action[]` message.
    /// @param _originChainId The standard chain id the message came from.
    function _forwardMessage(bytes32 _messageId, bytes memory _payload, uint256 _originChainId) internal {
        // Either the message is already delivered or executed.
        if (_messageState[_messageId] != TransactionState.None) {
            revert Errors.MESSAGE_ALREADY_DELIVERED_OR_EXECUTED(_messageId);
        }

        // The self-call also contains payload decoding, so a malformed payload
        // is captured for retry rather than reverting the bridge delivery.
        try this.executeActions(_messageId, _payload) {
            _messageState[_messageId] = TransactionState.Executed;

            emit MessageReceived(_originChainId, _messageId, _payload);
        } catch (bytes memory reason) {
            _messageState[_messageId] = TransactionState.Delivered;
            _messagePayloadHash[_messageId] = keccak256(_payload);

            emit MessageExecutionFailed(_originChainId, _messageId, _payload, reason);
        }
    }

    /// @notice Decodes and executes an authenticated payload on the executor.
    /// @dev External only so it can be wrapped in `try/catch`; callable
    ///      exclusively by this contract.
    /// @param _messageId The bridge message id passed to the executor.
    /// @param _payload The encoded `Action[]` message.
    function executeActions(bytes32 _messageId, bytes memory _payload) external {
        if (msg.sender != address(this)) {
            revert Errors.CALLER_NOT_SELF(msg.sender);
        }

        Action[] memory actions = abi.decode(_payload, (Action[]));

        IExecutor(executor).execute(_messageId, actions, 0);
    }

    /// @notice Helper function used by `updateExecutor` and the constructor.
    function _setExecutor(address _executor) internal {
        if (_executor == address(0)) revert Errors.ZERO_ADDRESS();
        if (_executor.code.length == 0) revert Errors.EXECUTOR_HAS_NO_CODE(_executor);

        emit ExecutorUpdated(executor, _executor);

        executor = _executor;
    }

    /// @notice Sets the trusted remotes for receiving messages.
    function _setTrustedRemotes(ChainAddressConfig[] memory _trustedRemoteConfigs) internal {
        for (uint256 i = 0; i < _trustedRemoteConfigs.length; i++) {
            uint256 chainId = _trustedRemoteConfigs[i].standardChainId;
            if (chainId == 0) revert Errors.INVALID_CHAIN_ID();

            address trustedRemote_ = _trustedRemoteConfigs[i].remote;
            _trustedRemotes[chainId] = trustedRemote_;

            emit TrustedRemoteSet(chainId, trustedRemote_);
        }
    }

    /// @notice Sets the remote receivers for sending messages.
    ///        Generally, it should be this adapter's counterpart
    ///        on the destination chain.
    function _setRemoteReceivers(ChainAddressConfig[] memory _remoteReceiverConfigs) internal {
        for (uint256 i = 0; i < _remoteReceiverConfigs.length; i++) {
            uint256 chainId = _remoteReceiverConfigs[i].standardChainId;
            if (chainId == 0) revert Errors.INVALID_CHAIN_ID();

            address remoteReceiver_ = _remoteReceiverConfigs[i].remote;
            _remoteReceivers[chainId] = remoteReceiver_;

            emit RemoteReceiverSet(chainId, remoteReceiver_);
        }
    }
}
