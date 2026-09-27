// Loads the browser scripts into Node for quick headless checks.
const fs = require('fs'), path = require('path'), vm = require('vm');
const root = path.join(__dirname, '..');
global.window = global;
global.Path2D = class { moveTo() {} lineTo() {} closePath() {} };
for (const f of ['tracks', 'car', 'physics', 'track', 'strategy', 'brain', 'driver', 'race'])
  if (fs.existsSync(path.join(root, 'js', f + '.js'))) vm.runInThisContext(fs.readFileSync(path.join(root, 'js', f + '.js'), 'utf8'), { filename: f + '.js' });
module.exports = global.SC;
