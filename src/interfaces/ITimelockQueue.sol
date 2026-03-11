// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {DataTypes} from "../helpers/DataTypes.sol";
import {Errors} from "../helpers/Errors.sol";
import {Events} from "../helpers/Events.sol";

interface ITimelockQueue {

    //queue an approved proposal for execution
    function queue(
        bytes32 proposalId,
        address target,
        address token,
        uint256 amount,
        bytes calldata callData
    ) external returns (uint256 unlockTime);

    //execute a queued proposal after unlock time
    function execute(bytes32 proposalId) external;

    //cancel a queued proposal before execution
    function cancel(bytes32 proposalId) external;

    //check if a proposal is queued
    function isQueued(bytes32 proposalId) external view returns (bool);

    //check if a proposal has been executed
    function isExecuted(bytes32 proposalId) external view returns (bool);

    //check if a proposal has been cancelled
    function isCancelled(bytes32 proposalId) external view returns (bool);

    //get the full queued item data
    function getQueuedItem(bytes32 proposalId) external view returns (DataTypes.TimeLockEntry memory);

    //get the unlock time of a queued proposal
    function getUnlockTime(bytes32 proposalId) external view returns (uint256);

    //get the minimum delay time
    function getMinDelay() external view returns (uint256);

    //update the minimum delay - only governance
    function updateMinDelay(uint256 newDelay) external;

    //check if a proposal is ready to execute
    function isReady(bytes32 proposalId) external view returns (bool);

}