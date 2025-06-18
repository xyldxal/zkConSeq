const { execSync } = require('child_process');
const path = require('path');

const buildDir = path.join(__dirname, '../build');

console.log('Verifying proof...');
execSync(`snarkjs groth16 verify ${path.join(buildDir, 'verification_key.json')} ${path.join(buildDir, 'public.json')} ${path.join(buildDir, 'proof.json')}`, { stdio: 'inherit' });