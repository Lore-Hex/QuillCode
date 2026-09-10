const path = require('node:path');
const { build } = require(path.join(process.env.GITHUB_WORKSPACE, 'desktop/package.json'));

module.exports = {
  ...build,
  forceCodeSigning: true,
  mac: {
    ...build.mac,
    notarize: false,
    // These directories intentionally contain both architecture-specific helpers.
    x64ArchFiles: 'Contents/Resources/{app.asar.unpacked/node_modules/node-pty/prebuilds/darwin-{arm64,x64}/{pty.node,spawn-helper},resources/runtime/native/darwin/prebuilds/darwin-{arm64,x64}/darwin-modifiers.node}',
    binaries: ['Contents/Resources/resources/runtime/tr-cowork'],
  },
};
