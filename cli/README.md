# MakerDAO spell attester

The command-line tool to assist with [on-chain attestation of MakerDAO spells](https://github.com/sidestream-tech/maker-spell-attester). It aids with creating or revoking [EAS](https://attest.org/) attestations of 3 kinds: `identity` (userAddress, userPseudonym, userTeam), `spell` (payloadId, crafterPseudonym, reviewerAPseudonym, reviewerBPseudonym), `deployment` (payloadId, payloadAddress, payloadHash). It also helps to identify current status of the spell using `status` command.

> Note: the CLI is just another interface for creating, revoking and fetching attestations, but a regular UI such as [EASscan](https://easscan.org/) can be used to do the same set of actions (by using relevant attestation schemas).

### Pre-requirements
- Installed [node.js](https://nodejs.org/en/download/package-manager)
- RPC url of the supported chain (will be read from the `RPC_URL` environment variable)
- Private key of your EOA wallet (will be read from the `PRIVATE_KEY` environment variable)

### Usage
The CLI can be directly executed without installation via `npx spell-attester` or installed on your machine via `npm i spell-attester@latest -g` and then executed via `spell-attester`. It is advised to install specific version of the package and then review its code before using it.

```sh
$ npx spell-attester --help
 <command>

Commands:
  create-identity            Create attestation to identify ethereum address
  create-spell               Create attestation to setup a spell and define its members
  create-deployment          Create attestation to verify deployed spell
  revoke [attestation-uid]   Revoke existing attestation
  status [payload-id]        Get status of existing spell
  configure [variable-name]  Configure env variables

Options:
  --help     Show help                                                 [boolean]
  --version  Show version number                                       [boolean]
```

#### Example usage
```sh
# Create Identity attestation (at least 3 identities are required)
$ npx spell-attester create-identity --user-address 0x... --user-pseudonym alice --team-name team_a

# Create Spell attestation
$ npx spell-attester create-spell --payload-id 2024-06-27 --crafter alice --reviewer-a bob --reviewer-b charlie

# Create Deployment attestation
$ npx spell-attester create-deployment --payload-id 2024-06-27 --payload-address 0x... --payload-hash 0x...

# Get status of the spell
$ npx spell-attester status 2024-06-27
```
