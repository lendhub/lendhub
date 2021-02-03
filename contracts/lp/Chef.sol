pragma solidity ^0.6.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/utils/EnumerableSet.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "../Governance/LendHub.sol";

//
// Note that it's ownable and the owner wields tremendous power. The ownership
// will be transferred to a governance smart contract once LHB is sufficiently
// distributed and the community can show to govern itself.
//
// Have fun reading it. Hopefully it's bug-free. God bless.
contract Chef is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // Info of each user.
    struct UserInfo {
        uint256 amount;     // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
        //
        // We do some fancy math here. Basically, any point in time, the amount of SUSHIs
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.amount * pool.accLHBPerShare) - user.rewardDebt
        //
        // Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
        //   1. The pool's `accLHBPerShare` (and `lastRewardBlock`) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
    }

    // Info of each pool.
    struct PoolInfo {
        IERC20 lpToken;           // Address of LP token contract.
        uint256 allocPoint;       // How many allocation points assigned to this pool. SUSHIs to distribute per block.
        uint256 lastRewardBlock;  // Last block number that SUSHIs distribution occurs.
        uint256 accLHBPerShare; // Accumulated LHB per share, times 1e12. See below.
    }

    // The LHB TOKEN!
    LendHub public lhb;
    uint256 public userLHBAmount = 0;
    // LHB tokens created per block.
    uint256 public lhbPerBlock;

    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping (uint256 => mapping (address => UserInfo)) public userInfo;
    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;
    // The block number when LHB mining starts.
    uint256 public startBlock;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);

    constructor(
        LendHub _lhb,
        uint256 _lhbPerBlock,
        uint256 _startBlock
    ) public {
        lhb = _lhb;
        lhbPerBlock = _lhbPerBlock;
        startBlock = _startBlock;
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    function updateLHBPerBlock(uint256 _lhbPerBlock) public onlyOwner {
        massUpdatePools();
        lhbPerBlock = _lhbPerBlock;
    }

    // Add a new lp to the pool. Can only be called by the owner.
    // XXX DO NOT add the same LP token more than once. Rewards will be messed up if you do.
    function add(uint256 _allocPoint, IERC20 _lpToken, bool _withUpdate) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardBlock = block.number > startBlock ? block.number : startBlock;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolInfo.push(PoolInfo({
            lpToken: _lpToken,
            allocPoint: _allocPoint,
            lastRewardBlock: lastRewardBlock,
            accLHBPerShare: 0
        }));
    }

    // Update the given pool's LHB allocation point. Can only be called by the owner.
    function set(uint256 _pid, uint256 _allocPoint, bool _withUpdate) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(_allocPoint);
        poolInfo[_pid].allocPoint = _allocPoint;
    }

    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(uint256 _from, uint256 _to) public pure returns (uint256) {
        return _to.sub(_from);
    }

    // View function to see pending SUSHIs on frontend.
    function pendingLHB(uint256 _pid, address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accLHBPerShare = pool.accLHBPerShare;
        uint256 lpSupply = 0;
        if (address(pool.lpToken) == address(lhb)) {
             lpSupply = userLHBAmount;
        } else {
            lpSupply = pool.lpToken.balanceOf(address(this));
        }
        if (block.number > pool.lastRewardBlock && lpSupply != 0) {
            uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
            uint256 sushiReward = multiplier.mul(lhbPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
            accLHBPerShare = accLHBPerShare.add(sushiReward.mul(1e12).div(lpSupply));
        }
        return user.amount.mul(accLHBPerShare).div(1e12).sub(user.rewardDebt);
    }

    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        uint256 lpSupply = 0;
        if (address(pool.lpToken) == address(lhb)) {
            lpSupply = userLHBAmount;
        } else {
            lpSupply = pool.lpToken.balanceOf(address(this));
        }
        if (lpSupply == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
        uint256 sushiReward = multiplier.mul(lhbPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
        pool.accLHBPerShare = pool.accLHBPerShare.add(sushiReward.mul(1e12).div(lpSupply));
        pool.lastRewardBlock = block.number;
    }

    // Deposit LP tokens to MasterChef for LHB allocation.
    function deposit(uint256 _pid, uint256 _amount) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);
        if (user.amount > 0) {
            uint256 pending = user.amount.mul(pool.accLHBPerShare).div(1e12).sub(user.rewardDebt);
            if(pending > 0) {
                safeLHBTransfer(msg.sender, pending);
            }
        }
        if(_amount > 0) {
            pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
            user.amount = user.amount.add(_amount);
            if (address(pool.lpToken) == address(lhb)) {
                userLHBAmount = userLHBAmount.add(_amount);
            }
        }
        user.rewardDebt = user.amount.mul(pool.accLHBPerShare).div(1e12);
        emit Deposit(msg.sender, _pid, _amount);
    }

    // Withdraw LP tokens from MasterChef.
    function withdraw(uint256 _pid, uint256 _amount) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");
        updatePool(_pid);
        uint256 pending = user.amount.mul(pool.accLHBPerShare).div(1e12).sub(user.rewardDebt);
        if(pending > 0) {
            safeLHBTransfer(msg.sender, pending);
        }
        if(_amount > 0) {
            user.amount = user.amount.sub(_amount);
            if (address(pool.lpToken) == address(lhb)) {
                userLHBAmount = userLHBAmount.sub(_amount);
            }
            pool.lpToken.safeTransfer(address(msg.sender), _amount);
        }
        user.rewardDebt = user.amount.mul(pool.accLHBPerShare).div(1e12);
        emit Withdraw(msg.sender, _pid, _amount);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        uint256 amount = user.amount;
        user.amount = 0;
        user.rewardDebt = 0;
        if (address(pool.lpToken) == address(lhb)) {
            userLHBAmount = userLHBAmount.sub(amount);
        }
        pool.lpToken.safeTransfer(address(msg.sender), amount);
        emit EmergencyWithdraw(msg.sender, _pid, amount);
    }

    // Safe lhb transfer function, just in case if rounding error causes pool to not have enough LHBs.
    function safeLHBTransfer(address _to, uint256 _amount) internal {
        uint256 lhbBalance = lhb.balanceOf(address(this));
        lhbBalance = lhbBalance.sub(userLHBAmount);
        if (_amount > lhbBalance) {
            lhb.transfer(_to, lhbBalance);
        } else {
            lhb.transfer(_to, _amount);
        }
    }

    function grantCompInternal(address _to, uint _amount) internal returns (uint) {
        uint lhbBalance = lhb.balanceOf(address(this));
        lhbBalance = lhbBalance.sub(userLHBAmount);
        if (_amount <= lhbBalance) {
            lhb.transfer(_to, _amount);
            return 0;
        }
        return _amount;
    }

    function _grantComp(address recipient, uint amount) public onlyOwner {
        uint amountLeft = grantCompInternal(recipient, amount);
        require(amountLeft == 0, "insufficient LHB for grant");
    }
}
