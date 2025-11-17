#!/usr/bin/env node

import { resolveFile, updateTemplateConfig } from '../src/file-handler.js';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

/**
 * Integration test for file resolution with template processing
 */
async function runIntegrationTest() {
  console.log('🔗 Running Integration Tests\n');

  try {
    // Set up test configuration
    updateTemplateConfig({
      variables: {
        title: 'Integration Test Document',
        author: 'Test Runner',
        date: '2025-11-09',
        organization: 'Test Organization',
        version: '2.0.0'
      }
    });

    const testContentDir = path.join(__dirname, '..', 'test-content');
    
    // Test 1: Request HTML file that doesn't exist, should fallback to MD with template processing
    console.log('📝 Test 1: Template processing in markdown file');
    const result = await resolveFile('/sample.html', testContentDir);
    
    if (result.status === 200) {
      const content = result.buffer.toString();
      
      // Check that templates were processed
      const checks = [
        { name: 'Title substitution', test: content.includes('Integration Test Document') },
        { name: 'Author substitution', test: content.includes('Test Runner') },
        { name: 'Date substitution', test: content.includes('2025-11-09') },
        { name: 'Failed substitution styling', test: content.includes('failed-substitution') },
        { name: 'HTML structure', test: content.includes('<!DOCTYPE html>') },
        { name: 'CSS styling', test: content.includes('.failed-substitution') }
      ];

      let passed = 0;
      for (const check of checks) {
        if (check.test) {
          console.log(`  ✅ ${check.name}`);
          passed++;
        } else {
          console.log(`  ❌ ${check.name}`);
        }
      }

      console.log(`\n  Results: ${passed}/${checks.length} checks passed`);
      
      if (passed === checks.length) {
        console.log('✅ Integration test PASSED\n');
      } else {
        console.log('❌ Integration test FAILED\n');
        console.log('Generated content preview:');
        console.log(content.substring(0, 500) + '...\n');
      }
    } else {
      console.log(`❌ File resolution failed with status: ${result.status}`);
      console.log(`   Error: ${result.buffer.toString()}\n`);
    }

    // Test 2: Test configuration updates
    console.log('⚙️  Test 2: Configuration update test');
    
    // Update config
    updateTemplateConfig({
      variables: {
        title: 'Updated Title',
        author: 'Updated Author'
      }
    });

    const result2 = await resolveFile('/sample.html', testContentDir);
    if (result2.status === 200) {
      const content2 = result2.buffer.toString();
      if (content2.includes('Updated Title') && content2.includes('Updated Author')) {
        console.log('  ✅ Configuration update working correctly\n');
      } else {
        console.log('  ❌ Configuration update failed\n');
      }
    }

    // Test 3: Test non-existent file
    console.log('🚫 Test 3: Non-existent file handling');
    const result3 = await resolveFile('/nonexistent.html', testContentDir);
    if (result3.status === 404) {
      console.log('  ✅ 404 handling working correctly\n');
    } else {
      console.log(`  ❌ Expected 404, got ${result3.status}\n`);
    }

  } catch (error) {
    console.error('❌ Integration test failed with error:', error);
  }
}

// Run the integration test
runIntegrationTest().catch(console.error);