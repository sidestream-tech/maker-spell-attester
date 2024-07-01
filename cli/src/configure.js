import fs from 'node:fs';
import dotenv from 'dotenv';

export const getVariables = function (path) {
    const variables = {};
    dotenv.config({ path, processEnv: variables, encoding: 'utf-8' });
    return variables;
};

const serialize = function (variables) {
    let content = '';
    for (const [key, value] of Object.entries(variables)) {
        content += `${key}=${JSON.stringify(value)}\n`;
    }
    return content;
};

export const setVariable = function (path, key, value) {
    const variables = getVariables();
    variables[key] = value;
    fs.writeFileSync(path, serialize(variables));
};
