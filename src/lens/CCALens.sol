// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {AuctionStateLens} from './AuctionStateLens.sol';
import {TickDataLens} from './TickDataLens.sol';
import {Multicallable} from 'solady/utils/Multicallable.sol';

/// @title CCALens
/// @notice Lens contract for reading data from deployed CCA auctions
contract CCALens is Multicallable, AuctionStateLens, TickDataLens {}
