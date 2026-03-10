// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

library Events {

    //Proposal Events
    event ProposalCreated(bytes32 indexed proposalId, address indexed proposer, uint256 createdAt);
    event ProposalApproved(bytes32 indexed proposalId, address indexed approver);
    event ProposalQueued(bytes32 indexed proposalId, uint256 unlockTime);
    event ProposalExecuted(bytes32 indexed proposalId, address indexed executor);
    event ProposalCancelled(bytes32 indexed proposalId, address indexed canceller);
    event ProposalExpired(bytes32 indexed proposalId);

    //Signature Events
    event SignatureSubmitted(bytes32 indexed proposalId, address indexed signer, uint256 nonce);
    event ThresholdReached(bytes32 indexed proposalId, uint256 totalSignatures);

    //Timelock Events
    event TimelockStarted(bytes32 indexed proposalId, uint256 unlockTime);
    event TimelockExecuted(bytes32 indexed proposalId, uint256 executedAt);
    event TimelockCancelled(bytes32 indexed proposalId, uint256 cancelledAt);

    //Merkle Events
    event MerkleRootUpdated(uint256 indexed epoch, bytes32 newRoot, address updatedBy);
    event RewardClaimed(uint256 indexed epoch, address indexed recipient, uint256 amount);

    //General Events
    event EmergencyStop(address triggeredBy, uint256 timestamp);
    event GovernanceUpdated(address oldGovernance, address newGovernance);

}