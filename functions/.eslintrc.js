module.exports = {
    env: {
        es6: true,
        node: true,
    },
    parserOptions: {
        ecmaVersion: 2020, // Supporte les fonctionnalités d'ES11
        sourceType: "module", // Permet l'utilisation de modules ES6
    },
    extends: [
        "eslint:recommended",
        "google",
    ],
    rules: {
        "no-restricted-globals": ["error", "name", "length"],
        "prefer-arrow-callback": "error",
        "no-unused-vars": ["error", {args: "none"}],
        "quotes": ["error", "double", {allowTemplateLiterals: true}],
        "max-len": ["error", {code: 120}],
        "indent": ["error", 4],
        "comma-dangle": ["error", "always-multiline"],
        "linebreak-style": "off",
        "require-jsdoc": "off",
        "valid-jsdoc": "off",
    },
    overrides: [
        {
            files: ["**/*.spec.*"],
            env: {
                mocha: true,
            },
            rules: {},
        },
    ],
    globals: {},
};
