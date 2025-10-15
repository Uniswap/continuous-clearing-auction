import { MultiTestRunner } from "../src/MultiTestRunner";
import { simpleSetup } from "../instances/setup/SimpleSetup";
import { simpleInteraction } from "../instances/interaction/SimpleInteraction";
import { erc20Setup } from "../instances/setup/ERC20Setup";
import { erc20Interaction } from "../instances/interaction/ERC20Interaction";
import { advancedSetup } from "../instances/setup/AdvancedSetup";
import { advancedInteraction } from "../instances/interaction/AdvancedInteraction";
import { variationSetup } from "../instances/setup/VariationSetup";
import { variationInteraction } from "../instances/interaction/VariationInteraction";
import { TestSetupData } from "../schemas/TestSetupSchema";
import { TestInteractionData } from "../schemas/TestInteractionSchema";
import { CombinationResult } from "../src/MultiTestRunner";
import hre from "hardhat";

describe("E2E Tests", function () {
  let runner: MultiTestRunner;
  let results: CombinationResult[] = [];

  before(async function () {
    console.log("🔍 Test: hre.ethers available?", !!hre.ethers);
    runner = new MultiTestRunner();
  });

  it("should run simple setup and interaction", async function () {
    const combinations = [{ setup: simpleSetup, interaction: simpleInteraction }];

    await runTest(combinations);
  });

  it("should run erc20 setup and interaction", async function () {
    const combinations = [{ setup: erc20Setup, interaction: erc20Interaction }];

    await runTest(combinations);
  });

  it("should run advanced setup and interaction", async function () {
    const combinations = [{ setup: advancedSetup, interaction: advancedInteraction }];

    await runTest(combinations);
  });

  it("should run variation setup and interaction (with random amounts and variance assertions)", async function () {
    const combinations = [{ setup: variationSetup, interaction: variationInteraction }];

    await runTest(combinations);
  });

  after(function () {
    printResults();
  });

  async function runTest(combinations: { setup: TestSetupData; interaction: TestInteractionData }[]) {
    console.log("🚀 TWAP Auction E2E Test Runner");
    console.log("================================");

    // Run the specified combinations
    console.log(`\n🎯 Running ${combinations.length} specified combinations...`);
    const _results = await runner.runAllCombinations(combinations);
    results.push(..._results);
    const failed = _results.filter((r) => !r.success).length;
    if (failed > 0) {
      console.log("\n❌ Failed combinations:");
      _results
        .filter((r) => !r.success)
        .forEach((r) => {
          console.log(`   - ${r.setupName} + ${r.interactionName}: ${r.error}`);
        });
      throw new Error(`${failed} test(s) failed`);
    }
  }

  function printResults() {
    // Summary
    const passed = results.filter((r) => r.success).length;
    const failed = results.filter((r) => !r.success).length;
    console.log("\n🏁 Final Summary:");
    console.log(`   Total combinations: ${results.length}`);
    console.log(`   ✅ Passed: ${passed}`);
    console.log(`   ❌ Failed: ${failed}`);

    if (failed > 0) {
      console.log("\n❌ Failed combinations:");
      results
        .filter((r) => !r.success)
        .forEach((r) => {
          console.log(`   - ${r.setupName} + ${r.interactionName}: ${r.error}`);
        });
      throw new Error(`${failed} test(s) failed`);
    } else {
      console.log("\n🎉 All tests passed!");
    }
  }
});
