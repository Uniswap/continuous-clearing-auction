// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

type ValueX7 is uint128;

using {add, sub, eq, ne, mul, div, gt, gte, lt, lte} for ValueX7 global;

function add(ValueX7 a, ValueX7 b) pure returns (ValueX7) {
    return ValueX7.wrap(ValueX7.unwrap(a) + ValueX7.unwrap(b));
}

function sub(ValueX7 a, ValueX7 b) pure returns (ValueX7) {
    return ValueX7.wrap(ValueX7.unwrap(a) - ValueX7.unwrap(b));
}

function eq(ValueX7 a, ValueX7 b) pure returns (bool) {
    return ValueX7.unwrap(a) == ValueX7.unwrap(b);
}

function ne(ValueX7 a, ValueX7 b) pure returns (bool) {
    return ValueX7.unwrap(a) != ValueX7.unwrap(b);
}

function gt(ValueX7 a, ValueX7 b) pure returns (bool) {
    return ValueX7.unwrap(a) > ValueX7.unwrap(b);
}

function gte(ValueX7 a, ValueX7 b) pure returns (bool) {
    return ValueX7.unwrap(a) >= ValueX7.unwrap(b);
}

function lt(ValueX7 a, ValueX7 b) pure returns (bool) {
    return ValueX7.unwrap(a) < ValueX7.unwrap(b);
}

function lte(ValueX7 a, ValueX7 b) pure returns (bool) {
    return ValueX7.unwrap(a) <= ValueX7.unwrap(b);
}

function mul(ValueX7 a, uint128 b) pure returns (ValueX7) {
    return ValueX7.wrap(ValueX7.unwrap(a) * b);
}

function div(ValueX7 a, uint128 b) pure returns (ValueX7) {
    return ValueX7.wrap(ValueX7.unwrap(a) / b);
}

library MPSLib {
    using MPSLib for *;

    /// @notice we use milli-bips, or one thousandth of a basis point
    uint24 public constant MPS = 1e7;

    function wrap(uint128 value) internal pure returns (ValueX7) {
        return ValueX7.wrap(value);
    }

    function unwrap(ValueX7 value) internal pure returns (uint128) {
        return ValueX7.unwrap(value);
    }

    function scaleUp(uint128 value) internal pure returns (ValueX7) {
        return ValueX7.wrap(value * MPS);
    }

    function scaleDown(ValueX7 value) internal pure returns (uint128) {
        return ValueX7.unwrap(value) / MPS;
    }

    /// @notice Apply mps to a value
    /// @dev Requires that value is > MPS to avoid loss of precision
    function applyMps(ValueX7 value, uint24 mps) internal pure returns (ValueX7) {
        return value.mul(mps).div(MPS);
    }
}
