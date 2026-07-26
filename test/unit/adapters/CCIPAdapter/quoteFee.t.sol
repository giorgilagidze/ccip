// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.17;

import { CCIPAdapterBase } from "./Base.t.sol";
import { Errors } from "@src/lib/Errors.sol";

contract CCIPAdapterQuoteFeeTest is CCIPAdapterBase {
    function test_revertsIfDestinationHasNoConfiguredReceiver() public {
        // `CHAIN_BASE` is a mapped chain id, but no remote receiver is set for it.
        vm.expectRevert(Errors.RECEIVER_ADDRESS_ZERO.selector);
        adapter.quoteFee(CHAIN_BASE, 200_000, "");
    }

    function test_revertsIfBridgeChainIdIsZero() public {
        vm.expectRevert(Errors.RECEIVER_ADDRESS_ZERO.selector);
        adapter.quoteFee(0, 200_000, "");
    }

    function test_returnsRouterQuoteAndConfiguredFeeToken() public {
        router.setFee(7 ether);

        (address feeToken, uint256 fee) = erc20Adapter.quoteFee(CHAIN_ETH_MAINNET, 200_000, "");

        assertEq(feeToken, address(feeTokenErc20));
        assertEq(fee, 7 ether);
    }

    function test_quotesTheReceiverThatSendMessageWouldUse() public {
        _grantAllPermissions();
        router.setFee(3 ether);

        (, uint256 fee) = adapter.quoteFee(CHAIN_ETH_MAINNET, 200_000, "");

        vm.deal(address(adapter), fee);
        vm.prank(alice);
        (, uint256 paid) = adapter.sendMessage(CHAIN_ETH_MAINNET, 200_000, "");

        assertEq(paid, fee);
        assertEq(router.lastReceiver(), abi.encode(remoteAdapter));
    }
}
