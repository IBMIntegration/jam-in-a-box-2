#!/usr/bin/env node

import { parseTemplateVariables, updateTemplateConfig, getTemplateConfig } from '../src/file-handler.js';

/**
 * Test runner for template parsing functionality
 */
class TemplateTestRunner {
  constructor() {
    this.tests = [];
    this.passed = 0;
    this.failed = 0;
  }

  /**
   * Add a test case
   * @param {string} name - Test name
   * @param {Function} testFn - Test function
   */
  test(name, testFn) {
    this.tests.push({ name, testFn });
  }

  /**
   * Assert that two values are equal
   * @param {*} actual - Actual value
   * @param {*} expected - Expected value
   * @param {string} message - Error message
   */
  assertEqual(actual, expected, message = '') {
    if (actual !== expected) {
      throw new Error(`${message}\nExpected: ${JSON.stringify(expected)}\nActual  : ${JSON.stringify(actual)}`);
    }
  }

  /**
   * Assert that actual contains expected substring
   * @param {string} actual - Actual string
   * @param {string} expected - Expected substring
   * @param {string} message - Error message
   */
  assertContains(actual, expected, message = '') {
    if (!actual.includes(expected)) {
      throw new Error(`${message}\nExpected "${actual}" to contain "${expected}"`);
    }
  }

  /**
   * Run all tests
   */
  async run() {
    console.log('🧪 Running Template Parser Tests\n');

    for (const { name, testFn } of this.tests) {
      try {
        await testFn();
        console.log(`✅ ${name}`);
        this.passed++;
      } catch (error) {
        console.log(`❌ ${name}`);
        console.log(`   Error: ${error.message}\n`);
        this.failed++;
      }
    }

    console.log(`\n📊 Test Results:`);
    console.log(`✅ Passed: ${this.passed}`);
    console.log(`❌ Failed: ${this.failed}`);
    console.log(`📋 Total: ${this.tests.length}`);

    if (this.failed > 0) {
      process.exit(1);
    }
  }
}

// Create test runner instance
const runner = new TemplateTestRunner();

// Test: Basic variable substitution
runner.test('Basic variable substitution', () => {
  updateTemplateConfig({
    variables: {
      title: 'My Document',
      author: 'John Doe'
    }
  });

  const input = 'Title: {{ title }}\nAuthor: {{ author }}';
  const expected = 'Title: My Document\nAuthor: John Doe';
  const actual = parseTemplateVariables(input);
  
  runner.assertEqual(actual, expected, 'Basic substitution failed');
});

// Test: Variable with default value
runner.test('Variable with default value', () => {
  updateTemplateConfig({ variables: {} });

  const input = 'Title: {{ title | Default Title }}';
  const expected = 'Title: Default Title';
  const actual = parseTemplateVariables(input);
  
  runner.assertEqual(actual, expected, 'Default value substitution failed');
});

// Test: Variable with default overridden by config
runner.test('Variable with default overridden by config', () => {
  updateTemplateConfig({
    variables: {
      title: 'Config Title'
    }
  });

  const input = 'Title: {{ title | Default Title }}';
  const expected = 'Title: Config Title';
  const actual = parseTemplateVariables(input);
  
  runner.assertEqual(actual, expected, 'Config should override default');
});

// Test: Whitespace handling
runner.test('Whitespace handling', () => {
  updateTemplateConfig({
    variables: {
      name: 'Test'
    }
  });

  const input = `{{  name  }}
{{
  name
}}
{{name|default value}}
{{ name | default value }}`;
  
  const expected = `Test
Test
Test
Test`;
  
  const actual = parseTemplateVariables(input);
  runner.assertEqual(actual, expected, 'Whitespace handling failed');
});

// Test: Escaped braces in default
runner.test('Escaped braces in default', () => {
  updateTemplateConfig({ variables: {} });

  const input = '{{ code | function() \\{ return true; \\} }}';
  const expected = 'function() { return true; }';
  const actual = parseTemplateVariables(input);
  
  runner.assertEqual(actual, expected, 'Escaped braces not handled correctly');
});

// Test: Multiple variables in one line
runner.test('Multiple variables in one line', () => {
  updateTemplateConfig({
    variables: {
      first: 'John',
      last: 'Doe'
    }
  });

  const input = 'Name: {{ first }} {{ last }}';
  const expected = 'Name: John Doe';
  const actual = parseTemplateVariables(input);
  
  runner.assertEqual(actual, expected, 'Multiple variables failed');
});

