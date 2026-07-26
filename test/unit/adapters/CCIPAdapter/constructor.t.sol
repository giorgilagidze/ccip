// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.17;

import { CCIPAdapterBase } from "./Base.t.sol";
import { CCIPAdapter } from "@src/adapters/CCIP/CCIPAdapter.sol";
import { IBaseAdapter } from "@src/adapters/IBaseAdapter.sol";
import { Errors } from "@src/lib/Errors.sol";
import { IDAO } from "@aragon/osx-commons-contracts/src/dao/IDAO.sol";

contract CCIPAdapterConstructorTest is CCIPAdapterBase {
    IBaseAdapter.ChainAddressConfig[] internal empty;

    function test_revertsIfRouterIsZeroAddress() public {
        vm.expectRevert(Errors.ZERO_ADDRESS.selector);
        new CCIPAdapter(IDAO(address(daoMock)), address(daoMock), address(0), address(0), empty, empty);
    }

    function test_revertsIfExecutorIsZeroAddress() public {
        vm.expectRevert(Errors.ZERO_ADDRESS.selector);
        new CCIPAdapter(IDAO(address(daoMock)), address(0), address(router), address(0), empty, empty);
    }

    function test_revertsIfExecutorHasNoCode() public {
        address eoa = makeAddr("executorWithoutCode");

        vm.expectRevert(abi.encodeWithSelector(Errors.EXECUTOR_HAS_NO_CODE.selector, eoa));
        new CCIPAdapter(IDAO(address(daoMock)), eoa, address(router), address(0), empty, empty);
    }

    function test_revertsIfATrustedRemoteConfigUsesChainIdZero() public {
        vm.expectRevert(Errors.INVALID_CHAIN_ID.selector);
        new CCIPAdapter(
            IDAO(address(daoMock)),
            address(daoMock),
            address(router),
            address(0),
            _config(0, remoteController),
            empty
        );
    }

    function test_revertsIfARemoteReceiverConfigUsesChainIdZero() public {
        vm.expectRevert(Errors.INVALID_CHAIN_ID.selector);
        new CCIPAdapter(
            IDAO(address(daoMock)), address(daoMock), address(router), address(0), empty, _config(0, remoteAdapter)
        );
    }

    function test_wiresUpDaoExecutorRouterAndFeeToken() public view {
        assertEq(address(adapter.dao()), address(daoMock));
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
