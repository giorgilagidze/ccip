// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.8;

import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import { IRouterClient } from "@chainlink/contracts-ccip/contracts/interfaces/IRouterClient.sol";
import { Client } from "@chainlink/contracts-ccip/contracts/libraries/Client.sol";
import { IAny2EVMMessageReceiver } from "@chainlink/contracts-ccip/contracts/interfaces/IAny2EVMMessageReceiver.sol";

import { IDAO } from "@aragon/osx-commons-contracts/src/dao/IDAO.sol";

import { Errors } from "../../lib/Errors.sol";

import { BaseAdapter } from "../BaseAdapter.sol";
import { IBaseAdapter } from "../IBaseAdapter.sol";
import { Permissions } from "../../lib/Permissions.sol";

/// @title CCIPAdapter
/// @notice Chainlink CCIP implementation of `IBaseAdapter`.
/// @custom:security-contact sirt@aragon.org
contract CCIPAdapter is IERC165, IAny2EVMMessageReceiver, BaseAdapter {
    using SafeERC20 for IERC20;

    /// @notice The CCIP Router address.
    IRouterClient public immutable CCIP_ROUTER;

    /// @notice The fee token used to pay bridge fees.
    ///         `address(0)` = chain's native currency.
    address public immutable FEE_TOKEN;

    /// @notice The receive function must only allow CCIP router.
    // forge-lint: disable-next-line(unwrapped-modifier-logic)
    modifier onlyRouter() {
        if (msg.sender != address(CCIP_ROUTER)) {
            revert Errors.CALLER_NOT_CCIP_ROUTER();
        }

        _;
    }

    /// @param _dao The DAO acting as this adapter's permission manager.
    /// @param _executor The executor inbound payloads are executed on.
    /// @param _ccipRouter The CCIP router on this chain.
    /// @param _feeToken The fee token, or `address(0)` for native. IMMUTABLE.
    /// @param _trustedRemoteConfigs The remote trusted config.
    /// @param _remoteReceiverConfigs The remote receiver config.
    /// @param _chainIdMappingConfigs The standard chain id <-> CCIP chain selector
    ///        mappings. Each `nativeChainId` must fit in a `uint64`.
    constructor(
        IDAO _dao,
        address _executor,
        address _ccipRouter,
        address _feeToken,
        ChainAddressConfig[] memory _trustedRemoteConfigs,
        ChainAddressConfig[] memory _remoteReceiverConfigs,
        ChainIdMappingConfig[] memory _chainIdMappingConfigs
    )
        BaseAdapter(_dao, _executor, _trustedRemoteConfigs, _remoteReceiverConfigs, _chainIdMappingConfigs)
    {
        if (_ccipRouter == address(0)) revert Errors.ZERO_ADDRESS();

        CCIP_ROUTER = IRouterClient(_ccipRouter);
        FEE_TOKEN = _feeToken;
    }

    /// @inheritdoc IBaseAdapter
    function quoteFee(uint256 _destinationChainId, uint256 _gasLimit, bytes calldata _message)
        public
        view
        virtual
        override
        returns (address, uint256)
    {
        // The counterpart adapter on the destination chain.
        address receiver = _remoteReceivers[_destinationChainId];
        if (receiver == address(0)) revert Errors.RECEIVER_ADDRESS_ZERO();

        // Reverts if not set.
        uint64 nativeChainId = SafeCast.toUint64(toNativeChainId(_destinationChainId));

        return (FEE_TOKEN, CCIP_ROUTER.getFee(nativeChainId, _buildMessage(receiver, _gasLimit, _message, FEE_TOKEN)));
    }

    /// @inheritdoc IBaseAdapter
    function sendMessage(uint256 _destinationChainId, uint256 _gasLimit, bytes calldata _message)
        public
        payable
        virtual
        override
        auth(Permissions.SEND_MESSAGE_PERMISSION_ID)
        returns (bytes32 messageId, uint256 fee)
    {
        // The counterpart adapter on the destination chain.
        address receiver = _remoteReceivers[_destinationChainId];
        if (receiver == address(0)) revert Errors.RECEIVER_ADDRESS_ZERO();

        // Reverts if not set.
        uint64 nativeChainId = SafeCast.toUint64(toNativeChainId(_destinationChainId));

        Client.EVM2AnyMessage memory ccipMessage = _buildMessage(receiver, _gasLimit, _message, FEE_TOKEN);

        // CCIP does not refund overpayment, so quote and pay exactly.
        fee = CCIP_ROUTER.getFee(nativeChainId, ccipMessage);

        if (FEE_TOKEN == address(0)) {
            uint256 balance = address(this).balance;
            if (balance < fee) {
                revert Errors.INSUFFICIENT_FEE_BALANCE(address(0), fee, balance);
            }

            messageId = CCIP_ROUTER.ccipSend{ value: fee }(nativeChainId, ccipMessage);
        } else {
            if (msg.value != 0) revert Errors.UNEXPECTED_NATIVE_VALUE();

            uint256 balance = IERC20(FEE_TOKEN).balanceOf(address(this));
            if (balance < fee) {
                revert Errors.INSUFFICIENT_FEE_BALANCE(FEE_TOKEN, fee, balance);
            }

            IERC20(FEE_TOKEN).forceApprove(address(CCIP_ROUTER), fee);

            messageId = CCIP_ROUTER.ccipSend(nativeChainId, ccipMessage);

            // Leave no standing allowance.
            IERC20(FEE_TOKEN).forceApprove(address(CCIP_ROUTER), 0);
        }
    }

    /// @inheritdoc IAny2EVMMessageReceiver
    function ccipReceive(Client.Any2EVMMessage calldata message) public virtual onlyRouter {
        address srcAddress = abi.decode(message.sender, (address));

        // Transform CCIP's chain selector into the standard chain Id.
        uint256 originChainId = fromNativeChainId(message.sourceChainSelector);

        if (srcAddress == address(0) || _trustedRemotes[originChainId] != srcAddress) {
            revert Errors.REMOTE_NOT_TRUSTED();
        }

        _forwardMessage(message.messageId, message.data, originChainId);
    }

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) public pure virtual returns (bool) {
        return interfaceId == type(IAny2EVMMessageReceiver).interfaceId || interfaceId == type(IBaseAdapter).interfaceId
            || interfaceId == type(IERC165).interfaceId;
    }

    // -------------------------------------------------------------------------
    // Internal
    // -------------------------------------------------------------------------

    /// @inheritdoc BaseAdapter
    /// @dev CCIP chain selectors are `uint64`, so an oversized value is rejected
    ///      at write time rather than reverting later on the send path.
    function _setChainIdMappings(ChainIdMappingConfig[] memory _chainIdMappingConfigs) internal virtual override {
        for (uint256 i = 0; i < _chainIdMappingConfigs.length; i++) {
            SafeCast.toUint64(_chainIdMappingConfigs[i].nativeChainId);
        }

        super._setChainIdMappings(_chainIdMappingConfigs);
    }

    /// @notice Builds the CCIP message for a send or a quote.
    /// @dev Shared by `quoteFee` and `sendMessage` so a quote always describes
    ///      exactly the message that would be sent.
    /// @param _receiver The counterpart adapter on the destination chain.
    /// @param _gasLimit The gas limit for cross-chain execution.
    /// @param _message The encoded `Action[]` payload.
    /// @param _feeToken The fee token; `address(0)` for native currency.
    /// @return The CCIP message to quote or send.
    function _buildMessage(address _receiver, uint256 _gasLimit, bytes memory _message, address _feeToken)
        internal
        pure
        virtual
        returns (Client.EVM2AnyMessage memory)
    {
        bytes memory extraArgs = Client._argsToBytes(
            Client.GenericExtraArgsV2({ gasLimit: _gasLimit, allowOutOfOrderExecution: true })
        );

        return Client.EVM2AnyMessage({
            receiver: abi.encode(_receiver),
            data: _message,
            tokenAmounts: new Client.EVMTokenAmount[](0),
            extraArgs: extraArgs,
            feeToken: _feeToken
        });
    }
}
