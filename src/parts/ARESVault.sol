// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {DataTypes} from "../helpers/DataTypes.sol";
import {Errors} from "../helpers/Errors.sol";
import {IARESVault} from "../interfaces/IARESVault.sol";
import {IProposalEngine} from "../interfaces/IProposalEngine.sol";
import {ISignatureVerifier} from "../interfaces/ISignatureVerifier.sol";
import {ITimelockQueue} from "../interfaces/ITimelockQueue.sol";
import {IMerkleDistributor} from "../interfaces/IMerkleDistributor.sol";
import {SecurityBase} from "../main/SecurityBase.sol";

interface IERC20Transfer {
    function transfer(address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

contract ARESVault is SecurityBase, IARESVault {

    //module addresses
    address public proposalEngine;
    address public signatureVerifier;
    address public timelockQueue;
    address public merkleDistributor;

    //flash loan protection
    //snapshot of voting power is taken at proposal block
    mapping(address => uint256) private _votingPowerSnapshot;

    //large drain protection threshold
    //no single proposal can drain more than this percentage
    uint256 public constant MAX_SINGLE_DRAIN_BPS = 1000; //10% in basis points

    //track total treasury value per token
    mapping(address => uint256) private _treasuryBalances;


    // ========================
    // CONSTRUCTOR
    // ========================

    constructor(
        address _governance,
        address _proposalEngine,
        address _signatureVerifier,
        address _timelockQueue,
        address _merkleDistributor
    ) SecurityBase(_governance) {
        if (_proposalEngine == address(0)) revert Errors.ZeroAddress();
        if (_signatureVerifier == address(0)) revert Errors.ZeroAddress();
        if (_timelockQueue == address(0)) revert Errors.ZeroAddress();
        if (_merkleDistributor == address(0)) revert Errors.ZeroAddress();

        proposalEngine = _proposalEngine;
        signatureVerifier = _signatureVerifier;
        timelockQueue = _timelockQueue;
        merkleDistributor = _merkleDistributor;
    }


    // ========================
    // PROPOSAL FUNCTIONS
    // ========================

    //propose a new treasury action
    function propose(
        DataTypes.ProposalType proposalType,
        address target,
        address token,
        uint256 amount,
        bytes calldata callData
    ) external whenNotStopped returns (bytes32 proposalId) {

        //flash loan protection
        //check caller has had voting power for at least one block
        if (_votingPowerSnapshot[msg.sender] == 0) {
            revert Errors.Unauthorized(msg.sender);
        }

        //large drain protection
        //check amount does not exceed max single drain threshold
        if (token != address(0) && amount > 0) {
            uint256 balance = IERC20Transfer(token).balanceOf(address(this));
            uint256 maxAllowed = (balance * MAX_SINGLE_DRAIN_BPS) / 10000;
            if (amount > maxAllowed) {
                revert Errors.InvalidAmount(amount);
            }
        }

        //delegate to proposal engine
        proposalId = IProposalEngine(proposalEngine).propose(
            proposalType,
            target,
            token,
            amount,
            callData
        );
    }


    //submit a signature to approve a proposal
    function submitSignature(
        bytes32 proposalId,
        bytes calldata signature
    ) external whenNotStopped {
        ISignatureVerifier(signatureVerifier).submitSignature(
            proposalId,
            signature
        );
    }


    //queue an approved proposal into the timelock
    function queueProposal(bytes32 proposalId) external whenNotStopped {

        //get proposal data from engine
        DataTypes.Proposal memory proposal = IProposalEngine(proposalEngine).getProposal(proposalId);

        //check proposal is approved
        if (proposal.proposalState != DataTypes.ProposalState.Approved) {
            revert Errors.ProposalNotApproved(proposalId);
        }

        //delegate to timelock queue
        ITimelockQueue(timelockQueue).queue(
            proposalId,
            proposal.target,
            proposal.token,
            proposal.amount,
            proposal.callData
        );
    }


    //execute a queued proposal after unlock time
    function executeProposal(bytes32 proposalId) external whenNotStopped {

        //get proposal data
        DataTypes.Proposal memory proposal = IProposalEngine(proposalEngine).getProposal(proposalId);

        //check proposal is queued
        if (proposal.proposalState != DataTypes.ProposalState.Queued) {
            revert Errors.ProposalNotQueued(proposalId);
        }

        //execute through timelock first
        //this marks proposal as executed in both timelock and engine
        ITimelockQueue(timelockQueue).execute(proposalId);

        //now perform the actual treasury action
        _executeAction(proposal);
    }


    //cancel a proposal at any stage
    function cancelProposal(bytes32 proposalId) external whenNotStopped {

        //get proposal state
        DataTypes.ProposalState state = IProposalEngine(proposalEngine).getProposalState(proposalId);

        //cannot cancel executed proposals
        if (state == DataTypes.ProposalState.Executed) {
            revert Errors.ProposalAlreadyExecuted(proposalId);
        }

        //cancel in proposal engine
        IProposalEngine(proposalEngine).cancel(proposalId);

        //if queued also cancel in timelock
        if (state == DataTypes.ProposalState.Queued) {
            ITimelockQueue(timelockQueue).cancel(proposalId);
        }
    }


    // ========================
    // REWARD FUNCTIONS
    // ========================

    //claim merkle rewards
    function claimReward(
        uint256 epoch,
        uint256 index,
        uint256 amount,
        bytes32[] calldata proof
    ) external whenNotStopped {
        IMerkleDistributor(merkleDistributor).claim(
            epoch,
            index,
            amount,
            proof
        );
    }


    //update merkle root for new epoch
    function updateRewardRoot(
        uint256 epoch,
        bytes32 newRoot
    ) external onlyGovernance {
        IMerkleDistributor(merkleDistributor).updateRoot(epoch, newRoot);
    }


    // ========================
    // GOVERNANCE VOTING POWER
    // ========================

    //register voting power - only governance
    //called when governance assigns voting rights to an address
    function registerVoter(address voter) external onlyGovernance {
        if (voter == address(0)) revert Errors.ZeroAddress();
        _votingPowerSnapshot[voter] = block.number;
    }


    //remove voting power - only governance
    function removeVoter(address voter) external onlyGovernance {
        _votingPowerSnapshot[voter] = 0;
    }


    // ========================
    // EMERGENCY FUNCTIONS
    // ========================

    function emergencyStop()
        public
        override(SecurityBase, IARESVault)
        onlyGovernance
    {
        super.emergencyStop();
    }

    function resume()
        public
        override(SecurityBase, IARESVault)
        onlyGovernance
    {
        super.resume();
    }

    //check if vault is currently stopped
    function isStopped() external view returns (bool) {
        return stopped;
    }


    // ========================
    // VIEW FUNCTIONS
    // ========================

    //get the proposal engine address
    function getProposalEngine() external view returns (address) {
        return proposalEngine;
    }


    //get the signature verifier address
    function getSignatureVerifier() external view returns (address) {
        return signatureVerifier;
    }


    //get the timelock queue address
    function getTimelockQueue() external view returns (address) {
        return timelockQueue;
    }


    //get the merkle distributor address
    function getMerkleDistributor() external view returns (address) {
        return merkleDistributor;
    }


    //get vault balance of a specific token
    function getBalance(address token) external view returns (uint256) {
        return IERC20Transfer(token).balanceOf(address(this));
    }

    function updateGovernance(address newGovernance)
        public
        override(SecurityBase, IARESVault)
        onlyGovernance
    {
        super.updateGovernance(newGovernance);
    }


    //get current governance address
    function getGovernance() external view returns (address) {
        return governance;
    }


    // ========================
    // INTERNAL FUNCTIONS
    // ========================

    //execute the actual treasury action
    function _executeAction(DataTypes.Proposal memory proposal) internal {

        if (proposal.proposalType == DataTypes.ProposalType.Transfer) {
            //transfer tokens to target
            bool success = IERC20Transfer(proposal.token).transfer(
                proposal.target,
                proposal.amount
            );
            if (!success) revert Errors.CallFailed(proposal.target, "");

        } else if (proposal.proposalType == DataTypes.ProposalType.Call) {
            //make external call with calldata
            (bool success, ) = proposal.target.call(proposal.callData);
            if (!success) revert Errors.CallFailed(proposal.target, proposal.callData);

        } else if (proposal.proposalType == DataTypes.ProposalType.Upgrade) {
            //upgrade a module address
            _handleUpgrade(proposal.target, proposal.callData);
        }
    }


    //handle module upgrades
    function _handleUpgrade(
        address /* target */,
        bytes memory callData
    ) internal {
        //decode which module to upgrade and new address
        (uint256 moduleId, address newAddress) = abi.decode(callData, (uint256, address));

        if (newAddress == address(0)) revert Errors.ZeroAddress();

        //0 = proposalEngine
        //1 = signatureVerifier
        //2 = timelockQueue
        //3 = merkleDistributor
        if (moduleId == 0) {
            proposalEngine = newAddress;
        } else if (moduleId == 1) {
            signatureVerifier = newAddress;
        } else if (moduleId == 2) {
            timelockQueue = newAddress;
        } else if (moduleId == 3) {
            merkleDistributor = newAddress;
        } else {
            revert Errors.InvalidProposalType();
        }
    }

}