// Test: Spaces in default values preserved
runner.test('Spaces in default values preserved', () => {
  updateTemplateConfig({ variables: {} });

  const input = '{{ description |   This has   multiple   spaces   }}';
  const expected = 'This has   multiple   spaces';
  const actual = parseTemplateVariables(input);
  
  runner.assertEqual(actual, expected, 'Spaces in default not preserved');
});

// Test: Multi-line default values
runner.test('Multi-line default values', () => {
  updateTemplateConfig({ variables: {} });

  const input = `{{ content | Line 1
Line 2
  Indented line }}`;
  
  const expected = `Line 1
Line 2
  Indented line`;
  
  const actual = parseTemplateVariables(input);
  runner.assertEqual(actual, expected, 'Multi-line default failed');
});

// Test: Failed substitution (no config, no default)
runner.test('Failed substitution creates error span', () => {
  updateTemplateConfig({ variables: {} });

  // Capture console.warn calls
  const originalWarn = console.warn;
  let warnCalled = false;
  console.warn = (...args) => {
    warnCalled = true;
    if (args[0].includes("Template variable 'missing' not found")) {
      // Expected warning
    }
  };

  const input = '{{ missing }}';
  const expected = '<span class=\'failed-substitution\'>missing</span>';
  const actual = parseTemplateVariables(input);
  
  console.warn = originalWarn; // Restore original

  runner.assertEqual(actual, expected, 'Failed substitution not handled correctly');
  runner.assertEqual(warnCalled, true, 'Warning should have been logged');
});

// Test: Variable names with numbers and underscores
runner.test('Variable names with numbers and underscores', () => {
  updateTemplateConfig({
    variables: {
      var_1: 'Variable One',
      test_var_2: 'Variable Two',
      _private: 'Private Var'
    }
  });

  const input = '{{ var_1 }}, {{ test_var_2 }}, {{ _private }}';
  const expected = 'Variable One, Variable Two, Private Var';
  const actual = parseTemplateVariables(input);
  
  runner.assertEqual(actual, expected, 'Complex variable names failed');
});

// Test: Empty default value
runner.test('Empty default value', () => {
  updateTemplateConfig({ variables: {} });

  const input = '{{ empty | }}';
  const expected = '';
  const actual = parseTemplateVariables(input);
  
  runner.assertEqual(actual, expected, 'Empty default not handled');
});

// Test: Variables that look like other variables
runner.test('Similar variable names', () => {
  updateTemplateConfig({
    variables: {
      name: 'John',
      name_full: 'John Doe',
      user_name: 'johndoe'
    }
  });

  const input = '{{ name }}, {{ name_full }}, {{ user_name }}';
  const expected = 'John, John Doe, johndoe';
  const actual = parseTemplateVariables(input);
  
  runner.assertEqual(actual, expected, 'Similar variable names failed');
});

// Test: Special characters in default values
runner.test('Special characters in default values', () => {
  updateTemplateConfig({ variables: {} });

  const input = '{{ special | <>&"\'%$#@!()[]{}+ }}';
  const expected = '<>&"\'%$#@!()[]{}+';
  const actual = parseTemplateVariables(input);
  
  runner.assertEqual(actual, expected, 'Special characters not preserved');
});

// Test: Template variables in markdown context
runner.test('Template variables in markdown context', () => {
  updateTemplateConfig({
    variables: {
      title: 'Test Document',
      author: 'Jane Smith',
      version: '2.1.0'
    }
  });

  const input = `# {{ title }}

**Author:** {{ author }}
**Version:** {{ version | 1.0.0 }}

This is a {{ type }} document.`;

  const expected = `# Test Document

**Author:** Jane Smith
**Version:** 2.1.0

This is a <span class='failed-substitution'>type</span> document.`;

  const actual = parseTemplateVariables(input);
  try {
    runner.assertContains(actual, 'Test Document', 'Title not substituted');
    runner.assertContains(actual, 'Jane Smith', 'Author not substituted'); 
    runner.assertContains(actual, '2.1.0', 'Version not substituted');
    runner.assertContains(actual, 'failed-substitution', 'Missing variable not marked as failed');
  } catch (error) {
    console.error('Actual output:', actual);
    console.error('Template config:', getTemplateConfig());
    throw error;
  }
});

