# MaxBidPriceLib
[Git Source](https://github.com/Uniswap/twap-auction/blob/000be74c9fb6e92005b3e6aff5f612cf221eaa8e/src/libraries/MaxBidPriceLib.sol)

**Title:**
MaxBidPriceLib

Library for calculating the maximum bid price for a given total supply

The two are generally inversely correlated with certain constraints.


## State Variables
### MAX_V4_PRICE
The maximum allowable price for a bid is type(uint160).max

Given a total supply we want to find the maximum bid price such that both the
token liquidity and currency liquidity at the end of the Auction are less than the
maximum liquidity supported by Uniswap v4.
The chart below shows the shaded area of valid (max bid price, total supply) value pairs such that
both calculated liquidity values are less than the maximum liquidity supported by Uniswap v4.
(x axis represents the max bid price in log form, and y is the total supply in log form)
y ↑
|               :                         :   :
|                                            :                                  :
128 +               :                               :
|                                                  :                            :
|               :                                 :   :
|                                                    :                          :
|               :                                       :
|                                                          :                    :
|               :                                         :   : (x=110, y=100)
| : : : : : : : +#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+ : ::: : : : : : : : : : : : : : : : : : : : : : : : : : : : : : : : :
96 +            +############################################   :
|               #################################################  :            :
|               +#################################################+#  :
|               #####################################################+          :
|               +#######################################################:
|               ########################################################## :    :
|               +#########################################################+#  :
|               #############################################################+  :
64 +            +###############################################################: (x=160, y=62)
|               ################################################################:  :
|               +###############################################################  :   :
|               ################################################################:    :
|               +###############################################################        :
|               ################################################################:          :
|               +###############################################################          :   :
|               ################################################################:            :
32 +            +###############################################################                :
|               ################################################################:                  :
|               +###############################################################                  :   :
|               ################################################################:                    :
|               +###############################################################                        :
|               ################################################################:                          :
|               +###############################################################+               +         :   : +
+---------------+###############+###############+###############+###############+---------------+---------------+--------------- x (max price)
0              32              64              96              128             160             192             224           256
Legend:
x = max bid price in log form
y = total supply in log form
L_max = 2^107 (the lowest max liquidity per tick supported in Uniswap v4)
p_sqrtMax = 1461446703485210103287273052203988822378723970342 (max sqrt price in Uniswap v4)
p_sqrtMin = 4295128739 (min sqrt price in Uniswap v4)
x < 160, x > 32; (minimum price of 2^32, maximum price of 2^160)
y < 100; (minimum supply of 2^0 or 1, maximum supply of 2^100)
Equations for liquidity amounts in Uniswap v4:
1) If currencyIsCurrency1, L_0 = (2^y * ((2^((x+96)/2) * 2^160) / 2^96)) / |2^((x+96)/2)-p_sqrtMax| < L_max
2)                         L_1 = (2^(x+y)) / |2^((x+96)/2)-p_sqrtMin| < L_max
3) if currencyIsCurrency0, L_0 = (2^y * p_sqrtMax * 2^((192-x+96)/2)) / (2^(192-x+96) * |p_sqrtMax-2^((192-x+96)/2)|) < L_max
4)                         L_1 = (2^(y+96)) / |2^((192-x+96)/2)-p_sqrtMin| < L_max

This is the maximum price that can be shifted left by 96 bits without overflowing a uint256


```solidity
uint256 constant MAX_V4_PRICE = type(uint160).max
```


### LOWER_TOTAL_SUPPLY_THRESHOLD
The total supply value below which the maximum bid price is capped at MAX_V4_PRICE

Since the two are inversely correlated, generally lower total supply = higher max bid price
However, for very small total supply values we still can't exceed the max v4 price.
This is the intersection of `maxPriceKeepingCurrencyRaisedUnderInt128Max` and MAX_V4_PRICE,
meaning that because we can't support prices above uint160.max, all total supply values at or below
this threshold are capped at MAX_V4_PRICE.


```solidity
uint256 constant LOWER_TOTAL_SUPPLY_THRESHOLD = 1 << 62
```


## Functions
### maxBidPrice

Calculates the maximum bid price for a given total supply

Total supply values under the LOWER_TOTAL_SUPPLY_THRESHOLD are capped at MAX_V4_PRICE


```solidity
function maxBidPrice(uint128 _totalSupply) internal pure returns (uint256);
```

