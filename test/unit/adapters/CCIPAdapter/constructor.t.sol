// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.17;

import { CCIPAdapterBase } from "./Base.t.sol";
import { CCIPAdapter } from "@src/adapters/CCIP/CCIPAdapter.sol";
import { IBaseAdapter } from "@src/adapters/IBaseAdapter.sol";
import { Errors } from "@src/lib/Errors.sol";

contract CCIPAdapterConstructorTest is CCIPAdapterBase {
    IBaseAdapter.ChainAddressConfig[] internal empty;
    IBaseAdapter.ChainIdMappingConfig[] internal emptyChainIdMappings;

    function test_revertsIfRouterIsZeroAddress() public {
        vm.expectRevert(Errors.ZERO_ADDRESS.selector);
        new CCIPAdapter(
            address(daoMock), address(daoMock), address(0), address(0), empty, empty, emptyChainIdMappings
        );
    }

    function test_revertsIfExecutorIsZeroAddress() public {
        vm.expectRevert(Errors.ZERO_ADDRESS.selector);
        new CCIPAdapter(
            address(daoMock), address(0), address(router), address(0), empty, empty, emptyChainIdMappings
        );
    }

    function test_revertsIfExecutorHasNoCode() public {
        address eoa = makeAddr("executorWithoutCode");

        vm.expectRevert(abi.encodeWithSelector(Errors.EXECUTOR_HAS_NO_CODE.selector, eoa));
        new CCIPAdapter(address(daoMock), eoa, address(router), address(0), empty, empty, emptyChainIdMappings);
    }

    function test_revertsIfATrustedRemoteConfigUsesChainIdZero() public {
        vm.expectRevert(Errors.INVALID_CHAIN_ID.selector);
        new CCIPAdapter(
            address(daoMock),
            address(daoMock),
            address(router),
            address(0),
            _config(0, remoteController),
            empty,
            emptyChainIdMappings
        );
    }

    function test_revertsIfARemoteReceiverConfigUsesChainIdZero() public {
        vm.expectRevert(Errors.INVALID_CHAIN_ID.selector);
        new CCIPAdapter(
            address(daoMock),
            address(daoMock),
            address(router),
            address(0),
            empty,
            _config(0, remoteAdapter),
            emptyChainIdMappings
        );
    }

    function test_revertsIfAChainIdMappingConfigUsesChainIdZero() public {
        vm.expectRevert(Errors.INVALID_CHAIN_ID.selector);
        new CCIPAdapter(
            address(daoMock),
            address(daoMock),
            address(router),
            address(0),
            empty,
            empty,
            _chainIdMappingConfig(0, uint256(SEL_ETH_MAINNET))
        );
    }

    function test_revertsIfASelectorExceedsUint64() public {
        uint256 tooLarge = uint256(type(uint64).max) + 1;

        vm.expectRevert();
        new CCIPAdapter(
            address(daoMock),
            address(daoMock),
            address(router),
            address(0),
            empty,
            empty,
            _chainIdMappingConfig(CHAIN_ETH_MAINNET, tooLarge)
        );
    }

    function test_revertsIfAdminIsZeroAddress() public {
        vm.expectRevert(Errors.ZERO_ADDRESS.selector);
        new CCIPAdapter(address(0), address(daoMock), address(router), address(0), empty, empty, emptyChainIdMappings);
    }

    function test_grantsDefaultAdminRoleToAdmin() public view {
        assertTrue(adapter.hasRole(adapter.DEFAULT_ADMIN_ROLE(), address(daoMock)));
        assertFalse(adapter.hasRole(adapter.DEFAULT_ADMIN_ROLE(), alice));
    }

    function test_wiresUpAdminExecutorRouterAndFeeToken() public view {
        assertEq(adapter.executor(), address(daoMock));
        assertEq(address(adapter.CCIP_ROUTER()), address(router));
        assertEq(adapter.FEE_TOKEN(), address(0));
        assertEq(erc20Adapter.FEE_TOKEN(), address(feeTokenErc20));
    }

    function test_wiresUpConfiguredRemotesAndSelector() public view {
        assertEq(adapter.trustedRemote(CHAIN_ETH_MAINNET), remoteController);
        assertEq(adapter.remoteReceiver(CHAIN_ETH_MAINNET), remoteAdapter);
        assertEq(adapter.toNativeChainId(CHAIN_ETH_MAINNET), uint256(SEL_ETH_MAINNET));
    }
}
