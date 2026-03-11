// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../helpers/DataTypes.sol";
import "../helpers/Errors.sol";
import "../helpers/Events.sol";
import "../interfaces/IProposalEngine.sol";
import "../main/SecurityBase.sol";

contract ProposalEngine is SecurityBase, IProposalEngine {

    //store all proposals
    mapping(bytes32 => DataTypes.Proposal) private _proposals;

    //track nonce per proposer
    mapping(address => uint256) private _nonces;

    //signature verifier address
    address public signatureVerifier;

    //timelock queue address
    address public timelockQueue;

    //how long before a proposal expires
    uint256 public constant PROPOSAL_EXPIRY = 7 days;


    // ========================
    // CONSTRUCTOR
    // ========================

    constructor(
        address _governance,
        address _signatureVerifier,
        address _timelockQueue
    ) SecurityBase(_governance) {
        if (_signatureVerifier == address(0)) revert Errors.ZeroAddress();
        if (_timelockQueue == address(0)) revert Errors.ZeroAddress();
        signatureVerifier = _signatureVerifier;
        timelockQueue = _timelockQueue;
    }


    // ========================
    // PROPOSAL FUNCTIONS
    // ========================

    //create a new proposal
    function propose(
        DataTypes.ProposalType proposalType,
        address target,
        address token,
        uint256 amount,
        bytes calldata callData
    ) external whenNotStopped returns (bytes32 proposalId) {

        //validate inputs
        if (target == address(0)) revert Errors.ZeroAddress();
        if (amount == 0) revert Errors.InvalidAmount(amount);

        //get current nonce for proposer
        uint256 currentNonce = _nonces[msg.sender];

        //generate unique proposal id
        proposalId = keccak256(
            abi.encodePacked(
                msg.sender,
                target,
                amount,
                currentNonce,
                block.chainid,
                block.timestamp
            )
        );

        //make sure proposal does not already exist
        if (_proposals[proposalId].createdAt != 0) {
            revert Errors.ProposalAlreadyExists(proposalId);
        }

        //create the proposal
        _proposals[proposalId] = DataTypes.Proposal({
            id: uint256(proposalId),
            proposalType: proposalType,
            proposalState: DataTypes.ProposalState.Pending,
            proposer: msg.sender,
            target: target,
            token: token,
            amount: amount,
            callData: callData,
            createdAt: block.timestamp,
            nonce: currentNonce,
            // This field was missing, causing the argument count mismatch.
            unlockTime: 0
        });

        //increment nonce
        _nonces[msg.sender]++;

        //emit event
        emit Events.ProposalCreated(proposalId, msg.sender, block.timestamp);
    }


    //cancel an existing proposal
    function cancel(bytes32 proposalId) external whenNotStopped {
        DataTypes.Proposal storage proposal = _proposals[proposalId];

        //check proposal exists
        if (proposal.createdAt == 0) revert Errors.ProposalNotFound(proposalId);

        //only proposer or governance can cancel
        if (msg.sender != proposal.proposer && msg.sender != governance) {
            revert Errors.Unauthorized(msg.sender);
        }

        //cannot cancel already executed proposals
        if (proposal.proposalState == DataTypes.ProposalState.Executed) {
            revert Errors.ProposalAlreadyExecuted(proposalId);
        }

        //cannot cancel already cancelled proposals
        if (proposal.proposalState == DataTypes.ProposalState.Cancelled) {
            revert Errors.ProposalAlreadyCancelled(proposalId);
        }

        //update state
        proposal.proposalState = DataTypes.ProposalState.Cancelled;

        //emit event
        emit Events.ProposalCancelled(proposalId, msg.sender);
    }


    //get the current state of a proposal
    function getProposalState(bytes32 proposalId) external view returns (DataTypes.ProposalState) {
        if (_proposals[proposalId].createdAt == 0) revert Errors.ProposalNotFound(proposalId);

        DataTypes.Proposal storage proposal = _proposals[proposalId];

        //check if proposal has expired
        if (
            proposal.proposalState == DataTypes.ProposalState.Pending &&
            block.timestamp > proposal.createdAt + PROPOSAL_EXPIRY
        ) {
            return DataTypes.ProposalState.Expired;
        }

        return proposal.proposalState;
    }


    //get the full proposal data
    function getProposal(bytes32 proposalId) external view returns (DataTypes.Proposal memory) {
        if (_proposals[proposalId].createdAt == 0) revert Errors.ProposalNotFound(proposalId);
        return _proposals[proposalId];
    }


    //check if a proposal exists
    function proposalExists(bytes32 proposalId) external view returns (bool) {
        return _proposals[proposalId].createdAt != 0;
    }


    //mark proposal as approved - only callable by signature verifier
    function markApproved(bytes32 proposalId) external onlyAddress(signatureVerifier) {
        DataTypes.Proposal storage proposal = _proposals[proposalId];

        if (proposal.createdAt == 0) revert Errors.ProposalNotFound(proposalId);
        if (proposal.proposalState != DataTypes.ProposalState.Pending) {
            revert Errors.ProposalNotFound(proposalId);
        }

        proposal.proposalState = DataTypes.ProposalState.Approved;
        emit Events.ProposalApproved(proposalId, msg.sender);
    }


    //mark proposal as queued - only callable by timelock
    function markQueued(bytes32 proposalId, uint256 unlockTime) external onlyAddress(timelockQueue) {
        DataTypes.Proposal storage proposal = _proposals[proposalId];

        if (proposal.createdAt == 0) revert Errors.ProposalNotFound(proposalId);
        if (proposal.proposalState != DataTypes.ProposalState.Approved) {
            revert Errors.ProposalNotApproved(proposalId);
        }

        proposal.proposalState = DataTypes.ProposalState.Queued;
        proposal.unlockTime = unlockTime;
        emit Events.ProposalQueued(proposalId, unlockTime);
    }


    //mark proposal as executed - only callable by timelock
    function markExecuted(bytes32 proposalId) external onlyAddress(timelockQueue) {
        DataTypes.Proposal storage proposal = _proposals[proposalId];

        if (proposal.createdAt == 0) revert Errors.ProposalNotFound(proposalId);
        if (proposal.proposalState != DataTypes.ProposalState.Queued) {
            revert Errors.ProposalNotQueued(proposalId);
        }

        proposal.proposalState = DataTypes.ProposalState.Executed;
        emit Events.ProposalExecuted(proposalId, msg.sender);
    }


    //get the nonce of a proposer
    function getNonce(address proposer) external view returns (uint256) {
        return _nonces[proposer];
    }

}