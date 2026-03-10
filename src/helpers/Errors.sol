// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

library Errors {

    //proposal Error
    error ProposalNotFound(bytes32 proposalId);
    error ProposalAlreadyExists(bytes32 proposalId);
    error ProposalNotApproved(bytes32 proposalId);
    error ProposalNotQueued(bytes32 proposalId);
    error ProposalAlreadyExecuted(bytes32 proposalId);
    error ProposalAlreadyCancelled(bytes32 proposalId);
    error ProposalExpired(bytes32 proposalId, uint256 expiredAt);
    error InvalidProposalType();
    error UnauthorizedProposer(address caller);

    //Timelock Error
    error TimelockNotExpired(bytes32 proposalId);
    error TimelockAlreadyExecuted(bytes32 proposalId);
    error TimelockCancelled(bytes32 proposalId);
    error ExecutionTooEarly(uint256 unlockTime, uint256 currentTime);
    error InvalidUnlockTime(uint256 provided, uint256 minimum);

    //Signature Error
    error InvalidSignature(address signer, bytes32 proposalId);
    error SignatureAlreadyUsed(address signer, uint256 nonce);
    error SignatureExpired(uint256 expiredAt, uint256 currentTime);
    error InvalidSigner(address signer);
    error ThresholdNotMet(uint256 required, uint256 received);
    error InvalidChainId(uint256 expected, uint256 provided);
    error InvalidNonce(address signer, uint256 expected, uint256 provided);

    //Merkle Error
    error InvalidMerkleProof(address recipient, uint256 epoch);
    error AlreadyClaimed(address recipient, uint256 epoch);
    error InvalidEpoch(uint256 epoch);
    error ZeroAmount(address recipient);
    error InvalidRecipient(address recipient);

    //General Error
    error ZeroAddress();
    error Unauthorized(address caller);
    error InvalidAmount(uint256 amount);
    error CallFailed(address target, bytes callData);
    error Reentrancy();

}