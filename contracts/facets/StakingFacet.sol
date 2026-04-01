// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {LibAppStorage} from "../libraries/LibAppDiamond.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract StakingFacet {
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount, uint256 penalty);
    event RewardsClaimed(address indexed user, uint256 amount);
    event EmergencyWithdrawn(address indexed user, uint256 amount);

    modifier updateReward(uint256 poolId, address account) {
        _updateReward(poolId, account);
        _;
    }

    function stake(uint256 poolId, uint256 amount) external updateReward(poolId, msg.sender) {
        require(amount > 0, "Cannot stake 0");

        LibAppStorage.Layout storage l = LibAppStorage.layout();
        require(poolId < l.poolCount, "Pool does not exist");
        require(l.pools[poolId].active, "Pool is not active");

        LibAppStorage.PoolInfo storage pool = l.pools[poolId];
        LibAppStorage.UserInfo storage user = l.userInfo[poolId][msg.sender];

        require(
            IERC20(pool.stakingToken).transferFrom(msg.sender, address(this), amount),
            "Transfer failed"
        );

        if (user.amount > 0) {
            user.pendingRewards += user.amount * (pool.rewardPerTokenStored - user.rewardDebt) / 1e18;
        }

        user.amount += amount;
        user.stakeTime = block.timestamp;
        user.rewardDebt = pool.rewardPerTokenStored;
        pool.totalStaked += amount;

        emit Staked(msg.sender, amount);
    }

    function withdraw(uint256 poolId, uint256 amount) external updateReward(poolId, msg.sender) {
        LibAppStorage.Layout storage l = LibAppStorage.layout();
        require(poolId < l.poolCount, "Pool does not exist");

        LibAppStorage.PoolInfo storage pool = l.pools[poolId];
        LibAppStorage.UserInfo storage user = l.userInfo[poolId][msg.sender];

        require(user.amount >= amount, "Insufficient staked balance");
        require(amount > 0, "Cannot withdraw 0");

        uint256 penalty = 0;
        if (block.timestamp < user.stakeTime + pool.lockPeriod) {
            penalty = amount * pool.penaltyRate / 10000;
        }

        uint256 withdrawAmount = amount - penalty;

        user.amount -= amount;
        user.rewardDebt = pool.rewardPerTokenStored;
        pool.totalStaked -= amount;

        require(IERC20(pool.stakingToken).transfer(msg.sender, withdrawAmount), "Transfer failed");

        emit Withdrawn(msg.sender, withdrawAmount, penalty);
    }

    function claimRewards(uint256 poolId) external updateReward(poolId, msg.sender) {
        LibAppStorage.Layout storage l = LibAppStorage.layout();
        require(poolId < l.poolCount, "Pool does not exist");

        LibAppStorage.PoolInfo storage pool = l.pools[poolId];
        LibAppStorage.UserInfo storage user = l.userInfo[poolId][msg.sender];

        uint256 pending = earned(poolId, msg.sender);
        require(pending > 0, "No rewards to claim");

        user.pendingRewards = 0;
        user.lastClaimTime = block.timestamp;
        user.rewardDebt = pool.rewardPerTokenStored;

        require(IERC20(pool.rewardToken).transfer(msg.sender, pending), "Reward transfer failed");

        emit RewardsClaimed(msg.sender, pending);
    }

    function emergencyWithdraw(uint256 poolId) external {
        LibAppStorage.Layout storage l = LibAppStorage.layout();
        require(poolId < l.poolCount, "Pool does not exist");

        LibAppStorage.PoolInfo storage pool = l.pools[poolId];
        LibAppStorage.UserInfo storage user = l.userInfo[poolId][msg.sender];

        uint256 amount = user.amount;
        require(amount > 0, "No stake to withdraw");

        uint256 penalty = 0;
        if (block.timestamp < user.stakeTime + pool.lockPeriod) {
            penalty = amount * pool.penaltyRate / 10000;
        }

        uint256 withdrawAmount = amount - penalty;

        user.amount = 0;
        user.pendingRewards = 0;
        user.rewardDebt = pool.rewardPerTokenStored;
        pool.totalStaked -= amount;

        require(IERC20(pool.stakingToken).transfer(msg.sender, withdrawAmount), "Transfer failed");

        emit EmergencyWithdrawn(msg.sender, withdrawAmount);
    }

    function earned(uint256 poolId, address account) public view returns (uint256) {
        LibAppStorage.Layout storage l = LibAppStorage.layout();
        LibAppStorage.UserInfo storage user = l.userInfo[poolId][account];
        return user.pendingRewards + (user.amount * (rewardPerToken(poolId) - user.rewardDebt) / 1e18);
    }

    function rewardPerToken(uint256 poolId) public view returns (uint256) {
        LibAppStorage.Layout storage l = LibAppStorage.layout();
        LibAppStorage.PoolInfo storage pool = l.pools[poolId];

        if (pool.totalStaked == 0) return pool.rewardPerTokenStored;

        return pool.rewardPerTokenStored + (
            (block.timestamp - pool.lastUpdateTime) * pool.rewardRate * 1e18 / pool.totalStaked
        );
    }

    function getUserInfo(uint256 poolId, address user) external view returns (
        uint256 amount,
        uint256 pendingRewards,
        uint256 stakeTime,
        uint256 lastClaimTime,
        uint256 availableRewards
    ) {
        LibAppStorage.Layout storage l = LibAppStorage.layout();
        LibAppStorage.UserInfo storage info = l.userInfo[poolId][user];
        return (info.amount, info.pendingRewards, info.stakeTime, info.lastClaimTime, earned(poolId, user));
    }

    function canWithdrawWithoutPenalty(uint256 poolId, address user) external view returns (bool) {
        LibAppStorage.Layout storage l = LibAppStorage.layout();
        return block.timestamp >= l.userInfo[poolId][user].stakeTime + l.pools[poolId].lockPeriod;
    }

    function timeUntilUnlock(uint256 poolId, address user) external view returns (uint256) {
        LibAppStorage.Layout storage l = LibAppStorage.layout();
        LibAppStorage.UserInfo storage info = l.userInfo[poolId][user];
        LibAppStorage.PoolInfo storage pool = l.pools[poolId];
        if (block.timestamp >= info.stakeTime + pool.lockPeriod) return 0;
        return (info.stakeTime + pool.lockPeriod) - block.timestamp;
    }

    function _updateReward(uint256 poolId, address account) internal {
        LibAppStorage.Layout storage l = LibAppStorage.layout();
        if (poolId >= l.poolCount) return;

        LibAppStorage.PoolInfo storage pool = l.pools[poolId];
        pool.rewardPerTokenStored = rewardPerToken(poolId);
        pool.lastUpdateTime = block.timestamp;

        if (account != address(0)) {
            LibAppStorage.UserInfo storage user = l.userInfo[poolId][account];
            user.pendingRewards = earned(poolId, account);
            user.rewardDebt = pool.rewardPerTokenStored;
        }
    }
}
