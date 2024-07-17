import ethers from 'ethers';
import { NO_EXPIRATION, ZERO_ADDRESS } from '@ethereum-attestation-service/eas-sdk';
import { getEasAttesterContract, getEasRegistryContract, getSpellAttesterContract } from './contracts.js';
import { getConfig, getDateFromBlockNumber, getSigner } from './network.js';
import { decodeAttestationData, decodeErrorMessage, encodeAttestationData } from './helpers.js';

const generateAttestationUrl = async function (provider, attestationId) {
    const config = await getConfig(provider);
    return `${config.easScannerUrl}attestation/view/${attestationId}`;
};

const getAttestation = async function (provider, attestationId) {
    const easAttester = await getEasAttesterContract(provider);
    const attestation = await easAttester.getAttestation(attestationId);
    if (attestation.uid === ethers.constants.HashZero) {
        throw new Error('Attestation with uid not found');
    }
    return attestation;
};

export const getAttestationData = async function (provider, attestationId) {
    const attestation = await getAttestation(provider, attestationId);
    const easRegistry = await getEasRegistryContract(provider);
    const schemaRecord = await easRegistry.getSchema({ uid: attestation.schema });
    return {
        ...attestation,
        data: await decodeAttestationData(schemaRecord.schema, attestation),
    };
};

export const createAttestation = async function (provider, name, options, verbose) {
    // Get relevant data
    const spellAttester = await getSpellAttesterContract(provider);
    const schemaId = await spellAttester.schemaNameToSchemaId(ethers.utils.formatBytes32String(name));
    const easRegistry = await getEasRegistryContract(provider);
    const schemaRecord = await easRegistry.getSchema({ uid: schemaId });
    const easAttester = (await getEasAttesterContract(provider)).connect(getSigner(provider));

    // Encode options based on the types
    const attestationData = encodeAttestationData(schemaRecord.schema, options);

    // Make attestation
    try {
        const transaction = await easAttester.attest({
            schema: schemaId,
            data: {
                recipient: ZERO_ADDRESS,
                expirationTime: NO_EXPIRATION,
                revocable: true,
                data: attestationData,
            },
        });
        console.info(`Attestation transaction ("${transaction?.tx?.hash}") is submitted, waiting to be mined...`);
        const attestationId = await transaction.wait();
        return {
            id: attestationId,
            url: await generateAttestationUrl(provider, attestationId),
        };
    } catch (error) {
        if (verbose) {
            console.error(error);
        }
        throw new Error(`Attestation can not be created: ${decodeErrorMessage(error)}`);
    }
};

export const revokeAttestation = async function (provider, attestationId, verbose) {
    // Get relevant data
    const easAttester = (await getEasAttesterContract(provider)).connect(getSigner(provider));
    const attestation = await getAttestation(provider, attestationId);

    // Revoke attestation
    try {
        const transaction = await easAttester.revoke({
            schema: attestation.schema,
            data: {
                uid: attestationId,
                data: {
                    uid: attestationId,
                },
            },
        });
        console.info(`Revocation transaction ("${transaction?.tx?.hash}") is submitted, waiting to be mined...`);
        await transaction.wait();
        return {
            url: await generateAttestationUrl(provider, attestationId),
        };
    } catch (error) {
        if (verbose) {
            console.error(error);
        }
        throw new Error(`Attestation can not be revoked: ${decodeErrorMessage(error)}`);
    }
};

const getResolverEvents = async function (provider, schemaName, eventTypes, topics) {
    const spellAttester = await getSpellAttesterContract(provider);
    const resolverAddress = await spellAttester.schemaNameToResolver(ethers.utils.formatBytes32String(schemaName));
    const contract = new ethers.Contract(resolverAddress, [], provider);
    const filters = topics?.length > 0
        ? {
                address: contract.address,
                topics,
            }
        : '*';
    const events = await contract.queryFilter(filters);
    return Promise.all(events.map(async event => ({
        ...event,
        attester: ethers.utils.defaultAbiCoder.decode(['address'], event.topics[1])[0],
        type: `${eventTypes[event.topics[0]] ?? 'Unknown'} ${schemaName}`,
        date: await getDateFromBlockNumber(provider, event.blockNumber),
        url: await generateAttestationUrl(provider, event.data),
        attestation: await getAttestationData(provider, event.data),
    })));
};

