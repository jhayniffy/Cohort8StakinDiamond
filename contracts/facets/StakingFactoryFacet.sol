// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {LibAppStorage} from "../libraries/LibAppDiamond.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract StakingFactoryFacet {
    event PoolCreated(uint256 indexed poolId, address stakingToken, address rewardToken, uint256 rewardRate, uint256 lockPeriod, uint256 penaltyRate);
    event PoolDeactivated(uint256 indexed poolId);
    event PoolActivated(uint256 indexed poolId);
    event RewardRateUpdated(uint256 indexed poolId, uint256 oldRate, uint256 newRate);
    event LockPeriodUpdated(uint256 indexed poolId, uint256 oldPeriod, uint256 newPeriod);
    event PenaltyRateUpdated(uint256 indexed poolId, uint256 oldRate, uint256 newRate);

    modifier onlyOwner() {
        require(msg.sender == LibAppStorage.layout().owner, "Not owner");
        _;
    }

    function initFactory() external {
        LibAppStorage.Layout storage l = LibAppStorage.layout();
        require(l.owner == address(0), "Already initialized");
        l.owner = msg.sender;
    }

    function createPool(
        address stakingToken,
        address rewardToken,
        uint256 rewardRate,
        uint256 lockPeriod,
        uint256 penaltyRate
    ) external onlyOwner returns (uint256 poolId) {
        require(stakingToken != address(0), "Invalid staking token");
        require(rewardToken != address(0), "Invalid reward token");
        require(penaltyRate <= 10000, "Penalty rate too high");

        LibAppStorage.Layout storage l = LibAppStorage.layout();
        poolId = l.poolCount;

        l.pools[poolId] = LibAppStorage.PoolInfo({
            poolAddress: address(this),
            stakingToken: stakingToken,
            rewardToken: rewardToken,
            rewardRate: rewardRate,
            lockPeriod: lockPeriod,
            penaltyRate: penaltyRate,
            active: true,
            lastUpdateTime: block.timestamp,
            rewardPerTokenStored: 0,
            totalStaked: 0
        });

        l.poolCount++;

        emit PoolCreated(poolId, stakingToken, rewardToken, rewardRate, lockPeriod, penaltyRate);
    }

    function deactivatePool(uint256 poolId) external onlyOwner {
        LibAppStorage.Layout storage l = LibAppStorage.layout();
        require(poolId < l.poolCount, "Pool does not exist");
        l.pools[poolId].active = false;
        emit PoolDeactivated(poolId);
    }

    function activatePool(uint256 poolId) external onlyOwner {
        LibAppStorage.Layout storage l = LibAppStorage.layout();
        require(poolId < l.poolCount, "Pool does not exist");
        l.pools[poolId].active = true;
        emit PoolActivated(poolId);
    }

    function updatePoolParams(
        uint256 poolId,
        uint256 newRewardRate,
        uint256 newLockPeriod,
        uint256 newPenaltyRate
    ) external onlyOwner {
        LibAppStorage.Layout storage l = LibAppStorage.layout();
        require(poolId < l.poolCount, "Pool does not exist");
        require(newPenaltyRate <= 10000, "Penalty rate too high");

        LibAppStorage.PoolInfo storage pool = l.pools[poolId];

        if (newRewardRate != pool.rewardRate) {
            emit RewardRateUpdated(poolId, pool.rewardRate, newRewardRate);
            pool.rewardRate = newRewardRate;
        }
        if (newLockPeriod != pool.lockPeriod) {
            emit LockPeriodUpdated(poolId, pool.lockPeriod, newLockPeriod);
            pool.lockPeriod = newLockPeriod;
        }
        if (newPenaltyRate != pool.penaltyRate) {
            emit PenaltyRateUpdated(poolId, pool.penaltyRate, newPenaltyRate);
            pool.penaltyRate = newPenaltyRate;
        }
    }

    function fundPool(uint256 poolId, uint256 amount) external onlyOwner {
        LibAppStorage.Layout storage l = LibAppStorage.layout();
        require(poolId < l.poolCount, "Pool does not exist");
        require(
            IERC20(l.pools[poolId].rewardToken).transferFrom(msg.sender, address(this), amount),
            "Transfer failed"
        );
    }

    function getPool(uint256 poolId) external view returns (LibAppStorage.PoolInfo memory) {
        LibAppStorage.Layout storage l = LibAppStorage.layout();
        require(poolId < l.poolCount, "Pool does not exist");
        return l.pools[poolId];
    }

    function getAllPools() external view returns (LibAppStorage.PoolInfo[] memory) {
        LibAppStorage.Layout storage l = LibAppStorage.layout();
        LibAppStorage.PoolInfo[] memory allPools = new LibAppStorage.PoolInfo[](l.poolCount);
        for (uint256 i = 0; i < l.poolCount; i++) {
            allPools[i] = l.pools[i];
        }
        return allPools;
    }

    function poolCount() external view returns (uint256) {
        return LibAppStorage.layout().poolCount;
    }

    function factoryOwner() external view returns (address) {
        return LibAppStorage.layout().owner;
    }
}
