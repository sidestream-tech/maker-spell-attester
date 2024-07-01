# MakerDAO spell attester

A proposal for attesting MakerDAO spells (governance payload) on-chain which aims to improve transparency and structure of the process and reduce dependence on centralised services for security-critical operations.

## Description

The end user of the proposed protocol have access to 3 [EAS](https://attest.org/) attestation schemas connected together and restricted by 3 specifically developed [EAS resolvers](https://docs.attest.org/docs/tutorials/resolver-contracts):
- Identity schema: attests known spell actors (crafters and reviewers) using address, pseudonym and their team name
    - Ensures uniqueness of pseudonym and address (unless revoked)
    - Ensures only lowercase latin letters or underscore symbols are used for pseudonym and team name
- Spell schema: attests specific spell setup (using name of the spell, pseudonyms of 1 crafter and 2 reviewers)
    - Ensures uniqueness of the spell name
    - Ensures all spell members have non-revoked Identities
    - Ensures all spell members have different Identities
    - Ensures reviewers have different team names
- Deployment: attests deployed spell contract (using name of the spell, address and hash of the spell)
    - Ensures spell name have relevant non-revoked Spell attestation
    - Ensures provided address is not empty
    - Ensures user attesting Deployment is the Spell member
    - Ensures a single attestation per user per spell
    - Ensures crafter attests spell before reviewers
    - Ensures reviewers attest the same payload address as crafter
    - Ensures reviewers attest the same payload hash as crafter
    - ~~Ensures provided hash matches codehash of the address~~ (temporary disabled to enable cross-chain attestations)

The process of using provided attestations is therefore as follows:
1. Once: admin attests Identity of all known participants
    - If some participants leave in the future, their identities could be revoked
2. At the start of each spell: admin attests a Spell
    - If plans change later on, the particular spell could be revoked
3. At the end of the spell review: each spell participant attests deployed spell address
    - The hash of the spell is also verified on-chain
    - Spell attestation could be revoked later
4. An external observer can follow the progress of the spell and check its overall status on-chain

The attestations can be created directly using generic EAS interface or via the provided command-line tool (see [spell-attester](https://www.npmjs.com/package/spell-attester) npm package for more details).

## Quick start

### Governance Facilitator

1. Request admin rights from another admin or a protocol deployer
2. Create known Identity attestations:
    - `A`: Use EAS UI by navigating to the Identity schema (see "Deployed addresses" section below)
    - `B`: Execute `npx spell-attester create-identity --user-address 0x... --user-pseudonym alice --team-name team_a` for each known identity
3. Create Spell attestation:
    - `A`: Use EAS UI by navigating to the Spell schema (see "Deployed addresses" section below)
    - `B`: Execute `npx spell-attester create-spell --payload-id 2024-06-27 --crafter alice --reviewer-a bob --reviewer-b charlie` to create spell team

### Spell member

1. Request Identity attestation from a Governance Facilitator
2. Ensure that you know `payload-id` of the current Spell (usually target date)
3. Create Deployment attestation:
    - `A`: Use EAS UI by navigating to the specific schema (see "Deployed addresses" section below)
    - `B`: Execute `npx spell-attester create-deployment --payload-id 2024-06-27 --payload-address 0x... --payload-hash 0x...` to attest deployed spell

### External observer

- Get current status of a particular spell
    - `A`: Call `SpellAttester.getSpellAddressByPayloadId(string)` using known `payload-id` (see "Deployed addresses" section below find actual `SpellAttester` address)
    - `B`: Execute `npx spell-attester status 2024-06-27` to get current status of the Spell

## Deployed addresses

Latest addresses are always available inside automatically generated jsons in the [broadcast/Deploy.s.sol folder](./broadcast/Deploy.s.sol/).

### Mainnet (chain id `1`)
Not yet deployed

### Sepolia testnet (chain id `11155111`)
- Identity schema [0x552aecaa79fa923e8fb10663bd0d7ad534c2d015b114a2569dd15ca5b2c99831](https://sepolia.easscan.org/attestation/attestWithSchema/0x552aecaa79fa923e8fb10663bd0d7ad534c2d015b114a2569dd15ca5b2c99831)
- Spell schema [0x46f05becf2b24c569a380ff56b8aa1f48ee05c8d19415eb52676010c171928c2](https://sepolia.easscan.org/attestation/attestWithSchema/0x46f05becf2b24c569a380ff56b8aa1f48ee05c8d19415eb52676010c171928c2)
- Deployment schema [0x316f7075206e477729d0dfe0a3827e42593b22b50910682ca1d288d5ed80801f](https://sepolia.easscan.org/attestation/attestWithSchema/0x316f7075206e477729d0dfe0a3827e42593b22b50910682ca1d288d5ed80801f)
- SpellAttester contract [0xCe08e30B8a59A95a59b0Cc25fFa50909a3526d7e](https://sepolia.etherscan.io/address/0xCe08e30B8a59A95a59b0Cc25fFa50909a3526d7e#code)

## Development

1. Create `.env` file in the root of the project with all required environment variables listed below
2. Test contracts via `forge test -vvv --fork-url sepolia` or `forge test -vvv --fork-url mainnet`
3. Test [natspec](https://docs.soliditylang.org/en/latest/natspec-format.html) via `npx --yes @defi-wonderland/natspec-smells@1.1.3 --enforceInheritdoc=false --include='src/**/*.sol'`
4. Deploy project via `forge script script/Deploy.s.sol:Deploy --fork-url sepolia` (note: this will only simulate deployment, unless you add `--verify --broadcast` to actually broadcast the transactions and then verify contracts)

### Environment variables

- `SEPOLIA_RPC_URL` (required for testing on sepolia)
- `MAINNET_RPC_URL` (required for testing on mainnet)
- `ETHERSCAN_API_KEY` (required for contract deployment)
- `PRIVATE_KEY` (required for contract deployment)
