// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../helpers/DataTypes.sol";
import "../helpers/Errors.sol";
import "../helpers/Events.sol";

interface InterfaceMachineProposal {

    //create a new proposal
    function propose(
        DataTypes.ProposalType proposalType,
        address target,
        address token,
        uint256 amount,
        bytes calldata callData
    ) external returns (bytes32 proposalId);

    //cancel an existing proposal
    function cancel(bytes32 proposalId) external;

    //get the current state of a proposal
    function getProposalState(bytes32 proposalId) external view returns (DataTypes.ProposalState);

    //get the full proposal data
    function getProposal(bytes32 proposalId) external view returns (DataTypes.Proposal memory);

    //check if a proposal exists
    function proposalExists(bytes32 proposalId) external view returns (bool);

    //mark proposal as approved - only callable by signature verifier
    function markApproved(bytes32 proposalId) external;

    //mark proposal as queued - only callable by timelock
    function markQueued(bytes32 proposalId, uint256 unlockTime) external;

    //mark proposal as executed - only callable by timelock
    function markExecuted(bytes32 proposalId) external;

    //get the nonce of a proposer
    function getNonce(address proposer) external view returns (uint256);

}