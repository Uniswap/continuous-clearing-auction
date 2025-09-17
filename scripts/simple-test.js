#!/usr/bin/env node

const SimpleTestRunner = require('../src/SimpleTestRunner');

async function main() {
  console.log('🚀 Simple E2E Test');
  console.log('==================');
  
  const runner = new SimpleTestRunner();
  
  try {
    const result = await runner.runSimpleTest();
    
    if (result.success) {
      console.log('\n✅ All tests passed!');
      process.exit(0);
    } else {
      console.log('\n❌ Test failed!');
      console.log(`Expected: ${result.expected}, Got: ${result.actual}`);
      process.exit(1);
    }
  } catch (error) {
    console.error('\n💥 Test error:', error.message);
    process.exit(1);
  }
}

main();
