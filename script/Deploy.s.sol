// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {ProposalEngine} from "../src/parts/ProposalEngine.sol";
import {SignatureVerifier} from "../src/parts/SignatureVerifier.sol";
import {TimelockQueue} from "../src/parts/TimelockQueue.sol";
import {MerkleDistributor} from "../src/parts/MerkleDistributor.sol";
import {ARESVault} from "../src/parts/ARESVault.sol";

contract Deploy is Script {

    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address governance = vm.envAddress("GOVERNANCE_ADDRESS");
        address token = vm.envAddress("TOKEN_ADDRESS");

        vm.startBroadcast(deployerKey);

        //deploy proposal engine with placeholder addresses
        ProposalEngine proposalEngine = new ProposalEngine(
            governance,
            address(1),
            address(1)
        );

        //setup signers
        address[] memory signers = new address[](3);
        signers[0] = vm.envAddress("SIGNER_1");
        signers[1] = vm.envAddress("SIGNER_2");
        signers[2] = vm.envAddress("SIGNER_3");

        //deploy signature verifier
        SignatureVerifier sigVerifier = new SignatureVerifier(
            governance,
            address(proposalEngine),
            2,
            signers
        );

        //deploy timelock
        TimelockQueue timelockQueue = new TimelockQueue(
            governance,
            address(proposalEngine),
            2 days
        );

        //deploy merkle distributor
        MerkleDistributor merkleDistributor = new MerkleDistributor(
            governance,
            token
        );

        //deploy vault
        ARESVault vault = new ARESVault(
            governance,
            address(proposalEngine),
            address(sigVerifier),
            address(timelockQueue),
            address(merkleDistributor)
        );

        vm.stopBroadcast();

        //log addresses
        console.log("ProposalEngine:", address(proposalEngine));
        console.log("SignatureVerifier:", address(sigVerifier));
        console.log("TimelockQueue:", address(timelockQueue));
        console.log("MerkleDistributor:", address(merkleDistributor));
        console.log("ARESVault:", address(vault));
    }
}
