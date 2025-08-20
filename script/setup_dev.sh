#!/bin/bash
set -e

echo "Setting up development environment..."

# Install dependencies
echo "Installing Foundry dependencies..."
forge build

# Install VS Code extensions if code command is available
if command -v code &> /dev/null; then
    echo "Installing recommended VS Code extensions..."
    code --install-extension NomicFoundation.hardhat-solidity
    code --install-extension JuanBlanco.solidity
    code --install-extension tintinweb.solidity-visual-auditor
fi

# Install solhint if not already installed
if ! command -v solhint &> /dev/null; then
    echo "Installing solhint..."
    npm install -g solhint
fi

echo "Development environment setup complete!"
echo ""
echo "Next steps:"
echo "1. Reload your VS Code/Cursor window"
echo "2. Run 'forge test' to verify everything works"
echo "3. Use Ctrl+Shift+P -> 'Tasks: Run Task' to access Foundry commands"


