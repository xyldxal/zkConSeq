const { execSync } = require('child_process');
const path = require('path');

const buildDir = path.join(__dirname, '../build');

console.log('Generating proof...');
execSync(`snarkjs groth16 prove ${path.join(buildDir, 'circuit_final.zkey')} ${path.join(buildDir, 'witness.wtns')} ${path.join(buildDir, 'proof.json')} ${path.join(buildDir, 'public.json')}`, { stdio: 'inherit' });

console.log('Proof generated!');