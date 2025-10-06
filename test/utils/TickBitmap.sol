// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

struct TickBitmap {
    mapping(uint256 => uint256) words;
}

// Modified version of Uniswap v3 TickBitmap.sol
// Allows you to set ticks as initialized and query for the highest tick below a given value.
// https://github.com/Uniswap/v3-core/blob/main/contracts/libraries/TickBitmap.sol
library TickBitmapLib {
    uint256 internal constant WORD_SIZE = 256;

    /// @notice Mark a tick as placed.
    function set(TickBitmap storage self, uint256 tick) internal {
        (uint256 wordPos, uint8 bitPos) = position(tick);
        self.words[wordPos] |= (1 << bitPos);
    }

    /// @notice Check if a tick is placed.
    function isSet(TickBitmap storage self, uint256 tick) internal view returns (bool) {
        (uint256 wordPos, uint8 bitPos) = position(tick);
        return (self.words[wordPos] & (1 << bitPos)) != 0;
    }

    /// @notice Find the greatest tick < input that is placed.
    /// @return prev The tick number, or 0 if none exist.
    function findPrev(TickBitmap storage self, uint256 tick) internal view returns (uint256 prev) {
        if (tick == 0) return 0; // nothing is below 0

        // Look below tick
        tick -= 1;

        (uint256 wordPos, uint8 bitPos) = position(tick);

        // Mask off bits above tick in this word (safe at bitPos=255)
        uint256 mask = type(uint256).max >> (255 - bitPos);
        uint256 masked = self.words[wordPos] & mask;

        if (masked != 0) {
            // highest set bit in masked word
            uint8 msb = _mostSignificantBit(masked);
            return wordPos * WORD_SIZE + uint256(msb);
        }

        // Otherwise, step down word by word
        while (wordPos > 0) {
            wordPos--;
            uint256 word = self.words[wordPos];
            if (word != 0) {
                uint8 msb = _mostSignificantBit(word);
                return wordPos * WORD_SIZE + uint256(msb);
            }
        }

        // No ticks found
        return 0;
    }

    /// @dev Convert tick into (word, bit) position
    function position(uint256 tick) private pure returns (uint256 wordPos, uint8 bitPos) {
        wordPos = tick >> 8; // divide by 256
        bitPos = uint8(tick & 0xFF); // mod 256
    }

    /// @dev Find most significant bit index (0–255) of nonzero word
    function _mostSignificantBit(uint256 x) private pure returns (uint8 r) {
        require(x > 0);
        if (x >> 128 > 0) {
            x >>= 128;
            r += 128;
        }
        if (x >> 64 > 0) {
            x >>= 64;
            r += 64;
        }
        if (x >> 32 > 0) {
            x >>= 32;
            r += 32;
        }
        if (x >> 16 > 0) {
            x >>= 16;
            r += 16;
        }
        if (x >> 8 > 0) {
            x >>= 8;
            r += 8;
        }
        if (x >> 4 > 0) {
            x >>= 4;
            r += 4;
        }
        if (x >> 2 > 0) {
            x >>= 2;
            r += 2;
        }
        if (x >> 1 > 0) r += 1;
    }
}
