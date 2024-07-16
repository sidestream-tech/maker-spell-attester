#!/usr/bin/env node
import process from 'node:process';
import 'dotenv/config';
import yargs from 'yargs';
import { hideBin } from 'yargs/helpers';
import { envPath, getProvider, getSigner } from './src/network.js';
import { getVariables, setVariable } from './src/configure.js';
import { createAttestation, getAtttestationEventsByAttester, getSpellEvents, getSpellStatus, revokeAttestation } from './src/attestations.js';
import { formatAttestationEvent, handleErrors, prettify } from './src/helpers.js';

yargs(hideBin(process.argv))
    .parserConfiguration({
        'parse-numbers': false,
    })
    .command(
        'create-identity',
        'Create attestation to identify ethereum address',
        (yargs) => {
            return yargs
                .option('user-address', {
                    describe: 'Ethereum address of a user',
                    group: 'Required options:',
                    type: 'string',
                    demandOption: true,
                    requiresArg: true,
                })
                .option('user-pseudonym', {
                    describe: 'Public username',
                    group: 'Required options:',
                    type: 'string',
                    demandOption: true,
                    requiresArg: true,
                })
                .option('team-name', {
                    describe: 'Name of a team the user belongs to',
                    group: 'Required options:',
                    type: 'string',
                    demandOption: true,
                    requiresArg: true,
                });
        },
        async argv => handleErrors(async ({ printSuccess }) => {
            const options = {
                userAddress: argv.userAddress,
                userPseudonym: argv.userPseudonym,
                teamName: argv.teamName,
            };
            console.info(`Attempting to create identity attestation for ${prettify(options)}...`);
            const { url } = await createAttestation(await getProvider(), 'identity', options);
            printSuccess(`Successfully created new identity attestation: ${url}`);
        }),
    )
    .command(
        'create-spell',
        'Create attestation to setup a spell and define its members',
        (yargs) => {
            return yargs
                .option('payload-id', {
                    describe: 'String uniquely identifying the spell',
                    group: 'Required options:',
                    type: 'string',
                    demandOption: true,
                    requiresArg: true,
                })
                .option('crafter', {
                    describe: 'Attested pseudonym taking crafter role',
                    group: 'Required options:',
                    type: 'string',
                    demandOption: true,
                    requiresArg: true,
                })
                .option('reviewer-a', {
                    describe: 'Attested pseudonym taking reviewer role',
                    group: 'Required options:',
                    type: 'string',
                    demandOption: true,
                    requiresArg: true,
                })
                .option('reviewer-b', {
                    describe: 'Attested pseudonym taking reviewer role',
                    group: 'Required options:',
                    type: 'string',
                    demandOption: true,
                    requiresArg: true,
                });
        },
        async argv => handleErrors(async ({ printSuccess }) => {
            const options = {
                payloadId: argv.payloadId,
                crafter: argv.crafter,
                reviewerA: argv.reviewerA,
                reviewerB: argv.reviewerB,
            };
            console.info(`Attempting to create Spell attestation for ${prettify(options)}...`);
            const { url } = await createAttestation(await getProvider(), 'spell', options);
            printSuccess(`Successfully created new Spell attestation: ${url}`);
        }),
    )
    .command(
        'create-deployment',
        'Create attestation to verify deployed spell',
        (yargs) => {
            return yargs
                .option('payload-id', {
                    describe: 'String uniquely identifying the spell',
                    group: 'Required options:',
                    type: 'string',
                    demandOption: true,
                    requiresArg: true,
                })
                .option('payload-address', {
                    describe: 'Address of the deployed spell',
                    group: 'Required options:',
                    type: 'string',
                    demandOption: true,
                    requiresArg: true,
                })
                .option('payload-hash', {
                    describe: 'Code hash of the flattened deployed spell',
                    group: 'Required options:',
                    type: 'string',
                    demandOption: true,
                    requiresArg: true,
                });
        },
        async argv => handleErrors(async ({ printSuccess }) => {
            const options = {
                payloadId: argv.payloadId,
                payloadAddress: argv.payloadAddress,
                payloadHash: argv.payloadHash,
            };
            console.info(`Attempting to create deployment attestation for ${prettify(options)}...`);
            const { url } = await createAttestation(await getProvider(), 'deployment', options);
            printSuccess(`Successfully created new deployment attestation: ${url}`);
        }),
    )
    .command(
        'revoke [attestation-uid]',
        'Revoke existing attestation',
        () => {},
        async argv => handleErrors(async ({ printSuccess }) => {
            const attestationUid = argv.attestationUid;
            if (!attestationUid) {
                console.info(`No [attestation-uid] provided, attempting to fetch all attestations that are possible to revoke...`);
                const signer = await getSigner();
                const allEvents = await getAtttestationEventsByAttester(await getProvider(), signer.address);
                if (!allEvents.length) {
                    console.info(`No previous attestations found from current address "${signer.address}"`);
                } else {
                    console.table(allEvents.map(formatAttestationEvent));
                }
                return;
            }
            console.info(`Attempting to revoke attestation ${attestationUid}...`);
            const { url } = await revokeAttestation(await getProvider(), attestationUid);
            printSuccess(`Successfully revoked attestation: ${url}`);
        }),
    )
    .command(
        'status [payload-id]',
        'Get status of existing spell',
        () => {},
        async argv => handleErrors(async ({ printSuccess, printError }) => {
            const payloadId = argv.payloadId;
            if (!payloadId) {
                console.info(`Attempting to fetch all previously attested Spells...`);
                const spellAttestations = await getSpellEvents(await getProvider());
                if (spellAttestations.length === 0) {
                    console.info(`No previous Spell attestation events found`);
                    return;
                }
                console.info(`Found the following Spell attestation events:`);
                console.table(spellAttestations.map(formatAttestationEvent));
                return;
            }
            console.info(`Attempting to fetch current status of ${payloadId}...`);
            const spellStatus = await getSpellStatus(await getProvider(), payloadId);
            if (!spellStatus.events.length) {
                console.info(`No previous attestation events found for "${payloadId}"`);
            } else {
                console.table(spellStatus.events.map(formatAttestationEvent));
            }
            if (spellStatus.reason) {
                printError(spellStatus.message);
            } else {
                printSuccess(spellStatus.message);
            }
        }),
    )
    .command(
        'configure [key] [value]',
        'Configure env variables',
        () => {},
        async argv => handleErrors(async ({ printSuccess }) => {
            if (!argv.key || !argv.value) {
                console.info('To configure a variable, please provide its [key] and [value], for example:');
                console.info('npx spell-attester configure RPC_URL http://...');
                console.info(`\nCurrently set variables (found in "${envPath}"):`);
                console.info(prettify(getVariables(envPath)));
                return;
            }
            setVariable(envPath, argv.key, argv.value);
            printSuccess(`Variable "${argv.key}" was successfully saved into "${envPath}"`);
        }),
    )
    .strictCommands()
    .demandCommand(1)
    .parse();
