// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {AuctionParameters} from '../src/interfaces/IContinuousClearingAuction.sol';
import {IContinuousClearingAuctionFactory} from '../src/interfaces/IContinuousClearingAuctionFactory.sol';
import {AuctionStepsBuilder} from '../test/utils/AuctionStepsBuilder.sol';
import {Script, stdJson} from 'forge-std/Script.sol';
import {console2} from 'forge-std/console2.sol';
import {SafeCastLib} from 'solady/utils/SafeCastLib.sol';

/// @title ExampleScript
/// @notice Example script to generate the parameters for a CCA auction.
/// @dev For illustrative purposes only, please validate the parameters before using them in prod.
contract ExampleScript is Script {
    using stdJson for string;
    using SafeCastLib for uint256;

    struct StepInput {
        uint256 blockDelta;
        uint256 mps;
    }

    function run() public {
        address FACTORY_ADDRESS = vm.envAddress('FACTORY_ADDRESS');
        require(FACTORY_ADDRESS != address(0), 'env.FACTORY_ADDRESS is not set');

        string memory input = vm.readFile('script/example.json');
        string memory chainIdSlug = string(abi.encodePacked('["', vm.toString(block.chainid), '"]'));
        address token = input.readAddress(string.concat(chainIdSlug, '.token'));
        uint128 totalSupply = input.readUint(string.concat(chainIdSlug, '.totalSupply')).toUint128();

        AuctionParameters memory parameters;
        {
            parameters = AuctionParameters({
                currency: input.readAddress(string.concat(chainIdSlug, '.currency')),
                tokensRecipient: input.readAddress(string.concat(chainIdSlug, '.tokensRecipient')),
                fundsRecipient: input.readAddress(string.concat(chainIdSlug, '.fundsRecipient')),
                startBlock: input.readUint(string.concat(chainIdSlug, '.startBlock')).toUint64(),
                endBlock: input.readUint(string.concat(chainIdSlug, '.endBlock')).toUint64(),
                claimBlock: input.readUint(string.concat(chainIdSlug, '.claimBlock')).toUint64(),
                tickSpacing: input.readUint(string.concat(chainIdSlug, '.tickSpacing')),
                validationHook: input.readAddress(string.concat(chainIdSlug, '.validationHook')),
                floorPrice: input.readUint(string.concat(chainIdSlug, '.floorPrice')),
                requiredCurrencyRaised: input.readUint(string.concat(chainIdSlug, '.requiredCurrencyRaised'))
                    .toUint128(),
                auctionStepsData: bytes('')
            });
            bytes memory supplyScheduleRaw = input.parseRaw(string.concat(chainIdSlug, '.supplySchedule'));
            StepInput[] memory supplySchedule = abi.decode(supplyScheduleRaw, (StepInput[]));
            require(supplySchedule.length > 0, 'Supply schedule must have at least 1 step');

            bytes memory auctionStepsData = AuctionStepsBuilder.init();
            for (uint256 i = 0; i < supplySchedule.length; i++) {
                auctionStepsData = AuctionStepsBuilder.addStep(
                    auctionStepsData, supplySchedule[i].mps.toUint24(), supplySchedule[i].blockDelta.toUint40()
                );
            }
            parameters.auctionStepsData = auctionStepsData;
        }

        IContinuousClearingAuctionFactory factory = IContinuousClearingAuctionFactory(FACTORY_ADDRESS);
        bytes memory configData = abi.encode(parameters);
        // By default no salt is used, feel free to change or use a hashed salt to simulate deploying the auction from a strategy
        address auction = address(factory.initializeDistribution(token, totalSupply, configData, bytes32(0)));
        console2.log('Auction deployed to:', auction);
    }
}
