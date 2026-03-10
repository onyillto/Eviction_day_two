// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../helpers/DataTypes.sol";
import "../helpers/Errors.sol";
import "../helpers/Events.sol";
import "../interfaces/ISignatureVerifier.sol";
import "../interfaces/IProposalEngine.sol";
import "../main/SecurityBase.sol";

contract SignatureVerifier is SecurityBase, ISignatureVerifier {

    //authorized signers
    mapping(address => bool) private _signers;

    //track signatures per proposal per signer
    mapping(bytes32 => mapping(address => bool)) private _hasSigned;

    //track signature count per proposal
    mapping(bytes32 => uint256) private _signatureCount;

    //track used nonces per signer
    mapping(address => uint256) private _signerNonces;

    //number of signatures required
    uint256 private _threshold;

    //proposal engine address
    address public proposalEngine;

    //EIP-712 domain separator
    bytes32 private _domainSeparator;

    //EIP-712 type hash
    bytes32 private constant _APPROVAL_TYPEHASH = keccak256(
        "Approval(bytes32 proposalId,address signer,uint256 nonce,uint256 chainId)"
    );


    // ========================
    // CONSTRUCTOR
    // ========================

    constructor(
        address _governance,
        address _proposalEngine,
        uint256 threshold,
        address[] memory initialSigners
    ) SecurityBase(_governance) {

        if (_proposalEngine == address(0)) revert Errors.ZeroAddress();
        if (threshold == 0) revert Errors.InvalidAmount(threshold);
        if (initialSigners.length < threshold) revert Errors.ThresholdNotMet(threshold, initialSigners.length);

        proposalEngine = _proposalEngine;
        _threshold = threshold;

        //add initial signers
        for (uint256 i = 0; i < initialSigners.length; i++) {
            if (initialSigners[i] == address(0)) revert Errors.ZeroAddress();
            _signers[initialSigners[i]] = true;
        }

        //build EIP-712 domain separator
        _domainSeparator = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes("ARESProtocol")),
                keccak256(bytes("1")),
                block.chainid,
                address(this)
            )
        );
    }


    // ========================
    // SIGNATURE FUNCTIONS
    // ========================

    //submit a signature for a proposal
    function submitSignature(
        bytes32 proposalId,
        bytes calldata signature
    ) external whenNotStopped {

        //check signer is authorized
        if (!_signers[msg.sender]) revert Errors.InvalidSigner(msg.sender);

        //check proposal exists
        if (!IProposalEngine(proposalEngine).proposalExists(proposalId)) {
            revert Errors.ProposalNotFound(proposalId);
        }

        //check signer has not already signed
        if (_hasSigned[proposalId][msg.sender]) {
            revert Errors.SignatureAlreadyUsed(msg.sender, _signerNonces[msg.sender]);
        }

        //get current nonce
        uint256 currentNonce = _signerNonces[msg.sender];

        //verify the signature
        if (!_verifySignature(proposalId, msg.sender, currentNonce, signature)) {
            revert Errors.InvalidSignature(msg.sender, proposalId);
        }

        //mark as signed
        _hasSigned[proposalId][msg.sender] = true;

        //increment signature count
        _signatureCount[proposalId]++;

        //increment signer nonce
        _signerNonces[msg.sender]++;

        //emit event
        emit Events.SignatureSubmitted(proposalId, msg.sender, currentNonce);

        //check if threshold is met
        if (_signatureCount[proposalId] >= _threshold) {
            //tell proposal engine to mark as approved
            IProposalEngine(proposalEngine).markApproved(proposalId);
            emit Events.ThresholdReached(proposalId, _signatureCount[proposalId]);
        }
    }


    //verify a single signature is valid
    function verifySignature(
        bytes32 proposalId,
        address signer,
        bytes calldata signature
    ) external view returns (bool) {
        uint256 currentNonce = _signerNonces[signer];
        return _verifySignature(proposalId, signer, currentNonce, signature);
    }


    //check how many valid signatures a proposal has
    function getSignatureCount(bytes32 proposalId) external view returns (uint256) {
        return _signatureCount[proposalId];
    }


    //check if a specific signer has signed a proposal
    function hasSigned(bytes32 proposalId, address signer) external view returns (bool) {
        return _hasSigned[proposalId][signer];
    }


    //check if a signer is authorized
    function isAuthorizedSigner(address signer) external view returns (bool) {
        return _signers[signer];
    }


    //add a new authorized signer
    function addSigner(address signer) external onlyGovernance {
        if (signer == address(0)) revert Errors.ZeroAddress();
        if (_signers[signer]) revert Errors.ProposalAlreadyExists(bytes32(0));
        _signers[signer] = true;
    }


    //remove an authorized signer
    function removeSigner(address signer) external onlyGovernance {
        if (!_signers[signer]) revert Errors.InvalidSigner(signer);
        _signers[signer] = false;
    }


    //get the required signature threshold
    function getThreshold() external view returns (uint256) {
        return _threshold;
    }


    //update the threshold
    function updateThreshold(uint256 newThreshold) external onlyGovernance {
        if (newThreshold == 0) revert Errors.InvalidAmount(newThreshold);
        _threshold = newThreshold;
    }


    //get the current nonce of a signer
    function getSignerNonce(address signer) external view returns (uint256) {
        return _signerNonces[signer];
    }


    //get the domain separator
    function getDomainSeparator() external view returns (bytes32) {
        return _domainSeparator;
    }


    // ========================
    // INTERNAL FUNCTIONS
    // ========================

    //internal signature verification using EIP-712
    function _verifySignature(
        bytes32 proposalId,
        address signer,
        uint256 nonce,
        bytes calldata signature
    ) internal view returns (bool) {

        //build the struct hash
        bytes32 structHash = keccak256(
            abi.encode(
                _APPROVAL_TYPEHASH,
                proposalId,
                signer,
                nonce,
                block.chainid
            )
        );

        //build the final EIP-712 hash
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                _domainSeparator,
                structHash
            )
        );

        //recover the signer from the signature
        address recovered = _recoverSigner(digest, signature);

        //check recovered address matches expected signer
        return recovered == signer;
    }


    //recover signer address from signature
    function _recoverSigner(
        bytes32 digest,
        bytes calldata signature
    ) internal pure returns (address) {

        //signature must be 65 bytes
        if (signature.length != 65) return address(0);

        bytes32 r;
        bytes32 s;
        uint8 v;

        //extract r s v from signature
        assembly {
            r := calldataload(signature.offset)
            s := calldataload(add(signature.offset, 32))
            v := byte(0, calldataload(add(signature.offset, 64)))
        }

        //prevent signature malleability
        if (uint256(s) > 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0) {
            return address(0);
        }

        if (v != 27 && v != 28) return address(0);

        return ecrecover(digest, v, r, s);
    }

}