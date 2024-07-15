import chai, { expect } from 'chai';
import chaiSubset from 'chai-subset';
import chaiAsPromised from 'chai-as-promised';
import { before, describe, it } from 'mocha';
import hardhat from 'hardhat';
import { getSpellAttesterContract } from './contracts.js';
import { formatAttestationEvent } from './helpers.js';
import {
    createAttestation,
    getAttestationData,
    getAtttestationEventsByAttester,
    getDeploymentEvents,
    getIdentityEvents,
    getSpellEvents,
    getSpellStatus,
    revokeAttestation,
} from './attestations.js';

chai.use(chaiSubset);
chai.use(chaiAsPromised);

// Publicly known private key
const HARDHAT_PRIVATE_KEY = '0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80';
const hardhatAddress = new hardhat.ethers.Wallet(HARDHAT_PRIVATE_KEY, hardhat.ethers.provider).getAddress();

// User with admin right to the SPELL_ATTESTER
const SPELL_ATTESTER_ADMIN = '0xB0EA9D686c474630b63FfCD7dFD6b20b9A2f6169';

describe('Attestation creation', () => {
    before(async () => {
        // set PRIVATE_KEY
        process.env.PRIVATE_KEY = HARDHAT_PRIVATE_KEY;
        // give admin rights to the above address
        const impersonatedSigner = await hardhat.ethers.getImpersonatedSigner(SPELL_ATTESTER_ADMIN);
        const spellAttester = (await getSpellAttesterContract(hardhat.ethers.provider)).connect(impersonatedSigner);
        await spellAttester.rely(await hardhatAddress);
    });

    // define test data
    const aliceWallet = hardhat.ethers.Wallet.createRandom();
    const alice = {
        teamName: 'team_a',
        userPseudonym: 'alice',
        userAddress: aliceWallet.address,
    };

    const arthur = {
        teamName: 'team_a',
        userPseudonym: 'arthur',
        userAddress: hardhat.ethers.Wallet.createRandom().address,
    };

    const bob = {
        teamName: 'team_b',
        userPseudonym: 'bob',
        userAddress: hardhat.ethers.Wallet.createRandom().address,
    };

    const spellAttestationData = {
        payloadId: '2024-04-01',
        crafter: alice.userPseudonym,
        reviewerA: arthur.userPseudonym,
        reviewerB: bob.userPseudonym,
    };

    const deploymentAttestationData = {
        payloadId: '2024-04-01',
        // Test contract on sepolia: https://sepolia.etherscan.io/address/0xf37cd0a4767b0496d137b467a5b3b7e1b828a9a0
        payloadAddress: '0xF37Cd0A4767b0496d137B467a5B3b7E1B828A9A0',
        payloadHash: '0xcbd506959c532fb23ec002b50154ec8e08b2889d480f3899b3d43e527aebb307',
    };

    it('Spell attester contract exists on chain', async () => {
        const spellAttesterAddress = (await getSpellAttesterContract(hardhat.ethers.provider)).address;
        expect(spellAttesterAddress).to.contain.string('0x');
        const code = await hardhat.ethers.provider.getCode(spellAttesterAddress);
        expect(code === '0x').to.be.equal(
            false,
            `Invalid empty code of the spell attester at ${spellAttesterAddress}.\nYou might want to run "npm run reset" to clean hardhat cache`,
        );
    });

    it('Should be able to create Identity attestation', async () => {
        const { id, url } = await createAttestation(
            hardhat.ethers.provider,
            'identity',
            alice,
        );
        expect(id).to.contain.string('0x');
        expect(url).to.contain.string('https://');
        const attestation = await getAttestationData(hardhat.ethers.provider, id);
        expect(attestation.data).to.containSubset(alice);
    });

    it('Should be able to create Spell attestation', async () => {
        await createAttestation(
            hardhat.ethers.provider,
            'identity',
            arthur,
        );
        await createAttestation(
            hardhat.ethers.provider,
            'identity',
            bob,
        );
        const { id, url } = await createAttestation(
            hardhat.ethers.provider,
            'spell',
            spellAttestationData,
        );
        expect(id).to.contain.string('0x');
        expect(url).to.contain.string('https://');
        const attestation = await getAttestationData(
            hardhat.ethers.provider,
            id,
        );
        expect(attestation.data).to.containSubset(spellAttestationData);
    });

    it('Should fetch all Identity events', async () => {
        const allIdentityAttestations = await getIdentityEvents(hardhat.ethers.provider);
        expect(allIdentityAttestations.length).to.be.gte(3);
        expect(allIdentityAttestations[allIdentityAttestations.length - 3].attestation.data).to.containSubset(alice);
        expect(allIdentityAttestations[allIdentityAttestations.length - 2].attestation.data).to.containSubset(arthur);
        expect(allIdentityAttestations[allIdentityAttestations.length - 1].attestation.data).to.containSubset(bob);
    });

    it('Should fetch specific Identity events', async () => {
        const arthurIdentityAttestations = await getIdentityEvents(hardhat.ethers.provider, { userPseudonym: arthur.userPseudonym });
        expect(arthurIdentityAttestations.length).to.be.equal(1);
        expect(arthurIdentityAttestations[0].attestation.data).to.containSubset(arthur);
    });

    it('Should fetch all Spell events', async () => {
        const spellAttestations = await getSpellEvents(hardhat.ethers.provider);
        expect(spellAttestations[spellAttestations.length - 1].attestation.data).to.containSubset(spellAttestationData);
    });

    it('Should fetch specific Spell events', async () => {
        const knownSpellAttestations = await getSpellEvents(hardhat.ethers.provider, { payloadId: spellAttestationData.payloadId });
        expect(knownSpellAttestations.length).to.be.equal(1);
        const unknownSpellAttestations = await getSpellEvents(hardhat.ethers.provider, { payloadId: 'unknown payloadId' });
        expect(unknownSpellAttestations.length).to.be.equal(0);
    });

    it('Should be able to create Deployment attestation', async () => {
        // setup
        const [wallet] = await hardhat.ethers.getSigners();
        await wallet.sendTransaction({
            to: aliceWallet.address,
            value: hardhat.ethers.utils.parseEther('1'),
        });
        process.env.PRIVATE_KEY = aliceWallet.privateKey;
        // test
        const { id, url } = await createAttestation(
            hardhat.ethers.provider,
            'deployment',
            deploymentAttestationData,
        );
        expect(id).to.contain.string('0x');
        expect(url).to.contain.string('https://');
        const attestation = await getAttestationData(
            hardhat.ethers.provider,
            id,
        );
        expect(attestation.data).to.containSubset(deploymentAttestationData);
        // undo setup
        process.env.PRIVATE_KEY = HARDHAT_PRIVATE_KEY;
    });

    it('Should fetch specific Deployment events', async () => {
        const knownEvents = await getDeploymentEvents(hardhat.ethers.provider, { payloadId: spellAttestationData.payloadId });
        expect(knownEvents.length).to.be.equal(1);
        expect(knownEvents[0].attestation.data).to.containSubset(deploymentAttestationData);
        const unknownEvents = await getDeploymentEvents(hardhat.ethers.provider, { payloadId: 'unknown payloadId' });
        expect(unknownEvents.length).to.be.equal(0);
    });

    it('Should be able to revoke attestation', async () => {
        const { id: attestationId } = await createAttestation(
            hardhat.ethers.provider,
            'identity',
            {
                teamName: 'team_c',
                userPseudonym: 'charlie',
                userAddress: hardhat.ethers.Wallet.createRandom().address,
            },
        );
        const { url } = await revokeAttestation(hardhat.ethers.provider, attestationId);
        expect(url).to.contain.string('https://');
        expect(url).to.contain.string(attestationId);
        const attestation = await getAttestationData(hardhat.ethers.provider, attestationId);
        expect(attestation.revocationTime).to.not.equal(0);
    });

    it('Should return spell status', async () => {
        // setup: remove private key to test it works without it
        process.env.PRIVATE_KEY = undefined;
        const spellStatus = await getSpellStatus(hardhat.ethers.provider, spellAttestationData.payloadId);
        expect(spellStatus.message).to.equal('Spell is not found or not ready: "SpellAttester/spell-not-yet-reviewed"');
        expect(spellStatus.events.length).to.be.gte(7);
        console.table(spellStatus.events.map(formatAttestationEvent));
        // undo setup
        process.env.PRIVATE_KEY = HARDHAT_PRIVATE_KEY;
    });

    it('Should return all attestations by one user', async () => {
        const adminAttestationEvents = await getAtttestationEventsByAttester(hardhat.ethers.provider, await hardhatAddress);
        expect(adminAttestationEvents.length).to.be.equal(6);
        const aliceAttestationEvents = await getAtttestationEventsByAttester(hardhat.ethers.provider, aliceWallet.address);
        expect(aliceAttestationEvents.length).to.be.equal(1);
    });

    it('Should throw if attestation is not found', async () => {
        await expect(revokeAttestation(hardhat.ethers.provider, hardhat.ethers.constants.HashZero)).to.be.rejectedWith(Error, 'Attestation with uid not found');
    });
});
