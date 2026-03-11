WHAT IS ARES WHY I BUILT IT THIS WAY 
----------------------------------------------------------------
ARES is a treasury system I designed from scratch
I split it into modules because one big contract is not good
If one part gets attacked the others are not affected
Every action has to go through a specific path and cannot skip steps




The five modules and why each one exists
-----------------------------------------
ProposalEngine — this is where everything starts, someone asks to move money and this module tracks that request from start to finish
SignatureVerifier — before anything moves authorized people have to sign and this module checks those signatures are real and not reused
TimelockQueue — even after signatures pass nothing runs immediately, this module makes everything wait so governance has time to react
MerkleDistributor — paying thousands of contributors one by one would cost too much gas, this module lets everyone claim their own reward using a proof
ARESVault — this is the only contract that holds money, all the other modules just give it instructions, they never touch funds directly


The security base
------------------
Every module inherits from SecurityBase
This gives every module reentrancy protection, access control, and emergency stop for free
I did not copy this from OpenZeppelin, I wrote it myself using uint256 flags instead of booleans for gas efficiency



Trust assumptions
--------------------
Governance is trusted but limited, even governance cannot bypass the timelock
Signers are trusted but require a threshold, one signer cannot approve alone
The vault trusts modules but only for their specific job, SignatureVerifier can only call markApproved, nothing else
Nobody is trusted with unlimited power



Section 5 — Why this design prevents the failures mentioned in the exam
-------------------------------------------------------------------------
Governance takeovers — voter registration and signature threshold prevent this
Replay attacks — nonces and domain separator prevent this
Flash loan manipulation — snapshot system prevents this
Merkle root manipulation — only governance can update roots through a proposal
Timelock bypass — state updates before external calls prevent reentrancy bypass
Multisig griefing — threshold is adjustable and delay is capped


Closing paragraph
------------------
Every design decision was made with a specific attack in mind
The modularity is not just for clean code, it is a security boundary
No single compromised module can drain the treasury alone

