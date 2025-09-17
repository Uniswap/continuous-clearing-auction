const { expect } = require('chai');

describe('Simple Test', function() {
  it('should be able to deploy a contract', async function() {
    console.log('🔍 Testing contract deployment...');
    
    try {
      const ERC20Mock = await ethers.getContractFactory('ERC20Mock');
      console.log('🔍 ERC20Mock factory created:', !!ERC20Mock);
      
      const token = await ERC20Mock.deploy('Test', 'TEST', 18, '1000000000000000000000');
      console.log('🔍 Token deployed:', await token.getAddress());
      
      const name = await token.name();
      console.log('🔍 Token name:', name);
      
      expect(name).to.equal('Test');
      console.log('✅ Contract deployment and interaction successful!');
      
    } catch (error) {
      console.log('❌ Error:', error.message);
      throw error;
    }
  });
});
