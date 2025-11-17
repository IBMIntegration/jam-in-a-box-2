#!/usr/bin/env node

import { readFile } from 'fs/promises';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';

import apim from './details/apim.js';
import openShiftConsole from './details/openshift-console.js';
import gateway from './details/gateway.js';
import platformNavigator from './details/platform-navigator.js';
import startHereApp from './details/start-here-app.js';

// Get current directory for ES modules
const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

/**
 * Read and parse a JSON file
 * @param {string} filePath - Path to the JSON file
 * @returns {Promise<Object>} Parsed JSON data
 */
async function readJsonFile(filePath) {
  try {
    const data = await readFile(filePath, 'utf8');
    return JSON.parse(data);
  } catch (error) {
    console.error(`Error reading file ${filePath}:`, error.message);
    return null;
  }
}

/**
 * Generate a basic report on JSON file contents
 * @param {Object} data - Parsed JSON data
 */
function generateReport(data) {
  console.log(`\n=== Report ===`);

  if (!data) {
    console.log('❌ Failed to read or parse file');
    return;
  }

  console.log('Start here')
  const shDetails = startHereApp(data);
  console.log(JSON.stringify(shDetails, null, 2));

  console.log('Platform Navigator Details:');
  const pnDetails = platformNavigator(data);
  console.log(JSON.stringify(pnDetails, null, 2));

  console.log('OpenShift Console Details:');
  const ocDetails = openShiftConsole(data);
  console.log(JSON.stringify(ocDetails, null, 2));

  console.log('API Gateway Details:');
  const gwDetails = gateway(data);
  console.log(JSON.stringify(gwDetails, null, 2));

  console.log('API Manager Details:');
  const amDetails = apim(data);
  console.log(JSON.stringify(amDetails, null, 2));

  console.log('✅ File read successfully');
  console.log(`📊 Data type: ${typeof data}`);

  if (Array.isArray(data)) {
    console.log(`📋 Array with ${data.length} items`);
    if (data.length > 0) {
      console.log(`🔍 First item type: ${typeof data[0]}`);
    }
  } else if (typeof data === 'object' && data !== null) {
    const keys = Object.keys(data);
    console.log(`🗂️  Object with ${keys.length} keys`);
    if (keys.length > 0) {
      console.log(`🔑 Keys: ${keys.slice(0, 5).join(', ')}${keys.length > 5 ? '...' : ''}`);
    }
  }

  console.log(`📏 JSON size: ${JSON.stringify(data).length} characters`);
}

/**
 * Main function to process two JSON files
 */
async function main() {
  // Get file paths from command line arguments
  const args = process.argv.slice(2);

  if (args.length !== 2) {
    console.error('❌ Error: Two JSON file paths are required');
    console.error('Usage: node get-server-detail.js <output-file> <secret-file>');
    console.error('Example: node get-server-detail.js /tmp/output.abc123 /tmp/secret.def456');
    process.exit(1);
  }

  const [file1Path, file2Path] = args;

  console.log('🔍 Server Detail Reporter');
  console.log('========================');
  console.log(`Reading files:`);
  console.log(`  📁 File 1: ${file1Path}`);
  console.log(`  📁 File 2: ${file2Path}`);

  // Read both files
  const [data1, data2] = await Promise.all([
    readJsonFile(file1Path),
    readJsonFile(file2Path)
  ]);

  // Verify both files were read successfully
  if (!data1 || !data2) {
    console.log('⚠️  Some files could not be processed');
    process.exit(1);
  }

  // Ensure both are arrays
  if (!Array.isArray(data1) || !Array.isArray(data2)) {
    console.error('❌ Error: Both files must contain JSON arrays');
    console.error(`File 1 type: ${Array.isArray(data1) ? 'array' : typeof data1}`);
    console.error(`File 2 type: ${Array.isArray(data2) ? 'array' : typeof data2}`);
    process.exit(1);
  }

  // Concatenate both arrays
  const combinedData = [...data1, ...data2];

  // Generate single report for combined data
  generateReport(combinedData);

  // Summary
  console.log('\n=== Summary ===');
  console.log(`✅ ${file1Path} (${data1.length} items)`);
  console.log(`✅ ${file2Path} (${data2.length} items)`);
  console.log(`🎉 Combined ${combinedData.length} items processed successfully`);
}

// Handle command line arguments for custom file paths
if (process.argv.includes('--help') || process.argv.includes('-h')) {
  console.log('Usage: node get-server-detail.js <output-file> <secret-file>');
  console.log('');
  console.log('Arguments:');
  console.log('  output-file   Path to the output JSON file');
  console.log('  secret-file   Path to the secret JSON file');
  console.log('');
  console.log('Example:');
  console.log('  node get-server-detail.js /tmp/output.abc123 /tmp/secret.def456');
  process.exit(0);
}

// Run the main function
main().catch(error => {
  console.error('💥 Unexpected error:', error);
  process.exit(1);
});
