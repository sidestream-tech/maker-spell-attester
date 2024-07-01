import ethers from 'ethers';

export const decodeAttestationData = function (schema, attestation) {
    const optionTypes = schema.split(',').map(e => e.trim());
    const decodedArray = ethers.utils.defaultAbiCoder.decode(
        optionTypes,
        attestation.data,
    );
    // Keep only named values
    const decodedObject = {};
    for (const key of Object.keys(decodedArray)) {
        if (/^\+?\d+$/.test(key)) {
            continue;
        }
        decodedObject[key] = decodedArray[key];
    }
    return decodedObject;
};

export const encodeAttestationData = function (schema, options) {
    const optionValues = [];
    const optionTypes = schema.split(',').map(e => e.trim());
    for (const optionType of optionTypes) {
        const [type, key] = optionType.split(' ');
        const value = options[key];
        if (!value) {
            throw new Error(`Option "${key}" can not be empty`);
        }
        if (type === 'address') {
            try {
                ethers.utils.getAddress(value);
            } catch (error) {
                throw new Error(`Option "${key}" is invalid, please ensure checksummed format`);
            }
        }
        if (type === 'bytes32') {
            const valueBytes = ethers.utils.arrayify(value);
            if (!ethers.utils.isBytes(valueBytes) || valueBytes.length !== 32) {
                throw new Error(`Option "${key}" is invalid, please ensure bytes32 format`);
            }
            // Use converted value instead of the string
            optionValues.push(valueBytes);
            continue;
        }
        optionValues.push(value);
    }
    return ethers.utils.defaultAbiCoder.encode(
        optionTypes,
        optionValues,
    );
};

export const formatAttestationEvent = function (event) {
    return {
        type: event.type,
        date: event.date,
        url: event.url,
    };
};