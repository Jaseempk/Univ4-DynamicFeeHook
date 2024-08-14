//SPDX-License-Identifier:MIT

pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Deployers} from "@uniswap/v4-core/test/utils/Deployers.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {MockERC20} from "@uniswap/v4-core/lib/forge-gas-snapshot/lib/forge-std/src/mocks/MockERC20.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {LPFeeLibrary} from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";
import {PoolSwapTest} from "@uniswap/v4-core/src/test/PoolSwapTest.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {PoolManager} from "@uniswap/v4-core/src/PoolManager.sol";
import {console} from "forge-std/console.sol";

import {DynamicFeeHook} from "src/DynamicFeeHook.sol";

contract DynamicFeeHookTest is Test, Deployers {
    using CurrencyLibrary for Currency;
    using PoolIdLibrary for PoolKey;

    DynamicFeeHook feeHook;
    Currency token0;
    Currency token1;
    uint24 fee = 3000;
    int24 tickLower = -60;
    int24 tickUpper = 60;
    int256 liquidityDelta = 100 ether;
    int256 amountSpcfd = 0.00001 ether;

    function setUp() public {
        deployFreshManagerAndRouters();
        (token0, token1) = deployMintAndApprove2Currencies();
        uint160 flags = uint160(
            Hooks.BEFORE_INITIALIZE_FLAG |
                Hooks.BEFORE_SWAP_FLAG |
                Hooks.AFTER_SWAP_FLAG
        );
        address dynamicFeeHookAddress = address(flags);
        vm.txGasPrice(10 gwei); //to set the movingAveragePrice while deploying
        deployCodeTo(
            "DynamicFeeHook.sol",
            abi.encode(manager),
            dynamicFeeHookAddress
        );
        feeHook = DynamicFeeHook(dynamicFeeHookAddress);

        MockERC20(Currency.unwrap(token0)).approve(
            address(feeHook),
            type(uint256).max
        );
        MockERC20(Currency.unwrap(token1)).approve(
            address(feeHook),
            type(uint256).max
        );

        (key, ) = initPool(
            token0,
            token1,
            feeHook,
            LPFeeLibrary.DYNAMIC_FEE_FLAG,
            SQRT_PRICE_1_1,
            ZERO_BYTES
        );

        modifyLiquidityRouter.modifyLiquidity(
            key,
            IPoolManager.ModifyLiquidityParams({
                tickLower: tickLower,
                tickUpper: tickUpper,
                liquidityDelta: liquidityDelta,
                salt: bytes32(0)
            }),
            ZERO_BYTES
        );
    }

    function test_baseFeeFluctuations_basedOnGasPrice() public {
        PoolSwapTest.TestSettings memory test = PoolSwapTest.TestSettings({
            takeClaims: false,
            settleUsingBurn: false
        });
        uint24 baseFeeBefore = feeHook.gasFee();
        console.log("base-fee_after:", baseFeeBefore);
        vm.txGasPrice(20 gwei);
        swapRouter.swap(
            key,
            IPoolManager.SwapParams({
                zeroForOne: true,
                amountSpecified: -amountSpcfd,
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            }),
            test,
            ZERO_BYTES
        );
        uint24 basFeeAfter = feeHook.gasFee();
        console.log("base-fee-after:", basFeeAfter);

        vm.txGasPrice(3 gwei);
        swapRouter.swap(
            key,
            IPoolManager.SwapParams({
                zeroForOne: true,
                amountSpecified: -amountSpcfd,
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            }),
            test,
            ZERO_BYTES
        );
        console.log(feeHook.movingAveragePriceCount());
    }
}
