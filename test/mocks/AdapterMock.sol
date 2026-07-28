// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.17;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IBaseAdapter } from "@src/adapters/IBaseAdapter.sol";
import { Errors } from "@src/lib/Errors.sol";

/// @notice A bridge-less `IBaseAdapter` implementation used to drive
///         `CrossChainController`'s send path in isolation.
/// @dev DO NOT USE IN PRODUCTION!
///
///      This mock is deliberately built the way a REAL Option-1 adapter must
///      be built: its send path touches NO storage. Every knob is an
///      `immutable` set at construction, and the call is recorded by EMITTING
///      an event rather than by writing state — writing state would land in
///      the controller's slots, which is exactly the bug this design exists to
///      avoid. Tests configure behaviour by deploying a differently
///      parameterised mock, not by calling a setter.
contract AdapterMock is IBaseAdapter {
    address private immutable CONTROLLER;
    address private immutable FEE_TOKEN;
    uint256 private immutable FEE;
    bytes32 private immutable MESSAGE_ID;
    address private immutable FEE_SINK;
    bool private immutable REVERT_ON_SEND;
    bool private immutable REVERT_ON_QUOTE;

    /// @notice Emitted by `sendMessage`; the only record this mock keeps.
    /// @param context `address(this)` at execution time — the CONTROLLER when
    ///        the mock is reached by `delegatecall`, as it must be.
    event SendMessageCalled(
        address context, address receiver, uint256 destinationChainId, uint256 gasLimit, bytes message, uint256 value
    );

    /// @param controller_ The owning `CrossChainController`.
    /// @param feeToken_ The fee token to report/charge; `address(0)` native.
    /// @param fee_ The fee amount to report/charge.
    /// @param messageId_ The bridge message id `sendMessage` returns.
    /// @param feeSink_ Where the charged fee is sent, standing in for the
    ///        bridge router pulling payment from the fee payer.
    /// @param revertOnSend_ Make `sendMessage` revert.
    /// @param revertOnQuote_ Make `quoteFee` revert.
    constructor(
        address controller_,
        address feeToken_,
        uint256 fee_,
        bytes32 messageId_,
        address feeSink_,
        bool revertOnSend_,
        bool revertOnQuote_
    ) {
        CONTROLLER = controller_;
        FEE_TOKEN = feeToken_;
        FEE = fee_;
        MESSAGE_ID = messageId_;
        FEE_SINK = feeSink_;
        REVERT_ON_SEND = revertOnSend_;
        REVERT_ON_QUOTE = revertOnQuote_;
    }

    // -------------------------------------------------------------------------
    // IBaseAdapter
    // -------------------------------------------------------------------------

    function CROSS_CHAIN_CONTROLLER() external view override returns (address) {
        return CONTROLLER;
    }

    function toNativeChainId(uint256 _chainId) external pure override returns (uint256) {
        return _chainId;
    }

    function fromNativeChainId(uint256 _chainId) external pure override returns (uint256) {
        return _chainId;
    }

    function quoteFee(address _receiver, uint256 _destinationChainId, uint256 _gasLimit, bytes calldata _message)
        external
        view
        override
        returns (address, uint256)
    {
        (_receiver, _destinationChainId, _gasLimit, _message);
        // solhint-disable-next-line custom-errors, reason-string
        if (REVERT_ON_QUOTE) revert("AdapterMock: quoteFee reverted");
        return (FEE_TOKEN, FEE);
    }

    /// @dev Mirrors a real adapter: guards the execution context, checks the
    ///      FEE PAYER's balance (which under `delegatecall` is the controller's)
    ///      and moves the fee out of it.
    function sendMessage(address _receiver, uint256 _destinationChainId, uint256 _gasLimit, bytes calldata _message)
        external
        payable
        override
        returns (uint256 messageId, uint256 fee)
    {
        if (address(this) != CONTROLLER) {
            revert Errors.SEND_PATH_NOT_DELEGATECALLED(address(this));
        }
        // solhint-disable-next-line custom-errors, reason-string
        if (REVERT_ON_SEND) revert("AdapterMock: sendMessage reverted");

        address feeToken = FEE_TOKEN;
        fee = FEE;

        if (feeToken == address(0)) {
            uint256 balance = address(this).balance;
            if (balance < fee) {
                revert Errors.INSUFFICIENT_FEE_BALANCE(address(0), fee, balance);
            }
            if (fee != 0) {
                // solhint-disable-next-line avoid-low-level-calls
                (bool ok,) = FEE_SINK.call{ value: fee }("");
                if (!ok) revert Errors.NATIVE_TRANSFER_FAILED(FEE_SINK, fee);
            }
        } else {
            if (msg.value != 0) revert Errors.UNEXPECTED_NATIVE_VALUE();

            uint256 balance = IERC20(feeToken).balanceOf(address(this));
            if (balance < fee) {
                revert Errors.INSUFFICIENT_FEE_BALANCE(feeToken, fee, balance);
            }
            if (fee != 0) {
                // solhint-disable-next-line custom-errors, reason-string
                require(IERC20(feeToken).transfer(FEE_SINK, fee), "AdapterMock: fee transfer failed");
            }
        }

        emit SendMessageCalled(address(this), _receiver, _destinationChainId, _gasLimit, _message, msg.value);

        messageId = uint256(MESSAGE_ID);
    }
}
