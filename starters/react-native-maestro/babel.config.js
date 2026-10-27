// Merge into your babel.config.js; add the plugin as a pinned dev dependency:
//   yarn add -D babel-plugin-transform-inline-environment-variables@0.4.4
module.exports = {
  presets: ['module:@react-native/babel-preset'],
  plugins: [['transform-inline-environment-variables', {include: ['VERIFY_E2E', 'E2E_API_URL']}]],
};
