// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.17;

import { CCIPAdapterBase } from "./Base.t.sol";
import { IBaseAdapter } from "@src/adapters/IBaseAdapter.sol";
import { Errors } from "@src/lib/Errors.sol";
import { Permissions } from "@src/lib/Permissions.sol";
import { DaoUnauthorized } from "@aragon/osx-commons-contracts/src/permission/auth/auth.sol";

contract CCIPAdapterTrustedRemoteTest is CCIPAdapterBase {
    // -------------------------------------------------------------------------
    // Reads
    // -------------------------------------------------------------------------

    function test_returnsZeroForUnsetChain() public view {
        assertEq(adapter.trustedRemote(CHAIN_BASE), address(0));
        assertEq(adapter.remoteReceiver(CHAIN_BASE), address(0));
    }

    function test_returnsConfiguredRemotesForSetChain() public view {
        assertEq(adapter.trustedRemote(CHAIN_ETH_MAINNET), remoteController);
        assertEq(adapter.remoteReceiver(CHAIN_ETH_MAINNET), remoteAdapter);
    }

    /// @dev The two directions are independent mappings: setting one must not
    ///      leak into the other.
    function test_trustedRemoteAndRemoteReceiverAreIndependent() public {
        address inbound = makeAddr("inboundOnly");
        _setTrustedRemote(adapter, CHAIN_BASE, inbound);

        assertEq(adapter.trustedRemote(CHAIN_BASE), inbound);
        assertEq(adapter.remoteReceiver(CHAIN_BASE), address(0), "setting inbound must not set outbound");
    }

    // -------------------------------------------------------------------------
    // updateTrustedRemotes
    // -------------------------------------------------------------------------

    function test_updateTrustedRemotes_revertsForUnauthorizedCaller() public {
        IBaseAdapter.ChainAddressConfig[] memory configs = _config(CHAIN_BASE, remoteController);

        vm.expectRevert(
            abi.encodeWithSelector(
                DaoUnauthorized.selector,
                address(daoMock),
                address(adapter),
                alice,
                Permissions.UPDATE_REMOTES_PERMISSION_ID
            )
        );
        vm.prank(alice);
        adapter.updateTrustedRemotes(configs);
    }

    function test_updateTrustedRemotes_setsAndEmits() public {
        _grantAllPermissions();
        IBaseAdapter.ChainAddressConfig[] memory configs = _config(CHAIN_BASE, remoteController);

        vm.expectEmit(true, true, true, true, address(adapter));
        emit IBaseAdapter.TrustedRemoteSet(CHAIN_BASE, remoteController);

        adapter.updateTrustedRemotes(configs);

        assertEq(adapter.trustedRemote(CHAIN_BASE), remoteController);
    }

    function test_updateTrustedRemotes_clearsWithZeroAddress() public {
        _setTrustedRemote(adapter, CHAIN_ETH_MAINNET, address(0));

        assertEq(adapter.trustedRemote(CHAIN_ETH_MAINNET), address(0));
    }

    function test_updateTrustedRemotes_revertsForChainIdZero() public {
        _grantAllPermissions();
        IBaseAdapter.ChainAddressConfig[] memory configs = _config(0, remoteController);

        vm.expectRevert(Errors.INVALID_CHAIN_ID.selector);
        adapter.updateTrustedRemotes(configs);
    }

    // -------------------------------------------------------------------------
    // updateRemoteReceivers
    // -------------------------------------------------------------------------

    function test_updateRemoteReceivers_revertsForUnauthorizedCaller() public {
        IBaseAdapter.ChainAddressConfig[] memory configs = _config(CHAIN_BASE, remoteAdapter);

        vm.expectRevert(
            abi.encodeWithSelector(
                DaoUnauthorized.selector,
                address(daoMock),
                address(adapter),
                alice,
                Permissions.UPDATE_REMOTES_PERMISSION_ID
            )
        );
        vm.prank(alice);
        adapter.updateRemoteReceivers(configs);
    }

    function test_updateRemoteReceivers_setsAndEmits() public {
        _grantAllPermissions();
        IBaseAdapter.ChainAddressConfig[] memory configs = _config(CHAIN_BASE, remoteAdapter);

        vm.expectEmit(true, true, true, true, address(adapter));
        emit IBaseAdapter.RemoteReceiverSet(CHAIN_BASE, remoteAdapter);

        adapter.updateRemoteReceivers(configs);

        assertEq(adapter.remoteReceiver(CHAIN_BASE), remoteAdapter);
    }

    function test_updateRemoteReceivers_revertsForChainIdZero() public {
        _grantAllPermissions();
        IBaseAdapter.ChainAddressConfig[] memory configs = _config(0, remoteAdapter);

        vm.expectRevert(Errors.INVALID_CHAIN_ID.selector);
        adapter.updateRemoteReceivers(configs);
    }

    function test_updateRemoteReceivers_appliesEveryEntryInABatch() public {
        _grantAllPermissions();
        address baseReceiver = makeAddr("baseReceiver");
        address arbReceiver = makeAddr("arbReceiver");

        IBaseAdapter.ChainAddressConfig[] memory configs = new IBaseAdapter.ChainAddressConfig[](2);
        configs[0] = IBaseAdapter.ChainAddressConfig({ standardChainId: CHAIN_BASE, remote: baseReceiver });
        configs[1] = IBaseAdapter.ChainAddressConfig({ standardChainId: CHAIN_ARBITRUM_ONE, remote: arbReceiver });

        adapter.updateRemoteReceivers(configs);

        assertEq(adapter.remoteReceiver(CHAIN_BASE), baseReceiver);
        assertEq(adapter.remoteReceiver(CHAIN_ARBITRUM_ONE), arbReceiver);
    }
}
