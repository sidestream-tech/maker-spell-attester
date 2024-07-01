import crypto from 'node:crypto';
import { expect } from 'chai';
import { describe, it } from 'mocha';
import { getVariables, setVariable } from './configure.js';

describe('Configure command', () => {
    const path = `/tmp/.env-${crypto.randomUUID()}`;
    const key = 'TEST_KEY';
    const value = 'Test value';

    it('Should get and set variables', () => {
        expect(getVariables(path)).to.not.include({ [key]: value });
        setVariable(path, key, value);
        expect(getVariables(path)).to.include({ [key]: value });
    });
});
