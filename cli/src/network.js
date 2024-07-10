import process from 'node:process';
import fs from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import ethers from 'ethers';

export const __filename = fileURLToPath(import.meta.url);
export const __dirname = dirname(__filename);
export const configPath = join(__dirname, '..', 'config.json');
export const envPath = join(process.cwd(), '.env');

export const getConfig = async function (signerOrProvider) {
    const networkData = await signerOrProvider.getNetwork();
    const config = JSON.parse(fs.readFileSync(configPath));
    if (!config[networkData.chainId]) {
        throw new Error(`Unsupported chain id "${networkData.chainId}"`);
    }
    return { ...config[networkData.chainId], chainId: networkData.chainId };
};

export const getProvider = async function () {
    if (!process.env.RPC_URL) {
        throw new Error('Please provide RPC_URL env variable to enable interactions with blockchain');
    }
    const provider = new ethers.providers.JsonRpcProvider({
        url: process.env.RPC_URL,
        timeout: 1000,
    });
    try {
        await provider.getNetwork();
    } catch (error) {
        throw new Error(`Provided RPC_URL ("${process.env.RPC_URL}") is incorrect: ${error.reason}`);
    }
    return provider;
};

export const getSigner = function (provider) {
    if (!process.env.PRIVATE_KEY) {
        throw new Error('Please provide PRIVATE_KEY env variable to be able to submit transactions');
    }
    return new ethers.Wallet(process.env.PRIVATE_KEY, provider);
};

export const getDateFromBlockNumber = async function (provider, blockNumber) {
    const block = await provider.getBlock(blockNumber);
    if (!block?.timestamp) {
        throw new Error('Received incorrect timestamp value');
    }
    return new Date(block.timestamp * 1000);
};
