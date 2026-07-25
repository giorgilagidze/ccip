// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.17;

import { CCIPAdapterBase } from "./Base.t.sol";
import { CCIPAdapter } from "@src/adapters/CCIP/CCIPAdapter.sol";
import { BaseAdapter } from "@src/adapters/BaseAdapter.sol";
import { Errors } from "@src/lib/Errors.sol";

contract CCIPAdapterConstructorTest is CCIPAdapterBase {
    function test_revertsIfRouterIsZeroAddress() public {
        vm.expectRevert(Errors.ZERO_ADDRESS.selector);
        new CCIPAdapter(address(controller), address(0), address(0), new BaseAdapter.TrustedRemoteConfig[](0));
    }

    function test_wiresUpConfiguredTrustedRemoteControllerAndSelector() public view {
        assertEq(adapter.trustedRemote(CHAIN_ETH_MAINNET), remoteController);
        assertEq(adapter.toNativeChainId(CHAIN_ETH_MAINNET), uint256(SEL_ETH_MAINNET));
    }
}
