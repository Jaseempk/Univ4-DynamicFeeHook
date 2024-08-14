//SPDX-License-Identifier:MIT

pragma solidity ^0.8.24;

import {BaseHook} from "v4-periphery/src/base/hooks/BaseHook.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {LPFeeLibrary} from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";

contract DynamicFeeHook is BaseHook {
    error DFH__MustBeDynamicFee();

    // using PoolIdLibrary for PoolKey;
    using LPFeeLibrary for uint24;

    uint104 public movingAveragePriceCount;
    uint128 public movingAveragePrice;
    uint24 public constant BASE_FEE = 5000;

    constructor(IPoolManager _manager) BaseHook(_manager) {
        //updating the moving-avg price during deployment to initialise it
        updateMovingAveragePrice();
    }

    function getHookPermissions()
        public
        pure
        override
        returns (Hooks.Permissions memory)
    {
        return
            Hooks.Permissions({
                beforeInitialize: true,
                afterInitialize: false,
                beforeAddLiquidity: false,
                afterAddLiquidity: false,
                beforeRemoveLiquidity: false,
                afterRemoveLiquidity: false,
                beforeSwap: true,
                afterSwap: true,
                beforeDonate: false,
                afterDonate: false,
                beforeSwapReturnDelta: false,
                afterSwapReturnDelta: false,
                afterAddLiquidityReturnDelta: false,
                afterRemoveLiquidityReturnDelta: false
            });
    }

    function beforeInitialize(
        address,
        PoolKey calldata key,
        uint160,
        bytes calldata
    ) external pure override returns (bytes4) {
        if (!key.fee.isDynamicFee()) revert DFH__MustBeDynamicFee();
        return (this.beforeInitialize.selector);
    }

    function beforeSwap(
        address,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata,
        bytes calldata
    ) external override returns (bytes4, BeforeSwapDelta, uint24) {
        uint24 gaspee = gasFee();
        poolManager.updateDynamicLPFee(key, gaspee);
        return (this.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
    }

    function afterSwap(
        address,
        PoolKey calldata,
        IPoolManager.SwapParams calldata,
        BalanceDelta,
        bytes calldata
    ) external override returns (bytes4, int128) {
        updateMovingAveragePrice();
        return (this.afterSwap.selector, 0);
    }

    function updateMovingAveragePrice() internal {
        uint128 _gasFee = uint128(tx.gasprice);
        movingAveragePrice =
            ((movingAveragePrice * movingAveragePriceCount) + _gasFee) /
            (movingAveragePriceCount + 1);
        movingAveragePriceCount++;
    }

    function gasFee() public view returns (uint24 basfee) {
        uint128 gasPrice = uint128(tx.gasprice);

        //multiplying movingAvgPrice&1.1, just an arbitrary equation
        if (gasPrice > (movingAveragePrice * 11) / 10) {
            return BASE_FEE / 2;
        }
        //multiplying movingAvgPrice&0.9
        if (gasPrice < (movingAveragePrice * 9) / 10) {
            return BASE_FEE * 1;
        }
        return BASE_FEE;
    }
}
