// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.17;

import { Test } from "forge-std/Test.sol";

import { Client } from "@chainlink/contracts-ccip/contracts/libraries/Client.sol";

import { CCIPAdapter } from "@src/adapters/CCIP/CCIPAdapter.sol";
import { IBaseAdapter } from "@src/adapters/IBaseAdapter.sol";
import { ChainIds } from "@src/lib/ChainIds.sol";
import { Action } from "@aragon/osx-commons-contracts/src/executors/IExecutor.sol";
import { IDAO } from "@aragon/osx-commons-contracts/src/dao/IDAO.sol";
import { DAOMock } from "@osx-test/mocks/commons/dao/DAOMock.sol";
import { ERC20Mock } from "@mocks/ERC20Mock.sol";
import { CCIPRouterMock } from "@mocks/CCIPRouterMock.sol";

/// @title CCIPAdapterBase
/// @notice Shared fixture for the per-function `CCIPAdapter` unit tests:
///         deploys the DAO (which doubles as the executor), router, fee token,
///         and the adapter instances the suite needs, plus inbound-message and
///         remote-config helpers.
abstract contract CCIPAdapterBase is Test {
    // -------------------------------------------------------------------------
    // Real CCIP chain selectors / standard chain ids used throughout.
    // -------------------------------------------------------------------------

    uint64 internal constant SEL_ETH_MAINNET = 5009297550715157269;
    uint64 internal constant SEL_BASE = 15971525489660198786;
    uint64 internal constant SEL_ARBITRUM_ONE = 4949039107694359620;
    // A real CCIP selector the adapter does NOT map (Sepolia is intentionally
    // absent from the production map), used to exercise the unmapped path.
    uint64 internal constant SEL_SEPOLIA = 16015286601757825753;

    // Standard chain ids come from `ChainIds` (src/lib/ChainIds.sol).
    uint256 internal constant CHAIN_ETH_MAINNET = ChainIds.ETHEREUM;
    uint256 internal constant CHAIN_BASE = ChainIds.BASE;
    uint256 internal constant CHAIN_ARBITRUM_ONE = ChainIds.ARBITRUM_ONE;

    // Events come from `IBaseAdapter` (inherited), so `vm.expectEmit` can
    // `emit` them without a local redeclaration.

    DAOMock internal daoMock;
    CCIPRouterMock internal router;
    ERC20Mock internal feeTokenErc20;

    /// @dev Default adapter from `setUp`: native (`address(0)`) fee token.
    CCIPAdapter internal adapter;
    /// @dev A second adapter sharing `router`, but with `FEE_TOKEN = feeTokenErc20`.
    ///      `FEE_TOKEN` is immutable, so an ERC20-fee lane needs its own adapter
    ///      instance -- there is no setter to flip `adapter` itself over.
    CCIPAdapter internal erc20Adapter;

    address internal alice;
    /// @dev The remote chain's ADAPTER as seen on the RECEIVE path -- the
    ///      address CCIP reports as the message sender. This is what
    ///      `_trustedRemotes[chainId]` holds.
    address internal remoteController;
    /// @dev The remote chain's ADAPTER as the SEND target -- what
    ///      `_remoteReceivers[chainId]` holds and the router is asked to
    ///      deliver to. NEVER a valid value for `_trustedRemotes` in these
    ///      tests, so the two directions stay distinguishable.
    address internal remoteAdapter;

    function setUp() public virtual {
        alice = makeAddr("alice");
        remoteController = makeAddr("remoteController");
        remoteAdapter = makeAddr("remoteAdapter");

        daoMock = new DAOMock();
        router = new CCIPRouterMock();
        feeTokenErc20 = new ERC20Mock("Fee Token", "FEE");

        IBaseAdapter.ChainAddressConfig[] memory trustedRemotes = new IBaseAdapter.ChainAddressConfig[](1);
        trustedRemotes[0] =
            IBaseAdapter.ChainAddressConfig({ standardChainId: CHAIN_ETH_MAINNET, remote: remoteController });

        IBaseAdapter.ChainAddressConfig[] memory remoteReceivers = new IBaseAdapter.ChainAddressConfig[](1);
        remoteReceivers[0] =
            IBaseAdapter.ChainAddressConfig({ standardChainId: CHAIN_ETH_MAINNET, remote: remoteAdapter });

        adapter = new CCIPAdapter(
            IDAO(address(daoMock)),
            address(daoMock), // executor
            address(router),
            address(0), // native fee token
            trustedRemotes,
            remoteReceivers,
            _defaultChainIdMappings()
        );

        erc20Adapter = new CCIPAdapter(
            IDAO(address(daoMock)),
            address(daoMock),
            address(router),
            address(feeTokenErc20),
            trustedRemotes,
            remoteReceivers,
            _defaultChainIdMappings()
        );
    }

    /// @dev The chain id mappings the suite assumes are configured: the three
    ///      chains the fixtures exercise. `SEL_SEPOLIA` is deliberately left
    ///      out so the unmapped paths stay reachable.
    function _defaultChainIdMappings() internal pure returns (IBaseAdapter.ChainIdMappingConfig[] memory configs) {
        configs = new IBaseAdapter.ChainIdMappingConfig[](3);
        configs[0] =
            IBaseAdapter.ChainIdMappingConfig({ standardChainId: CHAIN_ETH_MAINNET, nativeChainId: uint256(SEL_ETH_MAINNET) });
        configs[1] = IBaseAdapter.ChainIdMappingConfig({ standardChainId: CHAIN_BASE, nativeChainId: uint256(SEL_BASE) });
        configs[2] = IBaseAdapter.ChainIdMappingConfig({
            standardChainId: CHAIN_ARBITRUM_ONE,
            nativeChainId: uint256(SEL_ARBITRUM_ONE)
        });
    }

    /// @dev A single-entry chain id config array, for constructor arguments.
    function _chainIdMappingConfig(uint256 standardChainId, uint256 nativeChainId)
        internal
        pure
        returns (IBaseAdapter.ChainIdMappingConfig[] memory configs)
    {
        configs = new IBaseAdapter.ChainIdMappingConfig[](1);
        configs[0] =
            IBaseAdapter.ChainIdMappingConfig({ standardChainId: standardChainId, nativeChainId: nativeChainId });
    }

    // -------------------------------------------------------------------------
    // Helpers
    // -------------------------------------------------------------------------

    /// @dev `DAOMock.hasPermission` is a single flag that authorizes EVERY
    ///      permission once toggled; only flip it inside tests that need it.
    function _grantAllPermissions() internal {
        daoMock.setHasPermissionReturnValueMock(true);
    }

    /// @dev Points `_remoteReceivers[chainId]` at `receiver` on `target`.
    ///      Grants every permission in the process.
    function _setRemoteReceiver(CCIPAdapter target, uint256 chainId, address receiver) internal {
        _grantAllPermissions();
        IBaseAdapter.ChainAddressConfig[] memory configs = new IBaseAdapter.ChainAddressConfig[](1);
        configs[0] = IBaseAdapter.ChainAddressConfig({ standardChainId: chainId, remote: receiver });
        target.updateRemoteReceivers(configs);
    }

    /// @dev Points `_trustedRemotes[chainId]` at `trusted` on `target`.
    ///      Grants every permission in the process.
    function _setTrustedRemote(CCIPAdapter target, uint256 chainId, address trusted) internal {
        _grantAllPermissions();
        IBaseAdapter.ChainAddressConfig[] memory configs = new IBaseAdapter.ChainAddressConfig[](1);
        configs[0] = IBaseAdapter.ChainAddressConfig({ standardChainId: chainId, remote: trusted });
        target.updateTrustedRemotes(configs);
    }

    /// @dev A single-entry config array, for constructor arguments.
    function _config(uint256 chainId, address remote)
        internal
        pure
        returns (IBaseAdapter.ChainAddressConfig[] memory configs)
    {
        configs = new IBaseAdapter.ChainAddressConfig[](1);
        configs[0] = IBaseAdapter.ChainAddressConfig({ standardChainId: chainId, remote: remote });
    }

    function _buildInbound(uint64 selector, address sender, bytes memory data)
        internal
        pure
        returns (Client.Any2EVMMessage memory)
    {
        return Client.Any2EVMMessage({
            messageId: keccak256("default-inbound-message"),
            sourceChainSelector: selector,
            sender: abi.encode(sender),
            data: data,
            destTokenAmounts: new Client.EVMTokenAmount[](0)
        });
    }

    function _emptyActionsPayload() internal pure returns (bytes memory) {
        return abi.encode(new Action[](0));
    }
}
