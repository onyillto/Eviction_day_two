//SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

library DataTypes{
     // Enum
     enum ProposalState{
        Pending,
        Approved,
        Queued,
        Executed,
        Cancelled,
        Expired
     }

     enum ProposalType{
        Transfer,
        Call,
        Upgrade
     }



     //STRUCT

     struct Proposal{
        uint256 id;
        ProposalType proposalType;
        ProposalState proposalState;
        address proposer;
        address target;
        address token;
        uint256 amount;
        bytes callData;
        uint256 createdAt;
        uint256 executeAfter;
        uint256 nonce;
     }

     struct SignatureData{
        address signer;
        bytes32 proposalId;
        uint256 nonce;
        uint256 chainId;
        bytes signature;
     }
     
     struct TimeLockEntry{
        bytes32 proposalId;
        uint256 executeAfter;
        bool executed;
        bool cancelled;
     }
    
    struct MerkleClaim{
        uint256 epoch;
        address recipient;
        uint256 amount;
        bytes32[] proof;
    }


}