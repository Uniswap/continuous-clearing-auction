const CombinedTestRunner = require('./CombinedTestRunner');

class TestCombinationRunner {
  constructor(hre, ethers) {
    this.hre = hre;
    this.ethers = ethers;
    this.combinedRunner = new CombinedTestRunner(hre, ethers);
  }

  /**
   * Run a specific setup + interaction combination
   * @param {string} setupFile - Setup JSON filename
   * @param {string} interactionFile - Interaction JSON filename
   * @returns {Object} Test result
   */
  async runCombination(setupFile, interactionFile) {
    console.log(`\n🎯 Running combination: ${setupFile} + ${interactionFile}`);
    
    try {
      const result = await this.combinedRunner.runCombinedTest(setupFile, interactionFile);
      console.log(`✅ ${setupFile} + ${interactionFile} - PASSED`);
      return { success: true, result, setupFile, interactionFile };
    } catch (error) {
      console.error(`❌ ${setupFile} + ${interactionFile} - FAILED`);
      console.error(`   Error: ${error.message}`);
      return { success: false, error: error.message, setupFile, interactionFile };
    }
  }

  /**
   * Run all predefined combinations
   * @param {Array} combinations - Array of {setup, interaction} objects
   * @returns {Array} Results array
   */
  async runAllCombinations(combinations) {
    console.log(`\n🧪 Running ${combinations.length} test combinations...`);
    
    const results = [];
    let passed = 0;
    let failed = 0;

    for (const combo of combinations) {
      const result = await this.runCombination(combo.setup, combo.interaction);
      results.push(result);
      
      if (result.success) {
        passed++;
      } else {
        failed++;
      }
    }

    console.log(`\n📊 Test Results:`);
    console.log(`   ✅ Passed: ${passed}`);
    console.log(`   ❌ Failed: ${failed}`);
    console.log(`   📈 Success Rate: ${((passed / combinations.length) * 100).toFixed(1)}%`);

    return results;
  }

  /**
   * Get all available setup and interaction files
   * @returns {Object} Available files
   */
  getAvailableFiles() {
    const setupFiles = this.combinedRunner.testRunner.getAllTestInstances('setup');
    const interactionFiles = this.combinedRunner.testRunner.getAllTestInstances('interaction');
    
    return {
      setup: setupFiles.map(f => f.filename),
      interaction: interactionFiles.map(f => f.filename)
    };
  }

  /**
   * Generate all possible combinations of setup + interaction files
   * @returns {Array} All possible combinations
   */
  generateAllCombinations() {
    const files = this.getAvailableFiles();
    const combinations = [];
    
    for (const setup of files.setup) {
      for (const interaction of files.interaction) {
        combinations.push({ setup, interaction });
      }
    }
    
    return combinations;
  }

  /**
   * Run all possible combinations
   * @returns {Array} Results array
   */
  async runAllPossibleCombinations() {
    const combinations = this.generateAllCombinations();
    return await this.runAllCombinations(combinations);
  }
}

module.exports = TestCombinationRunner;
