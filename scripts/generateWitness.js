const { execSync } = require('child_process');
const path = require('path');

const buildDir = path.join(__dirname, '../build');
const wasmPath = path.join(buildDir, 'ConsensusSequence_js/ConsensusSequence.wasm');
const inputPath = path.join(__dirname, '../test/input.json');
const witnessPath = path.join(buildDir, 'witness.wtns');

try {
    execSync(`node ${wasmPath} ${inputPath} ${witnessPath}`, {
        stdio: 'inherit'
    });
    console.log('✓ Witness generated');
} catch (error) {
    console.error('Witness generation failed');
    process.exit(1);
}