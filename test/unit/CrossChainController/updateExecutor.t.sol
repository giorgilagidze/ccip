// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.17;

import { CrossChainControllerBase } from "./Base.t.sol";
import { Errors } from "@src/lib/Errors.sol";
import { Action } from "@aragon/osx-commons-contracts/src/executors/IExecutor.sol";
import { DaoUnauthorized } from "@aragon/osx-commons-contracts/src/permission/auth/auth.sol";
import { CrossChainControllerDAOMock } from "@mocks/CrossChainControllerDAOMock.sol";
import { IDAO } from "@aragon/osx-commons-contracts/src/dao/IDAO.sol";

contract CrossChainControllerUpdateExecutorTest is CrossChainControllerBase {
    // -------------------------------------------------------------------------
    // Initial state.
    // -------------------------------------------------------------------------

    /// @dev The fixture initializes the controller with the DAO as executor.
    function test_initializeSetsExecutor() public view {
        assertEq(controller.executor(), address(daoMock));
    }

    function test_initializeRevertsOnZeroExecutor() public {
        vm.expectRevert(Errors.ZERO_ADDRESS.selector);
        deployController(address(daoMock), address(0));
    }

    function test_initializeRevertsOnCodelessExecutor() public {
        address eoa = makeAddr("eoaExecutor");
        vm.expectRevert(abi.encodeWithSelector(Errors.EXECUTOR_HAS_NO_CODE.selector, eoa));
        deployController(address(daoMock), eoa);
    }

    /// @dev The proxy is initialized by the fixture; a second call must revert.
    function test_initializeRevertsOnSecondCall() public {
        vm.expectRevert("Initializable: contract is already initialized");
        controller.initialize(IDAO(address(daoMock)), address(daoMock), false);
    }

    // -------------------------------------------------------------------------
    // Validation.
    // -------------------------------------------------------------------------

    function test_revertsOnZeroExecutor() public {
        vm.expectRevert(Errors.ZERO_ADDRESS.selector);
        vm.prank(alice);
        controller.updateExecutor(address(0));
    }

    /// @dev A codeless executor would make `execute` succeed silently, so it
    ///      must be rejected at set time rather than stranding messages later.
    function test_revertsOnCodelessExecutor() public {
        address eoa = makeAddr("eoaExecutor");

        vm.expectRevert(abi.encodeWithSelector(Errors.EXECUTOR_HAS_NO_CODE.selector, eoa));
        vm.prank(alice);
        controller.updateExecutor(eoa);

        // The previous executor is untouched by the failed update.
        assertEq(controller.executor(), address(daoMock));
    }

    // -------------------------------------------------------------------------
    // Auth.
    // -------------------------------------------------------------------------

    function test_revertsIfCallerUnauthorized() public {
        CrossChainControllerDAOMock newExecutor = new CrossChainControllerDAOMock();

        vm.expectRevert(
            abi.encodeWithSelector(
                DaoUnauthorized.selector, address(daoMock), address(controller), bob, updateExecutorPermissionId
            )
        );
        vm.prank(bob);
        controller.updateExecutor(address(newExecutor));
    }

    // -------------------------------------------------------------------------
    // Happy path.
    // -------------------------------------------------------------------------

    function test_updatesExecutorAndEmits() public {
        CrossChainControllerDAOMock newExecutor = new CrossChainControllerDAOMock();

        vm.expectEmit(true, true, true, true, address(controller));
        emit ExecutorUpdated(address(daoMock), address(newExecutor));

        vm.prank(alice);
        controller.updateExecutor(address(newExecutor));

        assertEq(controller.executor(), address(newExecutor));
    }

    /// @dev Repointing must remain possible during an incident, so it is NOT
    ///      gated by `whenNotPaused` -- mirroring `updateConfig`.
    function test_stillWorksWhilePaused() public {
        CrossChainControllerDAOMock newExecutor = new CrossChainControllerDAOMock();

        vm.prank(alice);
        controller.pause();

        vm.prank(alice);
        controller.updateExecutor(address(newExecutor));

        assertEq(controller.executor(), address(newExecutor));
    }

    // -------------------------------------------------------------------------
    // The executor is actually the contract execution is routed to.
    // -------------------------------------------------------------------------

    /// @dev Proves the swap has teeth: after repointing, an inbound message
    ///      executes on the NEW executor and not on the original DAO.
    function test_inboundMessageExecutesOnTheNewExecutor() public {
        _configureLane(CHAIN_ID, address(adapterA), remoteAdapterA);

        CrossChainControllerDAOMock newExecutor = new CrossChainControllerDAOMock();
        vm.prank(alice);
        controller.updateExecutor(address(newExecutor));

        // The ORIGINAL executor is rigged to revert. If execution still routed
        // there, the payload would be captured as failed instead of executed.
        daoMock.setExecuteReverts(true);

        CounterTarget counter = new CounterTarget();
        Action[] memory actions = new Action[](1);
        actions[0] = Action({ to: address(counter), value: 0, data: abi.encodeCall(CounterTarget.increment, ()) });
        bytes memory message = abi.encode(actions);

        vm.prank(address(adapterA));
        controller.receiveMessage(bytes32(uint256(1)), _encodedTx(1, CHAIN_ID, message), CHAIN_ID);

        // Ran through the new executor.
        assertEq(counter.count(), 1);
    }
}

/// @notice Minimal target that counts calls, to observe that execution ran.
/// @dev DO NOT USE IN PRODUCTION! Test-only.
contract CounterTarget {
    uint256 public count;

    function increment() external {
        count += 1;
    }
}
