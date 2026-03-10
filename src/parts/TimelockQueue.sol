// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../helpers/DataTypes.sol";
import "../helpers/Errors.sol";
import "../helpers/Events.sol";
import "../interfaces/ITimelockQueue.sol";
import "../interfaces/IProposalEngine.sol";
import "../main/SecurityBase.sol";

contract TimelockQueue is SecurityBase, ITimelockQueue {

    //store all queued items
    mapping(bytes32 => DataTypes.TimeLockEntry) private _queue;

    //proposal engine address
    address public proposalEngine;

    //minimum delay before execution
    uint256 public minDelay;

    //maximum delay before proposal expires
    uint256 public constant MAX_DELAY = 30 days;

    //default minimum delay
    uint256 public constant DEFAULT_MIN_DELAY = 2 days;


    // ========================
    // CONSTRUCTOR
    // ========================

    constructor(
        address _governance,
        address _proposalEngine,
        uint256 _minDelay
    ) SecurityBase(_governance) {
        if (_proposalEngine == address(0)) revert Errors.ZeroAddress();
        if (_minDelay < DEFAULT_MIN_DELAY) revert Errors.InvalidUnlockTime(_minDelay, DEFAULT_MIN_DELAY);
        if (_minDelay > MAX_DELAY) revert Errors.InvalidUnlockTime(_minDelay, MAX_DELAY);

        proposalEngine = _proposalEngine;
        minDelay = _minDelay;
    }


   

    //queue an approved proposal for execution
    function queue(
        bytes32 proposalId,
        address target,
        address token,
        uint256 amount,
        bytes calldata callData
    ) external whenNotStopped returns (uint256 unlockTime) {

        //check proposal exists and is approved
        DataTypes.ProposalState state = IProposalEngine(proposalEngine).getProposalState(proposalId);
        if (state != DataTypes.ProposalState.Approved) {
            revert Errors.ProposalNotApproved(proposalId);
        }

        //check not already queued
        if (_queue[proposalId].proposalId != bytes32(0)) {
            revert Errors.ProposalAlreadyExists(proposalId);
        }

        //calculate unlock time
        unlockTime = block.timestamp + minDelay;

        //store in queue
        _queue[proposalId] = DataTypes.TimeLockEntry({
            proposalId: proposalId,
            unlockTime: unlockTime,
            executed: false,
            cancelled: false
        });

        //tell proposal engine to mark as queued
        IProposalEngine(proposalEngine).markQueued(proposalId, unlockTime);

        //emit events
        emit Events.TimelockStarted(proposalId, unlockTime);
        emit Events.ProposalQueued(proposalId, unlockTime);
    }


    //execute a queued proposal after unlock time
    function execute(bytes32 proposalId) external nonReentrant whenNotStopped {
        DataTypes.TimeLockEntry storage entry = _queue[proposalId];

        //check proposal is queued
        if (entry.proposalId == bytes32(0)) revert Errors.ProposalNotQueued(proposalId);

        //check not already executed
        if (entry.executed) revert Errors.TimelockAlreadyExecuted(proposalId);

        //check not cancelled
        if (entry.cancelled) revert Errors.TimelockCancelled(proposalId);

        //check unlock time has passed
        if (block.timestamp < entry.unlockTime) {
            revert Errors.ExecutionTooEarly(entry.unlockTime, block.timestamp);
        }

        //mark as executed BEFORE making any external call
        entry.executed = true;

        //tell proposal engine to mark as executed
        IProposalEngine(proposalEngine).markExecuted(proposalId);

        //emit events
        emit Events.TimelockExecuted(proposalId, block.timestamp);
        emit Events.ProposalExecuted(proposalId, msg.sender);
    }


    //cancel a queued proposal before execution
    function cancel(bytes32 proposalId) external whenNotStopped {
        DataTypes.TimeLockEntry storage entry = _queue[proposalId];

        //check proposal is queued
        if (entry.proposalId == bytes32(0)) revert Errors.ProposalNotQueued(proposalId);

        //check not already executed
        if (entry.executed) revert Errors.TimelockAlreadyExecuted(proposalId);

        //check not already cancelled
        if (entry.cancelled) revert Errors.TimelockCancelled(proposalId);

        //only governance can cancel from timelock
        if (msg.sender != governance) revert Errors.Unauthorized(msg.sender);

        //mark as cancelled
        entry.cancelled = true;

        //emit events
        emit Events.TimelockCancelled(proposalId, block.timestamp);
        emit Events.ProposalCancelled(proposalId, msg.sender);
    }


    //check if a proposal is queued
    function isQueued(bytes32 proposalId) external view returns (bool) {
        return _queue[proposalId].proposalId != bytes32(0) &&
               !_queue[proposalId].executed &&
               !_queue[proposalId].cancelled;
    }


    //check if a proposal has been executed
    function isExecuted(bytes32 proposalId) external view returns (bool) {
        return _queue[proposalId].executed;
    }


    //check if a proposal has been cancelled
    function isCancelled(bytes32 proposalId) external view returns (bool) {
        return _queue[proposalId].cancelled;
    }


    //get the full queued item data
    function getQueuedItem(bytes32 proposalId) external view returns (DataTypes.TimeLockEntry memory) {
        if (_queue[proposalId].proposalId == bytes32(0)) revert Errors.ProposalNotFound(proposalId);
        return _queue[proposalId];
    }


    //get the unlock time of a queued proposal
    function getUnlockTime(bytes32 proposalId) external view returns (uint256) {
        if (_queue[proposalId].proposalId == bytes32(0)) revert Errors.ProposalNotFound(proposalId);
        return _queue[proposalId].unlockTime;
    }


    //get the minimum delay time
    function getMinDelay() external view returns (uint256) {
        return minDelay;
    }


    //update the minimum delay - only governance
    function updateMinDelay(uint256 newDelay) external onlyGovernance {
        if (newDelay < DEFAULT_MIN_DELAY) revert Errors.InvalidUnlockTime(newDelay, DEFAULT_MIN_DELAY);
        if (newDelay > MAX_DELAY) revert Errors.InvalidUnlockTime(newDelay, MAX_DELAY);
        minDelay = newDelay;
    }


    //check if a proposal is ready to execute
    function isReady(bytes32 proposalId) external view returns (bool) {
        DataTypes.TimeLockEntry storage entry = _queue[proposalId];
        return entry.proposalId != bytes32(0) &&
               !entry.executed &&
               !entry.cancelled &&
               block.timestamp >= entry.unlockTime;
    }

}