const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');

// Configuration
const CIRCUIT_NAME = 'ConsensusSequence';
const PTAU_SIZE = 20; // 2^12 constraints
const rootDir = path.resolve(__dirname, '..');
const buildDir = path.join(rootDir, 'build');
const circuitFile = path.join(rootDir, `${CIRCUIT_NAME}.circom`);

// Create build directory
if (!fs.existsSync(buildDir)) {
    fs.mkdirSync(buildDir, { recursive: true });
}

// Helper function to run commands with better output
function runCommand(cmd, errorMsg) {
    try {
        console.log(`$ ${cmd}`);
        const output = execSync(cmd, { stdio: 'pipe', encoding: 'utf-8' });
        console.log(output);
        return true;
    } catch (error) {
        console.error(`❌ ${errorMsg}`);
        console.error(`Command: ${error.cmd}`);
        console.error(`Exit code: ${error.status}`);
        console.error(error.stderr);
        return false;
    }
}

// 1. Compile Circuit
console.log('🔨 Compiling circuit...');
if (!runCommand(
    `circom "${circuitFile}" --r1cs --wasm --sym --output "${buildDir}"`,
    'Circuit compilation failed'
)) process.exit(1);

// 2. Generate Powers of Tau
console.log('⚙️ Generating Powers of Tau...');
const ptauFiles = {
    initial: path.join(buildDir, `pot${PTAU_SIZE}_0000.ptau`),
    contributed: path.join(buildDir, `pot${PTAU_SIZE}_0001.ptau`),
    final: path.join(buildDir, `powersOfTau28_hez_final_${PTAU_SIZE}.ptau`)
};

// Phase 1: New ceremony
if (!fs.existsSync(ptauFiles.initial)) {
    if (!runCommand(
        `snarkjs powersoftau new bn128 ${PTAU_SIZE} "${ptauFiles.initial}" -v`,
        'Failed to initialize Powers of Tau'
    )) process.exit(1);
}

// Phase 1: Contribute
if (!fs.existsSync(ptauFiles.contributed)) {
    if (!runCommand(
        `snarkjs powersoftau contribute "${ptauFiles.initial}" "${ptauFiles.contributed}" -v -e="$(date +%s)"`,
        'Failed to contribute to ceremony'
    )) process.exit(1);
}

// Prepare Phase 2
if (!fs.existsSync(ptauFiles.final)) {
    if (!runCommand(
        `snarkjs powersoftau prepare phase2 "${ptauFiles.contributed}" "${ptauFiles.final}" -v`,
        'Failed to prepare Phase 2'
    )) {
        console.log('⚠️ Trying alternative preparation method...');
        if (!runCommand(
            `snarkjs powersoftau verify "${ptauFiles.contributed}" && snarkjs powersoftau prepare phase2 "${ptauFiles.contributed}" "${ptauFiles.final}" -v`,
            'Phase 2 preparation failed completely'
        )) process.exit(1);
    }
}

// 3. Phase 2 Setup
console.log('⚙️ Performing Phase 2 setup...');
const zkeyPath = path.join(buildDir, 'circuit_final.zkey');
if (!runCommand(
    `snarkjs groth16 setup "${path.join(buildDir, `${CIRCUIT_NAME}.r1cs`)}" "${ptauFiles.final}" "${zkeyPath}"`,
    'Phase 2 setup failed'
)) {
    console.log('\n⚠️ Troubleshooting steps:');
    console.log('1. Delete all .ptau files and try again:');
    console.log(`   rm ${path.join(buildDir, 'pot*.ptau')}`);
    console.log(`   rm ${ptauFiles.final}`);
    console.log('2. Verify your system has enough RAM (16GB+ recommended)');
    console.log('3. Try reducing the circuit size for testing');
    process.exit(1);
}

console.log('\n✅ Setup completed successfully!');
console.log('Next steps:');
console.log(`1. Generate witness: npm run witness`);
console.log(`2. Generate proof: npm run prove`);
