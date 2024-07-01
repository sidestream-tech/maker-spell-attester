require('dotenv').config();
require('@nomiclabs/hardhat-waffle');
const process = require('node:process');

/**
 * @type import('hardhat/config').HardhatUserConfig
 */
module.exports = {
    solidity: '0.8.13',
    networks: {
        hardhat: {
            chainId: 11155111,
            forking: {
                url: process.env.SEPOLIA_RPC_URL || process.env.RPC_URL,
            },
        },
    },
};
