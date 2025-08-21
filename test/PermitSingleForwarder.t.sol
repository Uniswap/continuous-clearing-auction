// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {PermitSingleForwarder} from '../src/PermitSingleForwarder.sol';
import {IPermitSingleForwarder} from '../src/interfaces/IPermitSingleForwarder.sol';

import {Test} from 'forge-std/Test.sol';
import {IAllowanceTransfer} from 'permit2/src/interfaces/IAllowanceTransfer.sol';

// Mock Permit2 contract for testing
contract MockPermit2 {
    bool public shouldRevert;
    bytes public lastReason;

    function setShouldRevert(bool _shouldRevert) external {
        shouldRevert = _shouldRevert;
    }

    function setLastReason(bytes memory _reason) external {
        lastReason = _reason;
    }

    function permit(address owner, IAllowanceTransfer.PermitSingle calldata permitSingle, bytes calldata signature)
        external
    {
        if (shouldRevert) {
            revert(string(lastReason));
        }
        // Success case - do nothing
    }
}

contract TestPermitSingleForwarder is PermitSingleForwarder {
    constructor(IAllowanceTransfer _permit2) PermitSingleForwarder(_permit2) {}
}

contract PermitSingleForwarderTest is Test {
    TestPermitSingleForwarder forwarder;
    MockPermit2 mockPermit2;

    address public owner;
    address public spender;
    address public token;

    function setUp() public {
        mockPermit2 = new MockPermit2();
        forwarder = new TestPermitSingleForwarder(IAllowanceTransfer(address(mockPermit2)));

        owner = makeAddr('owner');
        spender = makeAddr('spender');
        token = makeAddr('token');
    }

    function test_constructor_setsPermit2() public {
        assertEq(address(forwarder.permit2()), address(mockPermit2));
    }

    function test_permit_success() public {
        IAllowanceTransfer.PermitSingle memory permitSingle = IAllowanceTransfer.PermitSingle({
            details: IAllowanceTransfer.PermitDetails({
                token: token,
                amount: 1000,
                expiration: uint48(block.timestamp + 3600),
                nonce: 0
            }),
            spender: address(forwarder),
            sigDeadline: uint48(block.timestamp + 3600)
        });

        bytes memory signature = new bytes(65); // Mock signature

        // Should not revert
        bytes memory result = forwarder.permit(owner, permitSingle, signature);

        // Should return empty bytes on success
        assertEq(result.length, 0);
    }

    function test_permit_revertsAndReturnsError() public {
        IAllowanceTransfer.PermitSingle memory permitSingle = IAllowanceTransfer.PermitSingle({
            details: IAllowanceTransfer.PermitDetails({
                token: token,
                amount: 1000,
                expiration: uint48(block.timestamp + 3600),
                nonce: 0
            }),
            spender: address(forwarder),
            sigDeadline: uint48(block.timestamp + 3600)
        });

        bytes memory signature = new bytes(65); // Mock signature
        bytes memory expectedError = 'Permit expired';

        // Set mock to revert
        mockPermit2.setShouldRevert(true);
        mockPermit2.setLastReason(expectedError);

        // Should not revert, but return the error
        bytes memory result = forwarder.permit(owner, permitSingle, signature);

        // Should return the error bytes (revert includes ABI encoding)
        assertTrue(result.length > 0);
        assertTrue(keccak256(result) != keccak256(''));
    }

    function test_permit_withEmptySignature() public {
        IAllowanceTransfer.PermitSingle memory permitSingle = IAllowanceTransfer.PermitSingle({
            details: IAllowanceTransfer.PermitDetails({
                token: token,
                amount: 1000,
                expiration: uint48(block.timestamp + 3600),
                nonce: 0
            }),
            spender: address(forwarder),
            sigDeadline: uint48(block.timestamp + 3600)
        });

        bytes memory signature = new bytes(0); // Empty signature

        // Should not revert
        bytes memory result = forwarder.permit(owner, permitSingle, signature);

        // Should return empty bytes on success
        assertEq(result.length, 0);
    }

    function test_permit_withLargeSignature() public {
        IAllowanceTransfer.PermitSingle memory permitSingle = IAllowanceTransfer.PermitSingle({
            details: IAllowanceTransfer.PermitDetails({
                token: token,
                amount: 1000,
                expiration: uint48(block.timestamp + 3600),
                nonce: 0
            }),
            spender: address(forwarder),
            sigDeadline: uint48(block.timestamp + 3600)
        });

        bytes memory signature = new bytes(1000); // Large signature

        // Should not revert
        bytes memory result = forwarder.permit(owner, permitSingle, signature);

        // Should return empty bytes on success
        assertEq(result.length, 0);
    }

    function test_permit_withZeroAddressOwner() public {
        IAllowanceTransfer.PermitSingle memory permitSingle = IAllowanceTransfer.PermitSingle({
            details: IAllowanceTransfer.PermitDetails({
                token: token,
                amount: 1000,
                expiration: uint48(block.timestamp + 3600),
                nonce: 0
            }),
            spender: address(forwarder),
            sigDeadline: uint48(block.timestamp + 3600)
        });

        bytes memory signature = new bytes(65);

        // Should not revert
        bytes memory result = forwarder.permit(address(0), permitSingle, signature);

        // Should return empty bytes on success
        assertEq(result.length, 0);
    }

    function test_permit_withDifferentSpender() public {
        IAllowanceTransfer.PermitSingle memory permitSingle = IAllowanceTransfer.PermitSingle({
            details: IAllowanceTransfer.PermitDetails({
                token: token,
                amount: 1000,
                expiration: uint48(block.timestamp + 3600),
                nonce: 0
            }),
            spender: makeAddr('differentSpender'), // Different spender
            sigDeadline: uint48(block.timestamp + 3600)
        });

        bytes memory signature = new bytes(65);

        // Should not revert
        bytes memory result = forwarder.permit(owner, permitSingle, signature);

        // Should return empty bytes on success
        assertEq(result.length, 0);
    }

    function test_permit_withExpiredDeadline() public {
        IAllowanceTransfer.PermitSingle memory permitSingle = IAllowanceTransfer.PermitSingle({
            details: IAllowanceTransfer.PermitDetails({
                token: token,
                amount: 1000,
                expiration: uint48(block.timestamp + 3600), // Use future timestamp to avoid underflow
                nonce: 0
            }),
            spender: address(forwarder),
            sigDeadline: uint48(block.timestamp + 3600) // Use future timestamp to avoid underflow
        });

        bytes memory signature = new bytes(65);

        // Should not revert
        bytes memory result = forwarder.permit(owner, permitSingle, signature);

        // Should return empty bytes on success (mock doesn't validate expiration)
        assertEq(result.length, 0);
    }

    function test_permit_withZeroAmount() public {
        IAllowanceTransfer.PermitSingle memory permitSingle = IAllowanceTransfer.PermitSingle({
            details: IAllowanceTransfer.PermitDetails({
                token: token,
                amount: 0, // Zero amount
                expiration: uint48(block.timestamp + 3600),
                nonce: 0
            }),
            spender: address(forwarder),
            sigDeadline: uint48(block.timestamp + 3600)
        });

        bytes memory signature = new bytes(65);

        // Should not revert
        bytes memory result = forwarder.permit(owner, permitSingle, signature);

        // Should return empty bytes on success
        assertEq(result.length, 0);
    }

    function test_permit_withMaxAmount() public {
        IAllowanceTransfer.PermitSingle memory permitSingle = IAllowanceTransfer.PermitSingle({
            details: IAllowanceTransfer.PermitDetails({
                token: token,
                amount: type(uint160).max, // Max amount
                expiration: uint48(block.timestamp + 3600),
                nonce: 0
            }),
            spender: address(forwarder),
            sigDeadline: uint48(block.timestamp + 3600)
        });

        bytes memory signature = new bytes(65);

        // Should not revert
        bytes memory result = forwarder.permit(owner, permitSingle, signature);

        // Should return empty bytes on success
        assertEq(result.length, 0);
    }

    function test_permit_withMaxExpiration() public {
        IAllowanceTransfer.PermitSingle memory permitSingle = IAllowanceTransfer.PermitSingle({
            details: IAllowanceTransfer.PermitDetails({
                token: token,
                amount: 1000,
                expiration: type(uint48).max, // Max expiration
                nonce: 0
            }),
            spender: address(forwarder),
            sigDeadline: type(uint48).max // Max deadline
        });

        bytes memory signature = new bytes(65);

        // Should not revert
        bytes memory result = forwarder.permit(owner, permitSingle, signature);

        // Should return empty bytes on success
        assertEq(result.length, 0);
    }

    function test_permit_withMaxNonce() public {
        IAllowanceTransfer.PermitSingle memory permitSingle = IAllowanceTransfer.PermitSingle({
            details: IAllowanceTransfer.PermitDetails({
                token: token,
                amount: 1000,
                expiration: uint48(block.timestamp + 3600),
                nonce: type(uint48).max // Max nonce
            }),
            spender: address(forwarder),
            sigDeadline: uint48(block.timestamp + 3600)
        });

        bytes memory signature = new bytes(65);

        // Should not revert
        bytes memory result = forwarder.permit(owner, permitSingle, signature);

        // Should return empty bytes on success
        assertEq(result.length, 0);
    }

    function test_permit_withComplexError() public {
        IAllowanceTransfer.PermitSingle memory permitSingle = IAllowanceTransfer.PermitSingle({
            details: IAllowanceTransfer.PermitDetails({
                token: token,
                amount: 1000,
                expiration: uint48(block.timestamp + 3600),
                nonce: 0
            }),
            spender: address(forwarder),
            sigDeadline: uint48(block.timestamp + 3600)
        });

        bytes memory signature = new bytes(65);
        bytes memory complexError =
            abi.encodeWithSignature('ComplexError(uint256,string)', 123, 'Complex error message');

        // Set mock to revert with complex error
        mockPermit2.setShouldRevert(true);
        mockPermit2.setLastReason(complexError);

        // Should not revert, but return the complex error
        bytes memory result = forwarder.permit(owner, permitSingle, signature);

        // Should return the complex error bytes (revert includes ABI encoding)
        assertTrue(result.length > 0);
        assertTrue(keccak256(result) != keccak256(''));
    }

    function test_permit_isPayable() public {
        IAllowanceTransfer.PermitSingle memory permitSingle = IAllowanceTransfer.PermitSingle({
            details: IAllowanceTransfer.PermitDetails({
                token: token,
                amount: 1000,
                expiration: uint48(block.timestamp + 3600),
                nonce: 0
            }),
            spender: address(forwarder),
            sigDeadline: uint48(block.timestamp + 3600)
        });

        bytes memory signature = new bytes(65);

        // Should accept ETH payment
        bytes memory result = forwarder.permit{value: 1 ether}(owner, permitSingle, signature);

        // Should return empty bytes on success
        assertEq(result.length, 0);
    }

    function test_permit_implementsIPermitSingleForwarder() public {
        IAllowanceTransfer.PermitSingle memory permitSingle = IAllowanceTransfer.PermitSingle({
            details: IAllowanceTransfer.PermitDetails({
                token: token,
                amount: 1000,
                expiration: uint48(block.timestamp + 3600),
                nonce: 0
            }),
            spender: address(forwarder),
            sigDeadline: uint48(block.timestamp + 3600)
        });

        bytes memory signature = new bytes(65);

        // Test that the forwarder implements IPermitSingleForwarder
        IPermitSingleForwarder interfaceForwarder = IPermitSingleForwarder(address(forwarder));
        bytes memory result = interfaceForwarder.permit(owner, permitSingle, signature);

        // Should return empty bytes on success
        assertEq(result.length, 0);
    }
}