// Test: Configuration update functionality
runner.test('Configuration updates work correctly', () => {
  // Set initial config
  updateTemplateConfig({
    variables: {
      test: 'initial'
    }
  });

  let result = parseTemplateVariables('{{ test }}');
  runner.assertEqual(result, 'initial', 'Initial config failed');

  // Update config
  updateTemplateConfig({
    variables: {
      test: 'updated'
    }
  });

  result = parseTemplateVariables('{{ test }}');
  runner.assertEqual(result, 'updated', 'Config update failed');
});

// Test: Get template config function
runner.test('Get template config returns current config', () => {
  const testConfig = {
    variables: {
      test_var: 'test_value'
    },
    other_property: 'other_value'
  };

  updateTemplateConfig(testConfig);
  const retrievedConfig = getTemplateConfig();
  
  runner.assertEqual(retrievedConfig.variables.test_var, 'test_value', 'Config retrieval failed');
});

// Test: Large template with many variables
runner.test('Large template with many variables', () => {
  const config = { variables: {} };
  for (let i = 0; i < 50; i++) {
    config.variables[`var${i}`] = `value${i}`;
  }
  updateTemplateConfig(config);

  let input = '';
  let expected = '';
  for (let i = 0; i < 50; i++) {
    input += `{{ var${i} }} `;
    expected += `value${i} `;
  }

  const actual = parseTemplateVariables(input);
  runner.assertEqual(actual, expected, 'Large template failed');
});

// Test: Performance with many substitutions
runner.test('Performance test with repeated substitutions', () => {
  updateTemplateConfig({
    variables: {
      name: 'Test'
    }
  });

  const input = '{{ name }}'.repeat(1000);
  const expected = 'Test'.repeat(1000);
  
  const startTime = Date.now();
  const actual = parseTemplateVariables(input);
  const endTime = Date.now();
  
  runner.assertEqual(actual, expected, 'Performance test failed');
  
  // Should complete in reasonable time (less than 100ms for 1000 substitutions)
  const duration = endTime - startTime;
  if (duration > 100) {
    throw new Error(`Performance test too slow: ${duration}ms`);
  }
});

// Test: Brace escaping rules - \}} should NOT close template
runner.test('Brace escaping - \\}} does not close template', () => {
  updateTemplateConfig({ variables: {} });

  const input = '{{ code | function() \\}} and more }} end';
  const expected = 'function() }} and more end';
  const actual = parseTemplateVariables(input);
  
  runner.assertEqual(actual, expected, 'Escaped first brace not handled correctly');
});

// Test: Brace escaping rules - }\} should NOT close template
runner.test('Brace escaping - }\\} does not close template', () => {
  updateTemplateConfig({ variables: {} });

  const input = '{{ code | obj}\\} more content }} end';
  const expected = 'obj} more content end';
  const actual = parseTemplateVariables(input);
  
  runner.assertEqual(actual, expected, 'Escaped second brace not handled correctly');
});

// Test: Brace escaping rules - \}\} should NOT close template
runner.test('Brace escaping - \\}\\} does not close template', () => {
  updateTemplateConfig({ variables: {} });

  const input = '{{ code | text\\}\\} more }} end';
  const expected = 'text}} more end';
  const actual = parseTemplateVariables(input);
  
  runner.assertEqual(actual, expected, 'Both escaped braces not handled correctly');
});

// Test: Brace escaping rules - }} SHOULD close template
runner.test('Brace escaping - }} closes template correctly', () => {
  updateTemplateConfig({ variables: {} });

  const input = '{{ code | function() { return; } }} end';
  const expected = 'function() { return; } end';
  const actual = parseTemplateVariables(input);
  
  runner.assertEqual(actual, expected, 'Unescaped closing braces not working');
});

// Test: Multiple escaped braces
runner.test('Multiple escaped braces in sequence', () => {
  updateTemplateConfig({ variables: {} });

  const input = '{{ text | a\\}b\\}c\\}d }} end';
  const expected = 'a}b}c}d end';
  const actual = parseTemplateVariables(input);
  
  runner.assertEqual(actual, expected, 'Multiple escaped braces failed');
});

// Run all tests
runner.run().catch(console.error);