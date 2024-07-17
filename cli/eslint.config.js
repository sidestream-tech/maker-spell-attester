import antfu from '@antfu/eslint-config';

export default antfu({
    stylistic: {
        indent: 4,
        semi: true,
    },
    typescript: true,
    jsonc: false,
    rules: {
        'style/brace-style': ['error', '1tbs'],
        'no-console': [
            'error',
            {
                allow: ['info', 'warn', 'error', 'table', 'trace'],
            },
        ],
    },
});