export const getIdentityEvents = async function (provider, filterBy) {
    const eventTypes = {
        [ethers.utils.id('Created(bytes32,address,bytes32)')]: 'Attested',
        [ethers.utils.id('Removed(bytes32,address,bytes32)')]: 'Revoked',
    };
    const topics = [
        null, // all event types
        filterBy?.attester ? ethers.utils.hexZeroPad(filterBy.attester, 32) : null,
        filterBy?.userPseudonym ? ethers.utils.keccak256(ethers.utils.toUtf8Bytes(filterBy.userPseudonym)) : null,
    ];
    return await getResolverEvents(provider, 'identity', eventTypes, topics);
};

export const getSpellEvents = async function (provider, filterBy) {
    const eventTypes = {
        [ethers.utils.id('Created(bytes32,address,bytes32)')]: 'Attested',
        [ethers.utils.id('Removed(bytes32,address,bytes32)')]: 'Revoked',
    };
    const topics = [
        null, // all event types
        filterBy?.attester ? ethers.utils.hexZeroPad(filterBy.attester, 32) : null,
        filterBy?.payloadId ? ethers.utils.keccak256(ethers.utils.toUtf8Bytes(filterBy.payloadId)) : null,
    ];
    return await getResolverEvents(provider, 'spell', eventTypes, topics);
};

export const getDeploymentEvents = async function (provider, filterBy) {
    const eventTypes = {
        [ethers.utils.id('Created(bytes32,address,bytes32)')]: 'Attested',
        [ethers.utils.id('Removed(bytes32,address,bytes32)')]: 'Revoked',
    };
    const topics = [
        null, // all event types
        filterBy?.attester ? ethers.utils.hexZeroPad(filterBy.attester, 32) : null,
        filterBy?.payloadId ? ethers.utils.keccak256(ethers.utils.toUtf8Bytes(filterBy.payloadId)) : null,
    ];
    return await getResolverEvents(provider, 'deployment', eventTypes, topics);
};

export const getAtttestationEventsByAttester = async function (provider, attester) {
    const events = await Promise.all([
        ...await getIdentityEvents(provider, { attester }),
        ...await getSpellEvents(provider, { attester }),
        ...await getDeploymentEvents(provider, { attester }),
    ]);
    return events.sort((a, b) => a.date.getTime() - b.date.getTime());
};

export const getSpellStatus = async function (provider, payloadId) {
    const spellAttester = await getSpellAttesterContract(provider);
    let address;
    let reason;
    let message;
    try {
        address = await spellAttester.getSpellAddressByPayloadId(payloadId);
        message = `The spell "${address}" was deployed and reviewed`;
    } catch (error) {
        reason = error.reason;
        message = `Spell is not found or not ready: "${reason}"`;
    }
    const spellEvents = await getSpellEvents(provider, { payloadId });
    const allSpellMemberPseudonyms = [
        ...spellEvents.map(a => a.data.crafter),
        ...spellEvents.map(a => a.data.reviewerA),
        ...spellEvents.map(a => a.data.reviewerB),
    ];
    const uniqueSpellMemberPseudonyms = [...new Set(allSpellMemberPseudonyms)];
    const memberEvents = await Promise.all(uniqueSpellMemberPseudonyms.map((userPseudonym) => {
        return getIdentityEvents(provider, { userPseudonym });
    }));
    const events = [
        ...spellEvents,
        ...await getDeploymentEvents(provider, { payloadId }),
        ...memberEvents.flat(),
    ].sort((a, b) => a.date.getTime() - b.date.getTime());
    return {
        address,
        reason,
        message,
        events,
    };
};
