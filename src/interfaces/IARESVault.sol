// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {DataTypes} from "../helpers/DataTypes.sol";
import {Errors} from "../helpers/Errors.sol";
import {Events} from "../helpers/Events.sol";

interface IARESVault {

    //propose a new treasury action
    function propose(
        DataTypes.ProposalType proposalType,
        address target,
        address token,
        uint256 amount,
        bytes calldata callData
    ) external returns (bytes32 proposalId);

    //submit a signature to approve a proposal
    function submitSignature(
        bytes32 proposalId,
        bytes calldata signature
    ) external;

    //queue an approved proposal into the timelock
    function queueProposal(bytes32 proposalId) external;

    //execute a queued proposal after unlock time
    function executeProposal(bytes32 proposalId) external;

    //cancel a proposal at any stage
    function cancelProposal(bytes32 proposalId) external;

    //claim merkle rewards
    function claimReward(
        uint256 epoch,
        uint256 index,
        uint256 amount,
        bytes32[] calldata proof
    ) external;

    //update merkle root for new epoch - only governance
    function updateRewardRoot(
        uint256 epoch,
        bytes32 newRoot
    ) external;

    //emergency stop - freezes all operations
    function emergencyStop() external;

    //resume after emergency stop - only governance
    function resume() external;

    //check if vault is currently stopped
    function isStopped() external view returns (bool);

    //get the proposal engine address
    function getProposalEngine() external view returns (address);

    //get the signature verifier address
    function getSignatureVerifier() external view returns (address);

    //get the timelock queue address
    function getTimelockQueue() external view returns (address);

    //get the merkle distributor address
    function getMerkleDistributor() external view returns (address);

    //get vault balance of a specific token
    function getBalance(address token) external view returns (uint256);

    //update governance address - only current governance
    function updateGovernance(address newGovernance) external;

    //get current governance address
    function getGovernance() external view returns (address);

}