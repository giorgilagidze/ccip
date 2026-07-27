// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.17;

import { CCIPAdapterBase } from "./Base.t.sol";
import { Client } from "@chainlink/contracts-ccip/contracts/libraries/Client.sol";
import { CCIPAdapter } from "@src/adapters/CCIP/CCIPAdapter.sol";
import { Errors } from "@src/lib/Errors.sol";
import { Permissions } from "@src/lib/Permissions.sol";
import { ERC20Mock } from "@mocks/ERC20Mock.sol";
import { CCIPRouterMock } from "@mocks/CCIPRouterMock.sol";

contract CCIPAdapterSendMessageTest is CCIPAdapterBase {
    // -------------------------------------------------------------------------
    // Authorization -- `sendMessage` is role-gated.
    // -------------------------------------------------------------------------

    function test_revertsIfCallerLacksSendMessageRole() public {
        vm.expectRevert(_missingRoleError(alice, Permissions.SEND_MESSAGE_ROLE));
        vm.prank(alice);
        adapter.sendMessage(CHAIN_ETH_MAINNET, 200_000, "");
    }

    function test_succeedsForCallerWithSendMessageRole() public {
        _grantAllPermissions();
        router.setFee(0.01 ether);
        vm.deal(address(adapter), 0.01 ether);

        vm.prank(alice);
        adapter.sendMessage(CHAIN_ETH_MAINNET, 200_000, "");

        assertEq(router.ccipSendCallCount(), 1);
    }

    // -------------------------------------------------------------------------
    // Receiver resolution -- taken from `_remoteReceivers`, not a parameter.
    // -------------------------------------------------------------------------

    function test_revertsIfNoRemoteReceiverConfiguredForDestination() public {
        _grantAllPermissions();

        // CHAIN_BASE is mapped as a CCIP selector but has no remote receiver.
        vm.expectRevert(Errors.RECEIVER_ADDRESS_ZERO.selector);
        adapter.sendMessage(CHAIN_BASE, 200_000, "");
    }

    function test_revertsIfRemoteReceiverWasCleared() public {
        _setRemoteReceiver(adapter, CHAIN_ETH_MAINNET, address(0));

        vm.expectRevert(Errors.RECEIVER_ADDRESS_ZERO.selector);
        adapter.sendMessage(CHAIN_ETH_MAINNET, 200_000, "");
    }

    function test_targetsTheConfiguredRemoteReceiver() public {
        _grantAllPermissions();
        router.setFee(0.01 ether);
        vm.deal(address(adapter), 0.01 ether);

        adapter.sendMessage(CHAIN_ETH_MAINNET, 200_000, "");

        assertEq(abi.decode(router.lastReceiver(), (address)), remoteAdapter);
    }

    /// @dev Repointing the receiver must change where the next send goes.
    function test_usesTheUpdatedReceiverAfterUpdateRemoteReceivers() public {
        address newReceiver = makeAddr("newRemoteReceiver");
        _setRemoteReceiver(adapter, CHAIN_ETH_MAINNET, newReceiver);

        router.setFee(0.01 ether);
        vm.deal(address(adapter), 0.01 ether);

        adapter.sendMessage(CHAIN_ETH_MAINNET, 200_000, "");

        assertEq(abi.decode(router.lastReceiver(), (address)), newReceiver);
    }

    function test_revertsForUnmappedDestinationChainId() public {
        _grantAllPermissions();
        _setRemoteReceiver(adapter, 999_999, remoteAdapter);

        vm.expectRevert(abi.encodeWithSelector(Errors.UNKNOWN_CHAIN_ID.selector, uint256(999_999)));
        adapter.sendMessage(999_999, 200_000, "");
    }

    // -------------------------------------------------------------------------
    // Fees -- the ADAPTER is pre-funded and pays.
    // -------------------------------------------------------------------------

    function test_nativeFee_paysExactFeeFromAdapterBalance() public {
        _grantAllPermissions();
        uint256 feeAmount = 0.05 ether;
        router.setFee(feeAmount);
        vm.deal(address(adapter), feeAmount);

        adapter.sendMessage(CHAIN_ETH_MAINNET, 200_000, "");

        assertEq(router.lastMsgValue(), feeAmount, "router must receive exactly the quoted fee");
        assertEq(address(adapter).balance, 0, "the whole pre-funded balance must have gone to the fee");
    }

    function test_nativeFee_revertsIfAdapterBalanceInsufficient() public {
        _grantAllPermissions();
        uint256 feeAmount = 1 ether;
        uint256 available = 0.5 ether;
        router.setFee(feeAmount);
        vm.deal(address(adapter), available);

        vm.expectRevert(
            abi.encodeWithSelector(Errors.INSUFFICIENT_FEE_BALANCE.selector, address(0), feeAmount, available)
        );
        adapter.sendMessage(CHAIN_ETH_MAINNET, 200_000, "");
    }

    /// @dev Regression test for the missing `forceApprove`: an adapter that
    ///      never approves the router would make `CCIPRouterMock`'s
    ///      `transferFrom` pull revert on zero allowance.
    function test_erc20Fee_approvesRouterAndRouterPullsExactFee() public {
        _grantAllPermissions();
        uint256 feeAmount = 3 ether;
        router.setFee(feeAmount);
        feeTokenErc20.setBalance(address(erc20Adapter), feeAmount);

        erc20Adapter.sendMessage(CHAIN_ETH_MAINNET, 200_000, "hello");

        assertEq(router.ccipSendCallCount(), 1);
        assertEq(feeTokenErc20.balanceOf(address(router)), feeAmount, "router must have pulled the fee");
    }

    function test_erc20Fee_leavesZeroStandingAllowanceOnAdapterAfterSend() public {
        _grantAllPermissions();
        uint256 feeAmount = 3 ether;
        router.setFee(feeAmount);
        feeTokenErc20.setBalance(address(erc20Adapter), feeAmount);

        erc20Adapter.sendMessage(CHAIN_ETH_MAINNET, 200_000, "");

        assertEq(feeTokenErc20.allowance(address(erc20Adapter), address(router)), 0);
    }

    function test_erc20Fee_revertsIfAdapterBalanceInsufficient() public {
        _grantAllPermissions();
        uint256 feeAmount = 1 ether;
        uint256 available = 0.4 ether;
        router.setFee(feeAmount);
        feeTokenErc20.setBalance(address(erc20Adapter), available);

        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.INSUFFICIENT_FEE_BALANCE.selector, address(feeTokenErc20), feeAmount, available
            )
        );
        erc20Adapter.sendMessage(CHAIN_ETH_MAINNET, 200_000, "");
    }

    function test_erc20Fee_revertsIfNativeValueSentWhileErc20FeeTokenConfigured() public {
        _grantAllPermissions();
        router.setFee(1 ether);
        feeTokenErc20.setBalance(address(erc20Adapter), 1 ether);
        vm.deal(alice, 1 ether);

        vm.expectRevert(Errors.UNEXPECTED_NATIVE_VALUE.selector);
        vm.prank(alice);
        erc20Adapter.sendMessage{ value: 1 ether }(CHAIN_ETH_MAINNET, 200_000, "");
    }

    // -------------------------------------------------------------------------
    // End-to-end routing.
    // -------------------------------------------------------------------------

    function test_endToEnd_routesThroughAdapterToRouter() public {
        _grantAllPermissions();

        uint256 feeAmount = 0.02 ether;
        router.setFee(feeAmount);
        vm.deal(address(adapter), feeAmount);

        bytes32 expectedMessageId = keccak256("expected-message-id");
        router.setNextMessageId(expectedMessageId);

        bytes memory payload = _emptyActionsPayload();
        uint256 gasLimit = 300_000;

        (bytes32 messageId, uint256 fee) = adapter.sendMessage(CHAIN_ETH_MAINNET, gasLimit, payload);

        assertEq(messageId, expectedMessageId);
        assertEq(fee, feeAmount);

        assertEq(abi.decode(router.lastReceiver(), (address)), remoteAdapter, "router must target the remote receiver");
        assertEq(router.lastData(), payload, "the payload must reach the bridge verbatim");
        assertEq(router.lastFeeToken(), address(0));
        assertEq(router.lastDestChainSelector(), SEL_ETH_MAINNET);
        assertEq(router.lastMsgValue(), feeAmount);
        assertEq(router.lastCaller(), address(adapter), "CCIP must see the adapter as the sender");

        bytes memory expectedExtraArgs =
            Client._argsToBytes(Client.GenericExtraArgsV2({ gasLimit: gasLimit, allowOutOfOrderExecution: true }));
        assertEq(router.lastExtraArgs(), expectedExtraArgs, "extraArgs must encode the requested gas limit");
    }

    // -------------------------------------------------------------------------
    // Immutables are per-adapter.
    // -------------------------------------------------------------------------

    /// @dev Two adapters, two fee tokens, two routers: a send through adapter A
    ///      must resolve A's OWN immutables and hit ONLY router A.
    function test_immutables_twoAdaptersRouteExclusivelyToTheirOwnRouterAndFeeToken() public {
        _grantAllPermissions();

        CCIPRouterMock routerB = new CCIPRouterMock();
        ERC20Mock feeTokenB = new ERC20Mock("Fee Token B", "FEEB");
        CCIPAdapter adapterB = new CCIPAdapter(
            address(daoMock),
            address(daoMock),
            address(routerB),
            address(feeTokenB),
            _config(CHAIN_BASE, remoteController),
            _config(CHAIN_BASE, remoteAdapter),
            _chainIdMappingConfig(CHAIN_BASE, uint256(SEL_BASE))
        );

        router.setFee(1 ether);
        routerB.setFee(2 ether);
        feeTokenErc20.setBalance(address(erc20Adapter), 1 ether);
        feeTokenB.setBalance(address(adapterB), 2 ether);

        erc20Adapter.sendMessage(CHAIN_ETH_MAINNET, 200_000, "");

        assertEq(router.ccipSendCallCount(), 1);
        assertEq(router.lastFeeToken(), address(feeTokenErc20));
        assertEq(routerB.ccipSendCallCount(), 0, "adapter A's send must not touch router B at all");
    }

    // -------------------------------------------------------------------------
    // Fee-token immutability trade-off: no `setFeeToken`.
    // -------------------------------------------------------------------------

    /// @dev There is no setter to rotate `FEE_TOKEN` -- it is `immutable`.
    ///      Rotating means deploying a SECOND `CCIPAdapter` and moving the
    ///      permission/funding over to it.
    function test_feeTokenRotation_requiresDeployingANewAdapter() public {
        _grantAllPermissions();

        router.setFee(1 ether);
        feeTokenErc20.setBalance(address(erc20Adapter), 1 ether);
        erc20Adapter.sendMessage(CHAIN_ETH_MAINNET, 200_000, "");
        assertEq(router.lastFeeToken(), address(feeTokenErc20));

        ERC20Mock newFeeToken = new ERC20Mock("New Fee Token", "NEWFEE");
        CCIPAdapter newAdapter = new CCIPAdapter(
            address(daoMock),
            address(daoMock),
            address(router),
            address(newFeeToken),
            _config(CHAIN_ETH_MAINNET, remoteController),
            _config(CHAIN_ETH_MAINNET, remoteAdapter),
            _chainIdMappingConfig(CHAIN_ETH_MAINNET, uint256(SEL_ETH_MAINNET))
        );

        _grantRole(newAdapter, Permissions.SEND_MESSAGE_ROLE, address(this));

        router.setFee(1 ether);
        newFeeToken.setBalance(address(newAdapter), 1 ether);
        newAdapter.sendMessage(CHAIN_ETH_MAINNET, 200_000, "");

        assertEq(router.lastFeeToken(), address(newFeeToken), "send must now use the new adapter's fee token");
    }
}
