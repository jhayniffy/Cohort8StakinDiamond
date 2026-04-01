// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

library LibAppStorage {
    bytes32 constant APP_STORAGE_POSITION = keccak256("diamond.app.staking.storage");

    struct UserInfo {
        uint256 amount;
        uint256 rewardDebt;
        uint256 pendingRewards;
        uint256 stakeTime;
        uint256 lastClaimTime;
    }

    struct PoolInfo {
        address poolAddress;
        address stakingToken;
        address rewardToken;
        uint256 rewardRate;
        uint256 lockPeriod;
        uint256 penaltyRate;
        bool active;
        uint256 lastUpdateTime;
        uint256 rewardPerTokenStored;
        uint256 totalStaked;
    }

    struct Layout {
        address owner;
        uint256 poolCount;
        mapping(uint256 => PoolInfo) pools;
        mapping(uint256 => mapping(address => UserInfo)) userInfo;
    }

    function layout() internal pure returns (Layout storage l) {
        bytes32 position = APP_STORAGE_POSITION;
        assembly {
            l.slot := position
        }
    }
}
