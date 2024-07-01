import ethers from 'ethers';
import { EAS, SchemaRegistry } from '@ethereum-attestation-service/eas-sdk';
import { getConfig, getSigner } from './network.js';

const ABIs = {
    easAttesterLike: [
        'function attest(bytes memory request) external payable returns (bytes32)',
        'function revoke(bytes memory request) external payable',
    ],
    spellAttesterLike: [
        'function deny(address usr) external',
        'function easAttester() external view returns (address)',
        'function easRegistry() external view returns (address)',
        'function fileSchema(bytes32 name, bytes32 id) external',
        'function rely(address usr) external',
        'function schemaNameToResolver(bytes32) external view returns (address)',
        'function schemaNameToSchemaId(bytes32) external view returns (bytes32)',
        'function getSpellAddressByPayloadId(string memory payloadId) external view returns (address)',
        'function wards(address) external view returns (uint256)',
    ],
};

export const getSpellAttesterContract = async function (provider) {
    const config = await getConfig(provider);
    if (!config.spellAttesterAddress) {
        throw new Error(`SpellAttester is not yet deployed to chain "${config.chainId}"`);
    }
    return new ethers.Contract(config.spellAttesterAddress, ABIs.spellAttesterLike, provider);
};

export const getEasRegistryContract = async function (provider) {
    const spellAttester = await getSpellAttesterContract(provider);
    const easRegistryAddress = await spellAttester.easRegistry();
    return new SchemaRegistry(easRegistryAddress).connect(getSigner(provider));
};

export const getEasAttesterContract = async function (provider) {
    const spellAttester = await getSpellAttesterContract(provider);
    const easAttesterAddress = await spellAttester.easAttester();
    return new EAS(easAttesterAddress).connect(getSigner(provider));
};
