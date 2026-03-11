# ARES Protocol

A treasury system i built from scratch for managing and sending protocol funds safely.
Everything goes through proposals, signatures, a time delay, then execution.
No shortcuts.

---

## How the folders are set up
```
src/
├── helpers/
│   ├── DataTypes.sol          # all my data shapes
│   ├── Errors.sol             # all my error messages
│   └── Events.sol             # all my events
├── interfaces/
│   ├── IARESVault.sol         
│   ├── IProposalEngine.sol    
│   ├── ISignatureVerifier.sol 
│   ├── ITimelockQueue.sol     
│   └── IMerkleDistributor.sol 
├── parts/
│   ├── ProposalEngine.sol     # handles proposals
│   ├── SignatureVerifier.sol  # checks signatures
│   ├── TimelockQueue.sol      # manages the waiting period
│   └── MerkleDistributor.sol  # handles reward claims
└── main/
    ├── SecurityBase.sol       # security rules every contract follows
    └── ARESVault.sol          # the main contract everything talks to

test/
└── ARESTest.sol               

script/
└── Deploy.s.sol               
```

---

## What you need

- [Foundry](https://getfoundry.sh)
- Solidity ^0.8.20

---

## Setting it up
```bash
git clone https://github.com/onyillto/Eviction_day_two>
cd ares-protocol
forge install
```

---

## Running the tests
```bash
# run everything
forge test

# see more info
forge test -vvvv


---

## How it works

Every treasury action follows this flow and cannot skip steps:
```
Propose → Sign → Queue → Wait → Execute
```

| Module | What it does |
|---|---|
| ProposalEngine | creates and tracks proposals |
| SignatureVerifier | collects signatures and checks they are real |
| TimelockQueue | makes everything wait before running |
| MerkleDistributor | lets contributors claim their rewards |
| ARESVault | the boss, holds the money, talks to all modules |

---

## Security stuff i built in

- Signatures use EIP-712 so they cant be reused or faked
- Reentrancy guards on everything that moves money
- Nothing executes without waiting through the timelock
- Flash loan attackers cant propose because of voter snapshots
- One proposal cant drain more than 10% of the treasury
- Emergency stop if anything goes wrong
- Claims use a bitmap so nobody claims twice
- Chain id is baked into signatures so they dont work on other chains

---

## What attacks this stops

| Attack | How i stopped it |
|---|---|
| Reentrancy | state updates before any external call |
| Signature replay | nonces per signer |
| Double claim | bitmap per epoch |
| Flash loan attack | voter registration required before proposing |
| Big treasury drain | capped at 10% per proposal |
| Early execution | unlock time must pass |
| Proposal replay | executed flag never gets deleted |
| Wrong chain signature | chain id locked in domain separator |
| Unauthorized execution | only specific contracts can change proposal state |
| Timelock griefing | delay is capped at 30 days max |

---

## License

MIT