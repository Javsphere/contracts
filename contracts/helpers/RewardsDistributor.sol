// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

contract RewardsDistributor {
    constructor() {}

    //    function _distributeRewards() private {
    //        uint256 _amount = IERC20(javAddress).balanceOf(address(this));
    //        uint256 _burnAmount = (_amount * burnPercent) / 100;
    //        uint256 _rewardsAmount = _amount - _burnAmount;
    //
    //        //1. Burn jav tokens
    //        IERC20Extended(javAddress).burn(_burnAmount);
    //
    //        //2. freezer rewards
    //        uint256 _freezerRewards = (_rewardsAmount * freezerPercent) / 100;
    //        IERC20(javAddress).transfer(freezerAddress, _freezerRewards);
    //
    //        //3. staking rewards
    //        uint256 _stakingRewards = _rewardsAmount - _freezerRewards;
    //        IERC20(javAddress).transfer(stakingAddress, _stakingRewards);
    //        IJavStaking(stakingAddress).updateRewards(0, _stakingRewards);
    //
    //        emit DistributeRewards(_amount);
    //    }

    //    function _swapToken(
    //        address _tokenIn,
    //        address _tokenOut,
    //        uint256 _amount,
    //        uint24 _poolFee
    //    ) private {
    //        IERC20(_tokenIn).safeDecreaseAllowance(address(swapRouter), 0);
    //        IERC20(_tokenIn).safeIncreaseAllowance(address(swapRouter), _amount);
    //
    //        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
    //            tokenIn: _tokenIn,
    //            tokenOut: _tokenOut,
    //            fee: _poolFee,
    //            recipient: address(this),
    //            deadline: block.timestamp,
    //            amountIn: _amount,
    //            amountOutMinimum: 0,
    //            sqrtPriceLimitX96: 0
    //        });
    //        swapRouter.exactInputSingle(params);
    //    }
}
