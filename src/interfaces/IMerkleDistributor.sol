// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../helpers/DataTypes.sol";
import "../helpers/Errors.sol";
import "../helpers/Events.sol";

interface IMerkleDistributor {

    //claim rewards for a specific epoch
    function claim(
        uint256 epoch,
        uint256 index,
        uint256 amount,
        bytes32[] calldata proof
    ) external;

    //update the merkle root for a new epoch - only governance
    function updateRoot(
        uint256 epoch,
        bytes32 newRoot
    ) external;

    //check if a specific index has been claimed for an epoch
    function isClaimed(
        uint256 epoch,
        uint256 index
    ) external view returns (bool);

    //get the merkle root for a specific epoch
    function getRoot(uint256 epoch) external view returns (bytes32);

    //get the current epoch
    function getCurrentEpoch() external view returns (uint256);

    //get the token being distributed
    function getToken() external view returns (address);

    //verify a merkle proof without claiming
    function verifyProof(
        uint256 epoch,
        uint256 index,
        address recipient,
        uint256 amount,
        bytes32[] calldata proof
    ) external view returns (bool);

    //get total amount claimed for an epoch
    function getEpochTotalClaimed(uint256 epoch) external view returns (uint256);

    //get total amount allocated for an epoch
    function getEpochTotalAllocated(uint256 epoch) external view returns (uint256);

}                                                                                                       