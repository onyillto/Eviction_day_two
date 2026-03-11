// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {DataTypes} from "../helpers/DataTypes.sol";
import {Errors} from "../helpers/Errors.sol";
import {Events} from "../helpers/Events.sol";

interface ISignatureVerifier {

    //submit a signature for a proposal
    function submitSignature(
        bytes32 proposalId,
        bytes calldata signature
    ) external;

    //verify a single signature is valid
    function verifySignature(
        bytes32 proposalId,
        address signer,
        bytes calldata signature
    ) external view returns (bool);

    //check how many valid signatures a proposal has
    function getSignatureCount(bytes32 proposalId) external view returns (uint256);

    //check if a specific signer has signed a proposal
    function hasSigned(bytes32 proposalId, address signer) external view returns (bool);

    //check if a signer is authorized
    function isAuthorizedSigner(address signer) external view returns (bool);

    //add a new authorized signer - only governance
    function addSigner(address signer) external;

    //remove an authorized signer - only governance
    function removeSigner(address signer) external;

    //get the required signature threshold
    function getThreshold() external view returns (uint256);

    //update the threshold - only governance
    function updateThreshold(uint256 newThreshold) external;

    //get the current nonce of a signer
    function getSignerNonce(address signer) external view returns (uint256);

    //get the domain separator used for EIP-712
    function getDomainSeparator() external view returns (bytes32);

}