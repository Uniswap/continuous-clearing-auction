const { ethers } = require('hardhat');

class SimpleTestRunner {
  constructor() {
    this.testContract = null;
  }

  async deployTestContract() {
    const SimpleTest = await ethers.getContractFactory('SimpleTest');
    this.testContract = await SimpleTest.deploy();
    return this.testContract;
  }

  async runSimpleTest() {
    console.log('🧪 Running simple test...');
    
    // Deploy contract
    await this.deployTestContract();
    console.log('✅ Contract deployed');
    
    // Set a value
    await this.testContract.setValue(42);
    console.log('✅ Value set to 42');
    
    // Get the value
    const value = await this.testContract.getValue();
    console.log(`✅ Value retrieved: ${value}`);
    
    // Verify it's correct
    if (value.toString() === '42') {
      console.log('🎉 Simple test passed!');
      return { success: true, value: value.toString() };
    } else {
      console.log('❌ Simple test failed!');
      return { success: false, expected: '42', actual: value.toString() };
    }
  }
}

module.exports = SimpleTestRunner;
