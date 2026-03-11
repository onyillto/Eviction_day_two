// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Errors} from "../helpers/Errors.sol";
import {Events} from "../helpers/Events.sol";
import {IMerkleDistributor} from "../interfaces/IMerkleDistributor.sol";
import {SecurityBase} from "../main/SecurityBase.sol";

interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

contract MerkleDistributor is SecurityBase, IMerkleDistributor {

    //token being distributed
    address public token;

    //merkle root per epoch
    mapping(uint256 => bytes32) private _roots;

    //claimed bitmap per epoch
    //epoch => wordIndex => bitmap
    mapping(uint256 => mapping(uint256 => uint256)) private _claimedBitmap;

    //total claimed per epoch
    mapping(uint256 => uint256) private _epochTotalClaimed;

    //total allocated per epoch
    mapping(uint256 => uint256) private _epochTotalAllocated;

    //current epoch
    uint256 private _currentEpoch;


    // ========================
    // CONSTRUCTOR
    // ========================

    constructor(
        address _governance,
        address _token
    ) SecurityBase(_governance) {
        if (_token == address(0)) revert Errors.ZeroAddress();
        token = _token;
        _currentEpoch = 0;
    }


    // ========================
    // CLAIM FUNCTIONS
    // ========================

    //claim rewards for a specific epoch
    function claim(
        uint256 epoch,
        uint256 index,
        uint256 amount,
        bytes32[] calldata proof
    ) external nonReentrant whenNotStopped {

        //check epoch has a root
        if (_roots[epoch] == bytes32(0)) revert Errors.InvalidEpoch(epoch);

        //check amount is not zero
        if (amount == 0) revert Errors.ZeroAmount(msg.sender);

        //check not already claimed
        if (_isClaimed(epoch, index)) revert Errors.AlreadyClaimed(msg.sender, epoch);

        //verify the merkle proof
        bytes32 leaf;
        assembly {
            let m := mload(0x40)
            mstore(m, index)
            mstore(add(m, 0x20), shl(96, caller()))
            mstore(add(m, 0x34), amount)
            leaf := keccak256(m, 0x54)
        }
        if (!_verifyProof(proof, _roots[epoch], leaf)) {
            revert Errors.InvalidMerkleProof(msg.sender, epoch);
        }

        //mark as claimed BEFORE transfer
        _setClaimed(epoch, index);

        //update total claimed
        _epochTotalClaimed[epoch] += amount;

        //transfer tokens
        bool success = IERC20(token).transfer(msg.sender, amount);
        if (!success) revert Errors.CallFailed(token, "");

        //emit event
        emit Events.RewardClaimed(epoch, msg.sender, amount);
    }


    //update the merkle root for a new epoch
    function updateRoot(
        uint256 epoch,
        bytes32 newRoot
    ) external onlyGovernance {
        if (newRoot == bytes32(0)) revert Errors.InvalidMerkleProof(address(0), epoch);

        //store root
        _roots[epoch] = newRoot;

        //update current epoch if newer
        if (epoch > _currentEpoch) {
            _currentEpoch = epoch;
        }

        //emit event
        emit Events.MerkleRootUpdated(epoch, newRoot, msg.sender);
    }


    //set total allocated for an epoch
    function setEpochAllocation(
        uint256 epoch,
        uint256 totalAllocated
    ) external onlyGovernance {
        if (totalAllocated == 0) revert Errors.InvalidAmount(totalAllocated);
        _epochTotalAllocated[epoch] = totalAllocated;
    }


    // ========================
    // VIEW FUNCTIONS
    // ========================

    //check if a specific index has been claimed for an epoch
    function isClaimed(
        uint256 epoch,
        uint256 index
    ) external view returns (bool) {
        return _isClaimed(epoch, index);
    }


    //get the merkle root for a specific epoch
    function getRoot(uint256 epoch) external view returns (bytes32) {
        return _roots[epoch];
    }


    //get the current epoch
    function getCurrentEpoch() external view returns (uint256) {
        return _currentEpoch;
    }


    //get the token being distributed
    function getToken() external view returns (address) {
        return token;
    }


    //verify a merkle proof without claiming
    function verifyProof(
        uint256 epoch,
        uint256 index,
        address recipient,
        uint256 amount,
        bytes32[] calldata proof
    ) external view returns (bool) {
        if (_roots[epoch] == bytes32(0)) return false;
        bytes32 leaf;
        assembly {
            let m := mload(0x40)
            mstore(m, index)
            mstore(add(m, 0x20), shl(96, recipient))
            mstore(add(m, 0x34), amount)
            leaf := keccak256(m, 0x54)
        }
        return _verifyProof(proof, _roots[epoch], leaf);
    }


    //get total amount claimed for an epoch
    function getEpochTotalClaimed(uint256 epoch) external view returns (uint256) {
        return _epochTotalClaimed[epoch];
    }


    //get total amount allocated for an epoch
    function getEpochTotalAllocated(uint256 epoch) external view returns (uint256) {
        return _epochTotalAllocated[epoch];
    }


    // ========================
    // INTERNAL FUNCTIONS
    // ========================

    //check if an index has been claimed using bitmap
    function _isClaimed(
        uint256 epoch,
        uint256 index
    ) internal view returns (bool) {
        uint256 wordIndex = index / 256;
        uint256 bitIndex = index % 256;
        uint256 word = _claimedBitmap[epoch][wordIndex];
        uint256 mask = uint256(1) << bitIndex;
        return word & mask != 0;
    }


    //set an index as claimed using bitmap
    function _setClaimed(
        uint256 epoch,
        uint256 index
    ) internal {
        uint256 wordIndex = index / 256;
        uint256 bitIndex = index % 256;
        _claimedBitmap[epoch][wordIndex] |= uint256(1) << bitIndex;
    }


    //verify a merkle proof
    function _verifyProof(
        bytes32[] calldata proof,
        bytes32 root,
        bytes32 leaf
    ) internal pure returns (bool) {
        bytes32 computedHash = leaf;

        for (uint256 i = 0; i < proof.length; i++) {
            bytes32 proofElement = proof[i];

            if (computedHash <= proofElement) {
                computedHash = keccak256(abi.encodePacked(computedHash, proofElement));
            } else {
                computedHash = keccak256(abi.encodePacked(proofElement, computedHash));
            }
        }

        return computedHash == root;
    }

}