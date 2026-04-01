// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../contracts/Diamond.sol";
import "../contracts/facets/DiamondCutFacet.sol";
import "../contracts/facets/DiamondLoupeFacet.sol";
import "../contracts/facets/OwnershipFacet.sol";
import "../contracts/facets/StakingFacet.sol";
import "../contracts/facets/StakingFactoryFacet.sol";
import "../contracts/interfaces/IDiamondCut.sol";
import "../contracts/libraries/LibAppDiamond.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract StakingDiamondTest is Test, IDiamondCut {
    Diamond diamond;
    DiamondCutFacet dCutFacet;
    DiamondLoupeFacet dLoupe;
    OwnershipFacet ownerFacet;
    StakingFacet stakingFacet;
    StakingFactoryFacet factoryFacet;

    MockERC20 stakingToken;
    MockERC20 rewardToken;

    address alice = address(0xA1);
    address bob   = address(0xB0);

    uint256 constant REWARD_RATE  = 1e15;
    uint256 constant LOCK_PERIOD  = 7 days;
    uint256 constant PENALTY_RATE = 1000;
    uint256 constant STAKE_AMOUNT = 100e18;
    uint256 constant FUND_AMOUNT  = 1000e18;

    uint256 poolId;

    function setUp() public {
        dCutFacet    = new DiamondCutFacet();
        dLoupe       = new DiamondLoupeFacet();
        ownerFacet   = new OwnershipFacet();
        stakingFacet = new StakingFacet();
        factoryFacet = new StakingFactoryFacet();

        diamond = new Diamond(address(this), address(dCutFacet));

        FacetCut[] memory cut = new FacetCut[](4);
        cut[0] = FacetCut({ facetAddress: address(dLoupe),       action: FacetCutAction.Add, functionSelectors: generateSelectors("DiamondLoupeFacet")    });
        cut[1] = FacetCut({ facetAddress: address(ownerFacet),   action: FacetCutAction.Add, functionSelectors: generateSelectors("OwnershipFacet")        });
        cut[2] = FacetCut({ facetAddress: address(stakingFacet), action: FacetCutAction.Add, functionSelectors: generateSelectors("StakingFacet")          });
        cut[3] = FacetCut({ facetAddress: address(factoryFacet), action: FacetCutAction.Add, functionSelectors: generateSelectors("StakingFactoryFacet")   });

        IDiamondCut(address(diamond)).diamondCut(cut, address(0), "");

        StakingFactoryFacet(address(diamond)).initFactory();

        stakingToken = new MockERC20("Staking Token", "STK");
        rewardToken  = new MockERC20("Reward Token",  "RWD");

        poolId = StakingFactoryFacet(address(diamond)).createPool(
            address(stakingToken), address(rewardToken), REWARD_RATE, LOCK_PERIOD, PENALTY_RATE
        );

        rewardToken.mint(address(this), FUND_AMOUNT);
        rewardToken.approve(address(diamond), FUND_AMOUNT);
        StakingFactoryFacet(address(diamond)).fundPool(poolId, FUND_AMOUNT);

        stakingToken.mint(alice, STAKE_AMOUNT * 2);
        stakingToken.mint(bob,   STAKE_AMOUNT);
    }

    function test_DiamondSetup() public view {
        address[] memory facetAddrs = DiamondLoupeFacet(address(diamond)).facetAddresses();
        assertEq(facetAddrs.length, 5);
    }

    function test_PoolCreated() public view {
        LibAppStorage.PoolInfo memory pool = StakingFactoryFacet(address(diamond)).getPool(poolId);
        assertEq(pool.stakingToken, address(stakingToken));
        assertEq(pool.rewardToken,  address(rewardToken));
        assertEq(pool.rewardRate,   REWARD_RATE);
        assertEq(pool.lockPeriod,   LOCK_PERIOD);
        assertEq(pool.penaltyRate,  PENALTY_RATE);
        assertTrue(pool.active);
    }

    function test_Stake() public {
        vm.startPrank(alice);
        stakingToken.approve(address(diamond), STAKE_AMOUNT);
        StakingFacet(address(diamond)).stake(poolId, STAKE_AMOUNT);
        vm.stopPrank();

        (uint256 amount,,,,) = StakingFacet(address(diamond)).getUserInfo(poolId, alice);
        assertEq(amount, STAKE_AMOUNT);

        LibAppStorage.PoolInfo memory pool = StakingFactoryFacet(address(diamond)).getPool(poolId);
        assertEq(pool.totalStaked, STAKE_AMOUNT);
    }

    function test_EarnRewards() public {
        vm.startPrank(alice);
        stakingToken.approve(address(diamond), STAKE_AMOUNT);
        StakingFacet(address(diamond)).stake(poolId, STAKE_AMOUNT);
        vm.stopPrank();

        vm.warp(block.timestamp + 1 days);

        uint256 rewards = StakingFacet(address(diamond)).earned(poolId, alice);
        assertGt(rewards, 0);
    }

    function test_ClaimRewards() public {
        vm.startPrank(alice);
        stakingToken.approve(address(diamond), STAKE_AMOUNT);
        StakingFacet(address(diamond)).stake(poolId, STAKE_AMOUNT);
        vm.stopPrank();

        vm.warp(block.timestamp + 1 days);

        uint256 balanceBefore = rewardToken.balanceOf(alice);

        vm.prank(alice);
        StakingFacet(address(diamond)).claimRewards(poolId);

        assertGt(rewardToken.balanceOf(alice), balanceBefore);
    }

    function test_WithdrawAfterLock() public {
        vm.startPrank(alice);
        stakingToken.approve(address(diamond), STAKE_AMOUNT);
        StakingFacet(address(diamond)).stake(poolId, STAKE_AMOUNT);
        vm.stopPrank();

        vm.warp(block.timestamp + LOCK_PERIOD + 1);

        uint256 balanceBefore = stakingToken.balanceOf(alice);

        vm.prank(alice);
        StakingFacet(address(diamond)).withdraw(poolId, STAKE_AMOUNT);

        assertEq(stakingToken.balanceOf(alice) - balanceBefore, STAKE_AMOUNT);
    }

    function test_WithdrawBeforeLock_Penalty() public {
        vm.startPrank(alice);
        stakingToken.approve(address(diamond), STAKE_AMOUNT);
        StakingFacet(address(diamond)).stake(poolId, STAKE_AMOUNT);
        vm.stopPrank();

        vm.warp(block.timestamp + 1 days);

        uint256 balanceBefore = stakingToken.balanceOf(alice);

        vm.prank(alice);
        StakingFacet(address(diamond)).withdraw(poolId, STAKE_AMOUNT);

        uint256 received = stakingToken.balanceOf(alice) - balanceBefore;
        uint256 expectedReceived = STAKE_AMOUNT - (STAKE_AMOUNT * PENALTY_RATE / 10000);
        assertEq(received, expectedReceived);
    }

    function test_EmergencyWithdraw() public {
        vm.startPrank(alice);
        stakingToken.approve(address(diamond), STAKE_AMOUNT);
        StakingFacet(address(diamond)).stake(poolId, STAKE_AMOUNT);
        vm.stopPrank();

        vm.warp(block.timestamp + 1 days);

        uint256 balanceBefore = stakingToken.balanceOf(alice);

        vm.prank(alice);
        StakingFacet(address(diamond)).emergencyWithdraw(poolId);

        assertGt(stakingToken.balanceOf(alice), balanceBefore);

        (uint256 amount,,,,) = StakingFacet(address(diamond)).getUserInfo(poolId, alice);
        assertEq(amount, 0);
    }

    function test_CanWithdrawWithoutPenalty() public {
        vm.startPrank(alice);
        stakingToken.approve(address(diamond), STAKE_AMOUNT);
        StakingFacet(address(diamond)).stake(poolId, STAKE_AMOUNT);
        vm.stopPrank();

        assertFalse(StakingFacet(address(diamond)).canWithdrawWithoutPenalty(poolId, alice));

        vm.warp(block.timestamp + LOCK_PERIOD + 1);
        assertTrue(StakingFacet(address(diamond)).canWithdrawWithoutPenalty(poolId, alice));
    }

    function test_UpdatePoolParams() public {
        StakingFactoryFacet(address(diamond)).updatePoolParams(poolId, 2e15, 14 days, 500);

        LibAppStorage.PoolInfo memory pool = StakingFactoryFacet(address(diamond)).getPool(poolId);
        assertEq(pool.rewardRate,  2e15);
        assertEq(pool.lockPeriod,  14 days);
        assertEq(pool.penaltyRate, 500);
    }

    function test_DeactivateAndActivatePool() public {
        StakingFactoryFacet(address(diamond)).deactivatePool(poolId);
        assertFalse(StakingFactoryFacet(address(diamond)).getPool(poolId).active);

        vm.startPrank(alice);
        stakingToken.approve(address(diamond), STAKE_AMOUNT);
        vm.expectRevert("Pool is not active");
        StakingFacet(address(diamond)).stake(poolId, STAKE_AMOUNT);
        vm.stopPrank();

        StakingFactoryFacet(address(diamond)).activatePool(poolId);
        assertTrue(StakingFactoryFacet(address(diamond)).getPool(poolId).active);
    }

    function test_MultipleUsers() public {
        vm.startPrank(alice);
        stakingToken.approve(address(diamond), STAKE_AMOUNT);
        StakingFacet(address(diamond)).stake(poolId, STAKE_AMOUNT);
        vm.stopPrank();

        vm.startPrank(bob);
        stakingToken.approve(address(diamond), STAKE_AMOUNT);
        StakingFacet(address(diamond)).stake(poolId, STAKE_AMOUNT);
        vm.stopPrank();

        vm.warp(block.timestamp + 1 days);

        assertGt(StakingFacet(address(diamond)).earned(poolId, alice), 0);
        assertGt(StakingFacet(address(diamond)).earned(poolId, bob),   0);
        assertEq(StakingFactoryFacet(address(diamond)).getPool(poolId).totalStaked, STAKE_AMOUNT * 2);
    }

    function test_NonOwnerCannotCreatePool() public {
        vm.prank(alice);
        vm.expectRevert("Not owner");
        StakingFactoryFacet(address(diamond)).createPool(
            address(stakingToken), address(rewardToken), REWARD_RATE, LOCK_PERIOD, PENALTY_RATE
        );
    }

    function test_GetAllPools() public view {
        LibAppStorage.PoolInfo[] memory allPools = StakingFactoryFacet(address(diamond)).getAllPools();
        assertEq(allPools.length, 1);
        assertEq(allPools[0].stakingToken, address(stakingToken));
    }

    function generateSelectors(string memory _facetName) internal returns (bytes4[] memory selectors) {
        string[] memory cmd = new string[](3);
        cmd[0] = "node";
        cmd[1] = "scripts/genSelectors.js";
        cmd[2] = _facetName;
        bytes memory res = vm.ffi(cmd);
        selectors = abi.decode(res, (bytes4[]));
    }

    function diamondCut(FacetCut[] calldata _diamondCut, address _init, bytes calldata _calldata) external override {}
}
