// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.17;

import { CCIPAdapterBase } from "./Base.t.sol";
import { Client } from "@chainlink/contracts-ccip/contracts/libraries/Client.sol";
import { CCIPAdapter } from "@src/adapters/CCIP/CCIPAdapter.sol";
import { IBaseAdapter } from "@src/adapters/IBaseAdapter.sol";
import { Errors } from "@src/lib/Errors.sol";
import { TransactionState } from "@src/lib/Transaction.sol";
import { IDAO } from "@aragon/osx-commons-contracts/src/dao/IDAO.sol";
import { ExecutorMock } from "@mocks/ExecutorMock.sol";

contract CCIPAdapterCcipReceiveTest is CCIPAdapterBase {
    function test_revertsIfCallerNotRouter() public {
        Client.Any2EVMMessage memory message = _buildInbound(SEL_ETH_MAINNET, remoteController, "");

        vm.expectRevert(Errors.CALLER_NOT_CCIP_ROUTER.selector);
        vm.prank(alice);
        adapter.ccipReceive(message);
    }

    function test_revertsIfDecodedSenderIsZero() public {
        Client.Any2EVMMessage memory message = _buildInbound(SEL_ETH_MAINNET, address(0), "");

        vm.expectRevert(Errors.REMOTE_NOT_TRUSTED.selector);
        vm.prank(address(router));
        adapter.ccipReceive(message);
    }

    function test_revertsIfSenderIsAnArbitraryUntrustedAddress() public {
        address untrusted = makeAddr("untrusted");
        Client.Any2EVMMessage memory message = _buildInbound(SEL_ETH_MAINNET, untrusted, "");

        vm.expectRevert(Errors.REMOTE_NOT_TRUSTED.selector);
        vm.prank(address(router));
        adapter.ccipReceive(message);
    }

    /// @dev The send target and the trusted sender are separate config entries.
    ///      An inbound message from the SEND target must still be rejected
    ///      unless it is also registered as the trusted remote.
    function test_revertsIfSenderIsRemoteReceiverInsteadOfTrustedRemote() public {
        Client.Any2EVMMessage memory message = _buildInbound(SEL_ETH_MAINNET, remoteAdapter, "");

        vm.expectRevert(Errors.REMOTE_NOT_TRUSTED.selector);
        vm.prank(address(router));
        adapter.ccipReceive(message);
    }

    /// @dev The success path: sender IS the trusted remote. The payload is a
    ///      raw encoded `Action[]`, executed on the executor and keyed by the
    ///      bridge's own `messageId`.
    function test_succeedsWhenSenderIsTrustedRemoteAndExecutes() public {
        bytes memory payload = _emptyActionsPayload();
        bytes32 messageId = keccak256("msg-1");

        Client.Any2EVMMessage memory message = _buildInbound(SEL_ETH_MAINNET, remoteController, payload);
        message.messageId = messageId;

        vm.expectEmit(true, true, true, true, address(adapter));
        emit IBaseAdapter.MessageReceived(CHAIN_ETH_MAINNET, messageId, payload);

        vm.prank(address(router));
        adapter.ccipReceive(message);

        assertEq(uint256(adapter.getMessageState(messageId)), uint256(TransactionState.Executed));
    }

    /// @dev A message arriving from a selector never mapped to a standard chain
    ///      id must revert, not be silently treated as chain `0`.
    function test_revertsForUnmappedSourceSelector() public {
        uint64 unmappedSelector = 1234567890; // not in the adapter's map
        Client.Any2EVMMessage memory message = _buildInbound(unmappedSelector, remoteController, "");

        vm.expectRevert(abi.encodeWithSelector(Errors.UNKNOWN_NATIVE_CHAIN_ID.selector, uint256(unmappedSelector)));
        vm.prank(address(router));
        adapter.ccipReceive(message);
    }

    /// @dev The same bridge message id must never be delivered twice.
    function test_revertsIfMessageIdAlreadyDelivered() public {
        Client.Any2EVMMessage memory message =
            _buildInbound(SEL_ETH_MAINNET, remoteController, _emptyActionsPayload());

        vm.prank(address(router));
        adapter.ccipReceive(message);

        vm.expectRevert(
            abi.encodeWithSelector(Errors.MESSAGE_ALREADY_DELIVERED_OR_EXECUTED.selector, message.messageId)
        );
        vm.prank(address(router));
        adapter.ccipReceive(message);
    }

    // -------------------------------------------------------------------------
    // Deliver-but-fail: a reverting payload must NOT revert bridge delivery.
    // -------------------------------------------------------------------------

    /// @dev Builds an adapter whose executor can be made to revert on demand.
    function _adapterWithFailingExecutor() internal returns (CCIPAdapter failAdapter, ExecutorMock executorMock) {
        executorMock = new ExecutorMock();
        failAdapter = new CCIPAdapter(
            IDAO(address(daoMock)),
            address(executorMock),
            address(router),
            address(0),
            _config(CHAIN_ETH_MAINNET, remoteController),
            _config(CHAIN_ETH_MAINNET, remoteAdapter),
            _chainIdMappingConfig(CHAIN_ETH_MAINNET, uint256(SEL_ETH_MAINNET))
        );
    }

    function test_failedExecution_isRecordedAsDeliveredInsteadOfReverting() public {
        (CCIPAdapter failAdapter, ExecutorMock executorMock) = _adapterWithFailingExecutor();
        executorMock.setShouldRevert(true);

        bytes memory payload = _emptyActionsPayload();
        Client.Any2EVMMessage memory message = _buildInbound(SEL_ETH_MAINNET, remoteController, payload);

        // Delivery itself must succeed, so the bridge never sees a revert.
        vm.prank(address(router));
        failAdapter.ccipReceive(message);

        assertEq(
            uint256(failAdapter.getMessageState(message.messageId)),
            uint256(TransactionState.Delivered),
            "a failed payload must be retained as Delivered"
        );
    }

    function test_malformedPayload_isCapturedForRetryInsteadOfReverting() public {
        // Not a valid `Action[]` encoding: decoding reverts inside the self-call.
        bytes memory malformed = hex"deadbeef";
        Client.Any2EVMMessage memory message = _buildInbound(SEL_ETH_MAINNET, remoteController, malformed);

        vm.prank(address(router));
        adapter.ccipReceive(message);

        assertEq(
            uint256(adapter.getMessageState(message.messageId)),
            uint256(TransactionState.Delivered),
            "a malformed payload must be captured, not revert delivery"
        );
    }
}
