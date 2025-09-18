#!/bin/bash

# E2E Test Runner Script
# Runs all setup + interaction combinations

set -e  # Exit on any error

echo "🧪 TWAP Auction E2E Test Suite"
echo "================================"

# Check if we're in the right directory
if [ ! -f "package.json" ]; then
    echo "❌ Error: Please run this script from the project root directory"
    exit 1
fi

# Install dependencies if needed
if [ ! -d "node_modules" ]; then
    echo "📦 Installing dependencies..."
    npm install
fi

# Compile contracts
echo "🔨 Compiling contracts..."
npx hardhat compile

# Run the combined tests
echo "🚀 Running E2E tests..."
echo ""

# Run all combined tests
npx hardhat test test/e2e/tests/e2e.test.js

echo ""
echo "✅ E2E tests completed!"

# Optional: Run with verbose output
if [ "$1" = "--verbose" ]; then
    echo ""
    echo "🔍 Running with verbose output..."
    npx hardhat test test/e2e/tests/e2e.test.js --verbose
fi

# Optional: Run specific combination
if [ "$1" = "--setup" ] && [ "$2" ] && [ "$3" = "--interaction" ] && [ "$4" ]; then
    echo ""
    echo "🎯 Running specific combination: $2 + $4"
    npx hardhat test test/e2e/tests/e2e.test.js --grep "Should run $2 \\+ $4 combination"
fi
