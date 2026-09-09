const path = require('node:path');
const { build } = require(path.join(process.env.GITHUB_WORKSPACE, 'desktop/package.json'));

module.exports = {
  ...build,
  forceCodeSigning: true,
  mac: {
    ...build.mac,
    notarize: false,
    binaries: ['Contents/Resources/resources/runtime/tr-cowork'],
  },
};
