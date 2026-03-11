// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {ARESVault} from "../src/parts/ARESVault.sol";
import {ProposalEngine} from "../src/parts/ProposalEngine.sol";
import {SignatureVerifier} from "../src/parts/SignatureVerifier.sol";
import {TimelockQueue} from "../src/parts/TimelockQueue.sol";
import {MerkleDistributor} from "../src/parts/MerkleDistributor.sol";
import {DataTypes} from "../src/helpers/DataTypes.sol";
import {Errors} from "../src/helpers/Errors.sol";

//mock ERC20 token for testing
contract MockToken {
    mapping(address => uint256) public balanceOf;
    
    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "insufficient");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}


//malicious contract for reentrancy attack test
contract MaliciousReentrant {
    ARESVault public vault;
    bytes32 public targetProposal;
    uint256 public attackCount;

    constructor(address _vault) {
        vault = ARESVault(_vault);
    }

    function setTarget(bytes32 proposalId) external {
        targetProposal = proposalId;
    }

    //this gets called during token transfer
    //tries to reenter the vault
    fallback() external payable {
        attackCount++;
        if (attackCount < 3) {
            vault.executeProposal(targetProposal);
        }
    }

    receive() external payable {}
}


contract ARESTest is Test {

    //contracts
    ARESVault public vault;
    ProposalEngine public proposalEngine;
    SignatureVerifier public sigVerifier;
    TimelockQueue public timelockQueue;
    MerkleDistributor public merkleDistributor;
    MockToken public token;

    //actors
    address public governance;
    address public proposer;
    address public attacker;
    address public contributor1;
    address public contributor2;

    //signer keys
    uint256 public signer1Key;
    uint256 public signer2Key;
    uint256 public signer3Key;
    address public signer1;
    address public signer2;
    address public signer3;

    //merkle test data
    bytes32 public merkleRoot;
    bytes32[] public contributor1Proof;
    bytes32[] public contributor2Proof;
    uint256 public constant CONTRIBUTOR1_AMOUNT = 100 ether;
    uint256 public constant CONTRIBUTOR2_AMOUNT = 200 ether;


    // ========================
    // SETUP
    // ========================

    function setUp() public {
        //setup actors
        governance = makeAddr("governance");
        proposer = makeAddr("proposer");
        attacker = makeAddr("attacker");
        contributor1 = makeAddr("contributor1");
        contributor2 = makeAddr("contributor2");

        //setup signers with private keys
        signer1Key = 0x1;
        signer2Key = 0x2;
        signer3Key = 0x3;
        signer1 = vm.addr(signer1Key);
        signer2 = vm.addr(signer2Key);
        signer3 = vm.addr(signer3Key);

        //deploy mock token
        token = new MockToken();

        //deploy modules
        vm.startPrank(governance);

        //deploy proposal engine with placeholder addresses first
        proposalEngine = new ProposalEngine(
            governance,
            address(1), //placeholder
            address(1)  //placeholder
        );

        //setup initial signers array
        address[] memory initialSigners = new address[](3);
        initialSigners[0] = signer1;
        initialSigners[1] = signer2;
        initialSigners[2] = signer3;

        //deploy signature verifier
        sigVerifier = new SignatureVerifier(
            governance,
            address(proposalEngine),
            2, //threshold of 2 signatures required
            initialSigners
        );

        //deploy timelock with 2 day minimum delay
        timelockQueue = new TimelockQueue(
            governance,
            address(proposalEngine),
            2 days
        );

        //deploy merkle distributor
        merkleDistributor = new MerkleDistributor(
            governance,
            address(token)
        );

        //deploy vault
        vault = new ARESVault(
            governance,
            address(proposalEngine),
            address(sigVerifier),
            address(timelockQueue),
            address(merkleDistributor)
        );

        //set dependencies in proposal engine
        proposalEngine.setDependencies(
            address(sigVerifier),
            address(timelockQueue)
        );

        //register proposer as voter
        vault.registerVoter(proposer);

        vm.stopPrank();

        //mint tokens to vault
        token.mint(address(vault), 1000 ether);
        token.mint(address(merkleDistributor), 1000 ether);

        //setup merkle tree for testing
        _setupMerkleTree();
    }


    //setup a simple merkle tree with two contributors
    function _setupMerkleTree() internal {
        //leaf for contributor1: index=0, address, amount
        bytes32 leaf1 = keccak256(abi.encodePacked(uint256(0), contributor1, CONTRIBUTOR1_AMOUNT));
        //leaf for contributor2: index=1, address, amount
        bytes32 leaf2 = keccak256(abi.encodePacked(uint256(1), contributor2, CONTRIBUTOR2_AMOUNT));

        //build simple two leaf tree
        //sort leaves
        bytes32 left = leaf1 <= leaf2 ? leaf1 : leaf2;
        bytes32 right = leaf1 <= leaf2 ? leaf2 : leaf1;
        merkleRoot = keccak256(abi.encodePacked(left, right));

        //proofs
        contributor1Proof = new bytes32[](1);
        contributor1Proof[0] = leaf2;

        contributor2Proof = new bytes32[](1);
        contributor2Proof[0] = leaf1;

        //set root in distributor
        vm.prank(governance);
        merkleDistributor.updateRoot(1, merkleRoot);
    }


    //helper to create a valid signature for a proposal
    function _signProposal(
        bytes32 proposalId,
        uint256 signerKey,
        address signerAddr,
        uint256 nonce
    ) internal view returns (bytes memory) {
        bytes32 domainSeparator = sigVerifier.getDomainSeparator();

        bytes32 structHash = keccak256(
            abi.encode(
                keccak256("Approval(bytes32 proposalId,address signer,uint256 nonce,uint256 chainId)"),
                proposalId,
                signerAddr,
                nonce,
                block.chainid
            )
        );

        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", domainSeparator, structHash)
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerKey, digest);
        return abi.encodePacked(r, s, v);
    }


    //helper to create and approve a proposal
    function _createAndApproveProposal() internal returns (bytes32 proposalId) {
        //create proposal
        vm.prank(proposer);
        proposalId = vault.propose(
            DataTypes.ProposalType.Transfer,
            makeAddr("recipient"),
            address(token),
            10 ether,
            ""
        );

        //sign with signer1
        bytes memory sig1 = _signProposal(
            proposalId,
            signer1Key,
            signer1,
            sigVerifier.getSignerNonce(signer1)
        );
        vm.prank(signer1);
        sigVerifier.submitSignature(proposalId, sig1);

        //sign with signer2 - this reaches threshold
        bytes memory sig2 = _signProposal(
            proposalId,
            signer2Key,
            signer2,
            sigVerifier.getSignerNonce(signer2)
        );
        vm.prank(signer2);
        sigVerifier.submitSignature(proposalId, sig2);
    }


    // ========================
    // FUNCTIONAL TESTS
    // ========================

    //test 1 - proposal can be created successfully
    function test_ProposalCreation() public {
        vm.prank(proposer);
        bytes32 proposalId = vault.propose(
            DataTypes.ProposalType.Transfer,
            makeAddr("recipient"),
            address(token),
            10 ether,
            ""
        );

        //check proposal exists
        assertTrue(proposalEngine.proposalExists(proposalId));

        //check state is pending
        assertEq(
            uint256(proposalEngine.getProposalState(proposalId)),
            uint256(DataTypes.ProposalState.Pending)
        );
    }


    //test 2 - proposal lifecycle from pending to executed
    function test_FullProposalLifecycle() public {
        //create and approve proposal
        bytes32 proposalId = _createAndApproveProposal();

        //check state is approved
        assertEq(
            uint256(proposalEngine.getProposalState(proposalId)),
            uint256(DataTypes.ProposalState.Approved)
        );

        //queue proposal
        vault.queueProposal(proposalId);

        //check state is queued
        assertEq(
            uint256(proposalEngine.getProposalState(proposalId)),
            uint256(DataTypes.ProposalState.Queued)
        );

        //fast forward past unlock time
        vm.warp(block.timestamp + 3 days);

        //execute proposal
        vault.executeProposal(proposalId);

        //check state is executed
        assertEq(
            uint256(proposalEngine.getProposalState(proposalId)),
            uint256(DataTypes.ProposalState.Executed)
        );
    }


    //test 3 - signature verification works correctly
    function test_SignatureVerification() public {
        vm.prank(proposer);
        bytes32 proposalId = vault.propose(
            DataTypes.ProposalType.Transfer,
            makeAddr("recipient"),
            address(token),
            10 ether,
            ""
        );

        //verify signature is valid before submitting
        bytes memory sig = _signProposal(
            proposalId,
            signer1Key,
            signer1,
            sigVerifier.getSignerNonce(signer1)
        );

        assertTrue(sigVerifier.verifySignature(proposalId, signer1, sig));
    }


    //test 4 - signature count increases correctly
    function test_SignatureCountIncreases() public {
        vm.prank(proposer);
        bytes32 proposalId = vault.propose(
            DataTypes.ProposalType.Transfer,
            makeAddr("recipient"),
            address(token),
            10 ether,
            ""
        );

        assertEq(sigVerifier.getSignatureCount(proposalId), 0);

        bytes memory sig1 = _signProposal(proposalId, signer1Key, signer1, 0);
        vm.prank(signer1);
        sigVerifier.submitSignature(proposalId, sig1);

        assertEq(sigVerifier.getSignatureCount(proposalId), 1);
    }


    //test 5 - timelock prevents early execution
    function test_TimelockPreventsEarlyExecution() public {
        bytes32 proposalId = _createAndApproveProposal();
        vault.queueProposal(proposalId);

        //try to execute immediately without waiting
        vm.expectRevert();
        vault.executeProposal(proposalId);
    }


    //test 6 - timelock allows execution after delay
    function test_TimelockAllowsExecutionAfterDelay() public {
        bytes32 proposalId = _createAndApproveProposal();
        vault.queueProposal(proposalId);

        //fast forward past delay
        vm.warp(block.timestamp + 3 days);

        //should not revert
        vault.executeProposal(proposalId);
    }


    //test 7 - merkle claim works correctly
    function test_MerkleClaim() public {
        uint256 balanceBefore = token.balanceOf(contributor1);

        vm.prank(contributor1);
        merkleDistributor.claim(1, 0, CONTRIBUTOR1_AMOUNT, contributor1Proof);

        uint256 balanceAfter = token.balanceOf(contributor1);
        assertEq(balanceAfter - balanceBefore, CONTRIBUTOR1_AMOUNT);
    }


    //test 8 - proposal cancellation works
    function test_ProposalCancellation() public {
        vm.prank(proposer);
        bytes32 proposalId = vault.propose(
            DataTypes.ProposalType.Transfer,
            makeAddr("recipient"),
            address(token),
            10 ether,
            ""
        );

        //cancel proposal
        vm.prank(proposer);
        vault.cancelProposal(proposalId);

        //check state is cancelled
        assertEq(
            uint256(proposalEngine.getProposalState(proposalId)),
            uint256(DataTypes.ProposalState.Cancelled)
        );
    }


    //test 9 - nonce increases after each proposal
    function test_NonceIncreasesAfterProposal() public {
        uint256 nonceBefore = proposalEngine.getNonce(address(vault));

        vm.prank(proposer);
        vault.propose(
            DataTypes.ProposalType.Transfer,
            makeAddr("recipient"),
            address(token),
            10 ether,
            ""
        );

        uint256 nonceAfter = proposalEngine.getNonce(address(vault));
        assertEq(nonceAfter, nonceBefore + 1);
    }


    // ========================
    // EXPLOIT TESTS
    // ========================

    //exploit test 1 - double claim attempt
    function test_Exploit_DoubleClaimFails() public {
        //first claim succeeds
        vm.prank(contributor1);
        merkleDistributor.claim(1, 0, CONTRIBUTOR1_AMOUNT, contributor1Proof);

        //second claim must fail
        vm.prank(contributor1);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.AlreadyClaimed.selector, contributor1, 1)
        );
        merkleDistributor.claim(1, 0, CONTRIBUTOR1_AMOUNT, contributor1Proof);
    }


    //exploit test 2 - invalid signature rejected
    function test_Exploit_InvalidSignatureRejected() public {
        vm.prank(proposer);
        bytes32 proposalId = vault.propose(
            DataTypes.ProposalType.Transfer,
            makeAddr("recipient"),
            address(token),
            10 ether,
            ""
        );

        //create signature with wrong key
        uint256 wrongKey = 0x999;
        bytes memory fakeSig = _signProposal(proposalId, wrongKey, signer1, 0);

        //submit should fail
        vm.prank(signer1);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.InvalidSignature.selector, signer1, proposalId)
        );
        sigVerifier.submitSignature(proposalId, fakeSig);
    }


    //exploit test 3 - premature execution rejected
    function test_Exploit_PrematureExecutionRejected() public {
        bytes32 proposalId = _createAndApproveProposal();
        vault.queueProposal(proposalId);

        //try to execute 1 second after queueing
        vm.warp(block.timestamp + 1);

        vm.expectRevert();
        vault.executeProposal(proposalId);
    }


    //exploit test 4 - proposal replay rejected
    function test_Exploit_ProposalReplayRejected() public {
        bytes32 proposalId = _createAndApproveProposal();
        vault.queueProposal(proposalId);
        vm.warp(block.timestamp + 3 days);
        vault.executeProposal(proposalId);

        //try to execute again
        vm.expectRevert(
            abi.encodeWithSelector(Errors.ProposalAlreadyExecuted.selector, proposalId)
        );
        vault.executeProposal(proposalId);
    }


    //exploit test 5 - unauthorized proposer rejected
    function test_Exploit_UnauthorizedProposerRejected() public {
        //attacker is not registered as voter
        vm.prank(attacker);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.Unauthorized.selector, attacker)
        );
        vault.propose(
            DataTypes.ProposalType.Transfer,
            makeAddr("recipient"),
            address(token),
            10 ether,
            ""
        );
    }


    //exploit test 6 - signature replay rejected
    function test_Exploit_SignatureReplayRejected() public {
        vm.prank(proposer);
        bytes32 proposalId = vault.propose(
            DataTypes.ProposalType.Transfer,
            makeAddr("recipient"),
            address(token),
            10 ether,
            ""
        );

        //sign and submit once
        bytes memory sig = _signProposal(proposalId, signer1Key, signer1, 0);
        vm.prank(signer1);
        sigVerifier.submitSignature(proposalId, sig);

        //try to submit same signature again
        vm.prank(signer1);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.SignatureAlreadyUsed.selector, signer1, 1)
        );
        sigVerifier.submitSignature(proposalId, sig);
    }


    //exploit test 7 - large drain protection
    function test_Exploit_LargeDrainRejected() public {
        //try to propose draining more than 10% of treasury
        //vault has 1000 ether, 10% is 100 ether, try 200 ether
        vm.prank(proposer);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.InvalidAmount.selector, 200 ether)
        );
        vault.propose(
            DataTypes.ProposalType.Transfer,
            makeAddr("recipient"),
            address(token),
            200 ether,
            ""
        );
    }


    //exploit test 8 - invalid merkle proof rejected
    function test_Exploit_InvalidMerkleProofRejected() public {
        //create fake proof
        bytes32[] memory fakeProof = new bytes32[](1);
        fakeProof[0] = bytes32(uint256(0x123456));

        vm.prank(contributor1);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.InvalidMerkleProof.selector, contributor1, 1)
        );
        merkleDistributor.claim(1, 0, CONTRIBUTOR1_AMOUNT, fakeProof);
    }


    //exploit test 9 - emergency stop blocks all operations
    function test_Exploit_EmergencyStopBlocksOperations() public {
        //trigger emergency stop
        vm.prank(governance);
        vault.emergencyStop();

        //try to propose
        vm.prank(proposer);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.Unauthorized.selector, proposer)
        );
        vault.propose(
            DataTypes.ProposalType.Transfer,
            makeAddr("recipient"),
            address(token),
            10 ether,
            ""
        );
    }


    //exploit test 10 - unauthorized signer rejected
    function test_Exploit_UnauthorizedSignerRejected() public {
        vm.prank(proposer);
        bytes32 proposalId = vault.propose(
            DataTypes.ProposalType.Transfer,
            makeAddr("recipient"),
            address(token),
            10 ether,
            ""
        );

        //attacker tries to sign
        bytes memory attackerSig = _signProposal(proposalId, 0x999, attacker, 0);
        vm.prank(attacker);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.InvalidSigner.selector, attacker)
        );
        sigVerifier.submitSignature(proposalId, attackerSig);
    }


    //exploit test 11 - cross chain signature rejected
    function test_Exploit_CrossChainSignatureRejected() public {
        vm.prank(proposer);
        bytes32 proposalId = vault.propose(
            DataTypes.ProposalType.Transfer,
            makeAddr("recipient"),
            address(token),
            10 ether,
            ""
        );

        //sign on different chain id
        vm.chainId(999);
        bytes memory wrongChainSig = _signProposal(proposalId, signer1Key, signer1, 0);

        //switch back to original chain
        vm.chainId(31337);

        //signature should be invalid because chain id is different
        vm.prank(signer1);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.InvalidSignature.selector, signer1, proposalId)
        );
        sigVerifier.submitSignature(proposalId, wrongChainSig);
    }

}