#!/usr/bin/env node

import { spawn } from 'child_process';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

/**
 * Run a test script and return results
 */
function runTest(scriptPath, testName) {
  return new Promise((resolve) => {
    console.log(`🏃 Running ${testName}...`);
    
    const child = spawn('node', [scriptPath], {
      stdio: 'pipe',
      cwd: __dirname
    });

    let stdout = '';
    let stderr = '';

    child.stdout.on('data', (data) => {
      stdout += data.toString();
    });

    child.stderr.on('data', (data) => {
      stderr += data.toString();
    });

    child.on('close', (code) => {
      console.log(stdout);
      if (stderr) {
        console.error(stderr);
      }
      
      const success = code === 0;
      console.log(`${success ? '✅' : '❌'} ${testName} ${success ? 'PASSED' : 'FAILED'}\n`);
      
      resolve({ success, code, stdout, stderr });
    });
  });
}

/**
 * Main test runner
 */
async function runAllTests() {
  console.log('🧪 MD Handler Test Suite');
  console.log('========================\n');

  const tests = [
    {
      name: 'Template Parser Unit Tests',
      script: path.join(__dirname, 'test-templates.js')
    },
    {
      name: 'Integration Tests',
      script: path.join(__dirname, 'test-integration.js')
    }
  ];

  let totalPassed = 0;
  let totalFailed = 0;

  for (const test of tests) {
    const result = await runTest(test.script, test.name);
    if (result.success) {
      totalPassed++;
    } else {
      totalFailed++;
    }
  }

  console.log('📊 Final Results:');
  console.log('=================');
  console.log(`✅ Test Suites Passed: ${totalPassed}`);
  console.log(`❌ Test Suites Failed: ${totalFailed}`);
  console.log(`📋 Total Test Suites: ${tests.length}\n`);

  if (totalFailed > 0) {
    console.log('❌ Some tests failed. Please review the output above.');
    process.exit(1);
  } else {
    console.log('✅ All tests passed! 🎉');
    process.exit(0);
  }
}

// Run if called directly
if (import.meta.url === `file://${process.argv[1]}`) {
  runAllTests().catch((error) => {
    console.error('❌ Test runner failed:', error);
    process.exit(1);
  });
}

export { runAllTests };