//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

// import "@pancakeswap/pancake-swap-lib/contracts/access/Ownable.sol";
import '@pancakeswap/pancake-swap-lib/contracts/token/BEP20/IBEP20.sol';
import './ZoinksToken.sol';
import './ShaggyToken.sol';
import './ScoobyToken.sol';

interface IMigratorChef {
    // Perform LP token migration from legacy PancakeSwap to CakeSwap.
    // Take the current LP token address and return the new LP token address.
    // Migrator should have full access to the caller's LP token.
    // Return the new LP token address.
    //
    // XXX Migrator must have allowance access to PancakeSwap LP tokens.
    // CakeSwap must mint EXACTLY the same amount of CakeSwap LP tokens or
    // else something bad will happen. Traditional PancakeSwap does not
    // do that so be careful!
    function migrate(IBEP20 token) external returns (IBEP20);
}

contract MasterChef is Ownable {
    
    // Info of each user
    struct UserInfo {
        uint256 amount; // How many LP tokens the user has provided
        uint256 zoinksRewardDebt;
        uint256 shaggyRewardDebt;
        uint256 scoobyRewardDebt;
    }

    // Info of each pool
    struct PoolInfo {
        IBEP20 lpToken; // Address of LP token contract.
        uint256 zoinksAllocPoint; // How many allocation points assigned to this pool.
        uint256 shaggyAllocPoint; // How many allocation points assigned to this pool.
        uint256 scoobyAllocPoint; // How many allocation points assigned to this pool.
        uint256 zoinksLastRewardBlock; // Last block number that cakes distribution occurs.
        uint256 shaggyLastRewardBlock; // Last block number that cakes distribution occurs.
        uint256 scoobyLastRewardBlock; // Last block number that cakes distribution occurs.
        uint256 accZoinksPerShare; // Accumulated Zoinks per share. 
        uint256 accShaggyPerShare; // Accumulated Shaggy per share.
        uint256 accScoobyPerShare; // Accumulated Shaggy per share. 
    }

    // Zoinks Token!
    ZoinksToken public zoinks;

    // Scooby Token!
    ScoobyToken public scooby;

    // Shaggy Token!
    ShaggyToken public shaggy;

    // Dev Address.
    address public devAddr;

    // The migrator contract. It has a lot of power. Can only be set through governance (owner).
    IMigratorChef public migrator;

    // Scooby tokens created per block.
    uint256 public scoobyPerBlock = 100;

    // Shaggy tokens created per block.
    uint256 public shaggyPerBlock = 100;

    // Info of each pool
    PoolInfo[] public poolInfo;

    // Info of each user that statek LP tokens
    mapping(uint256 => mapping (address => UserInfo)) public userInfo;

    // Zoinks Total allocation Points. Must be the sum of all zoinks allocation points in all pools.
    uint256 public zoinksTotalAllocPoint = 0;

    // Scooby Total allocation Points. Must be the sum of all scooby allocation points in all pools.
    uint256 public scoobyTotalAllocPoint = 0;

    // Shaggy Total allocation Points. Must be the sum of all shaggy allocation points in all pools.
    uint256 public shaggyTotalAllocPoint = 0;
    
    // The block number when mining starts.
    uint256 public startBlock;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);

    // constructor() public {}

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    // Add a new lp to the pool. Can only be called by the owner.
    // XXX DO NOT add the same LP token more than once. Rewards will be messed up if you do.
    function add(
        uint256 _zoinksAllocPoint,
        uint256 _scoobyAllocPoint,
        uint256 _shaggyAllocPoint,
        IBEP20 _lpToken,
        bool _withUpdate
    ) public onlyOwner {
        if(_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardBlock = block.number > startBlock ? block.number : startBlock;
        zoinksTotalAllocPoint += _zoinksAllocPoint;
        scoobyTotalAllocPoint += _scoobyAllocPoint;
        shaggyTotalAllocPoint += _shaggyAllocPoint;

        poolInfo.push(PoolInfo({
            lpToken: _lpToken,
            zoinksAllocPoint: _zoinksAllocPoint,
            scoobyAllocPoint: _scoobyAllocPoint,
            shaggyAllocPoint: _shaggyAllocPoint,
            zoinksLastRewardBlock: lastRewardBlock,
            scoobyLastRewardBlock: lastRewardBlock,
            shaggyLastRewardBlock: lastRewardBlock,
            accZoinksPerShare: 0,
            accShaggyPerShare: 0,
            accScoobyPerShare: 0
        }));
        updateStakingPool();
    }

    function set(
        uint256 _pid,
        uint256 _zoinksAllocPoint,
        uint256 _shaggyAllocPoint,
        uint256 _scoobyAllocPoint,
        bool _withUpdate
    ) public onlyOwner {
        if (_withUpdate) massUpdatePools();

        uint256 prevZoinksAllocPoint = poolInfo[_pid].zoinksAllocPoint;
        uint256 prevShaggyAllocPoint = poolInfo[_pid].shaggyAllocPoint;
        uint256 prevScoobyAllocPoint = poolInfo[_pid].scoobyAllocPoint;
        poolInfo[_pid].zoinksAllocPoint = _zoinksAllocPoint;
        poolInfo[_pid].shaggyAllocPoint = _shaggyAllocPoint;
        poolInfo[_pid].scoobyAllocPoint = _scoobyAllocPoint;

        if(prevZoinksAllocPoint != _zoinksAllocPoint && prevShaggyAllocPoint != _shaggyAllocPoint && prevScoobyAllocPoint != _scoobyAllocPoint) {
            updateStakingPool();
        } else {
            if (prevZoinksAllocPoint != _zoinksAllocPoint) {
                zoinksTotalAllocPoint = zoinksTotalAllocPoint - prevZoinksAllocPoint + _zoinksAllocPoint;
                updateZoinksStakingPool();
            }

            if (prevShaggyAllocPoint != _shaggyAllocPoint) {
                shaggyTotalAllocPoint = shaggyTotalAllocPoint - prevShaggyAllocPoint + _shaggyAllocPoint;
                updateShaggyStakingPool();
            }

            if (prevScoobyAllocPoint != _scoobyAllocPoint) {
                scoobyTotalAllocPoint = scoobyTotalAllocPoint - prevScoobyAllocPoint + _scoobyAllocPoint;
                updateScoobyStakingPool();
            }
        }
    }

    function updateStakingPool() internal {
        uint256 length = poolInfo.length;
        uint256 zoinksPoints = 0;
        uint256 shaggyPoints = 0;
        uint256 scoobyPoints = 0;

        for (uint256 pid = 1; pid < length; pid ++)
        {
            zoinksPoints = zoinksPoints + poolInfo[pid].zoinksAllocPoint;
            shaggyPoints = shaggyPoints + poolInfo[pid].shaggyAllocPoint;
            scoobyPoints = scoobyPoints + poolInfo[pid].scoobyAllocPoint;
        }

        if (zoinksPoints != 0) {
            zoinksTotalAllocPoint = zoinksTotalAllocPoint - poolInfo[0].zoinksAllocPoint + zoinksPoints;
            poolInfo[0].zoinksAllocPoint = zoinksPoints;
        }

        if (shaggyPoints != 0) {
            zoinksTotalAllocPoint = zoinksTotalAllocPoint - poolInfo[0].zoinksAllocPoint + shaggyPoints;
            poolInfo[0].shaggyAllocPoint = shaggyPoints;
        }

        if (scoobyPoints != 0) {
            scoobyTotalAllocPoint = scoobyTotalAllocPoint - poolInfo[0].scoobyAllocPoint + scoobyPoints;
            poolInfo[0].scoobyAllocPoint = scoobyPoints;
        }
    }

    function updateZoinksStakingPool() internal {
        uint256 length = poolInfo.length;
        uint256 points = 0;

        for (uint256 pid = 1; pid < length; pid ++)
        {
            points = points + poolInfo[pid].zoinksAllocPoint;
        }

        if (points != 0) {
            zoinksTotalAllocPoint = zoinksTotalAllocPoint - poolInfo[0].zoinksAllocPoint + points;
            poolInfo[0].zoinksAllocPoint = points;
        }
    }

    function updateShaggyStakingPool() internal {
        uint256 length = poolInfo.length;
        uint256 points = 0;

        for (uint256 pid = 1; pid < length; pid ++)
        {
            points = points + poolInfo[pid].shaggyAllocPoint;
        }

        if (points != 0) {
            shaggyTotalAllocPoint = shaggyTotalAllocPoint - poolInfo[0].shaggyAllocPoint + points;
            poolInfo[0].shaggyAllocPoint = points;
        }
    }

    function updateScoobyStakingPool() internal {
        uint256 length = poolInfo.length;
        uint256 points = 0;

        for (uint256 pid = 1; pid < length; pid ++)
        {
            points = points + poolInfo[pid].scoobyAllocPoint;
        }

        if (points != 0) {
            scoobyTotalAllocPoint = scoobyTotalAllocPoint - poolInfo[0].scoobyAllocPoint + points;
            poolInfo[0].scoobyAllocPoint = points;
        }
    }

    // Set the migrator contract. Can only be called by the owner.
    function setMigrator(IMigratorChef _migrator) public onlyOwner {
        migrator = _migrator;
    }

    // Migrate lp token to another lp contract. Can be called by anyone. We trust the migrator contract is good.
    function migrate(uint256 _pid) public {
        require(address(migrator) != address(0), "migrate: no migrator");
        PoolInfo storage pool = poolInfo[_pid];
        IBEP20 lpToken = pool.lpToken;
        uint256 bal = lpToken.balanceOf(address(this));
        // lpToken.safeApprove(address(migrator), bal);
        IBEP20 newLpToken = migrator.migrate(lpToken);
        require(bal == newLpToken.balanceOf(address(this)), "migrate: bad");
        pool.lpToken = newLpToken;
    }

    function getMultiplier(uint256 _from, uint256 _to) public pure returns (uint256) {
        uint256 multiplier = _to - _from;
        return multiplier;
    }

    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for(uint256 pid = 0; pid < length; pid++) {
            updatePool(pid);
        }
    }

    // Update Reward variables of the given pool to be up-to-date
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];

        // if(block.number < pool.lastRewardBlock) return;

        uint256 accZoinksSupply = pool.accZoinksPerShare;
        uint256 accShaggySupply = pool.accShaggyPerShare;
        uint256 accScoobySupply = pool.accScoobyPerShare;

        if(accZoinksSupply == 0) {
            pool.zoinksLastRewardBlock = block.number;
            return;
        } else {
            uint256 multiplier = getMultiplier(pool.zoinksLastRewardBlock, block.number);
            uint256 zoinksReward = multiplier * pool.accZoinksPerShare * pool.zoinksAllocPoint / zoinksTotalAllocPoint;

            pool.accZoinksPerShare = pool.accZoinksPerShare + zoinksReward * (1e12) / accZoinksSupply;
            pool.zoinksLastRewardBlock = block.number;
        }

        if(accShaggySupply == 0) {
            pool.shaggyLastRewardBlock = block.number;
            return;
        } else {
            uint256 multiplier = getMultiplier(pool.shaggyLastRewardBlock, block.number);
            uint256 shaggyReward = multiplier * pool.accShaggyPerShare * pool.shaggyAllocPoint / shaggyTotalAllocPoint;

            shaggy.mintToRewardPools();

            pool.accShaggyPerShare = pool.accShaggyPerShare + shaggyReward * (1e12) / accShaggySupply;
            pool.shaggyLastRewardBlock = block.number;
        }

        if(accScoobySupply == 0) {
            pool.scoobyLastRewardBlock = block.number;
            return;
        } else {
            uint256 multiplier = getMultiplier(pool.scoobyLastRewardBlock, block.number);
            uint256 scoobyReward = multiplier * pool.accScoobyPerShare * pool.scoobyAllocPoint / scoobyTotalAllocPoint;

            scooby.mintToRewardPools();

            pool.accScoobyPerShare = pool.accScoobyPerShare + scoobyReward * (1e12) / accScoobySupply;
            pool.scoobyLastRewardBlock = block.number;
        }
    }

    // Deposit LP tokens
    function deposit(uint256 _pid, uint256 _amount) public {
        require(_pid != 0, 'deposit by staking');

        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);
        if(user.amount > 0) {
            uint256 zoinksPending = user.amount * pool.accZoinksPerShare / (1e12) - user.zoinksRewardDebt;
            if(zoinksPending > 0) {
                zoinks.transferFrom(address(this), msg.sender, zoinksPending);
            }

            uint256 shaggyPending = user.amount * pool.accShaggyPerShare / (1e12) - user.shaggyRewardDebt;
            if(shaggyPending > 0) {
                shaggy.transferFrom(address(this), msg.sender, shaggyPending);
            }

            uint256 scoobyPending = user.amount * pool.accScoobyPerShare / (1e12) - user.scoobyRewardDebt;
            if(scoobyPending > 0) {
                scooby.transferFrom(address(this), msg.sender, scoobyPending);
            }
        }

        if (_amount > 0) {
            pool.lpToken.transferFrom(address(msg.sender), address(this), _amount);
            user.amount = user.amount + _amount;
        }

        user.zoinksRewardDebt = user.amount * pool.accZoinksPerShare / (1e12);
        user.shaggyRewardDebt = user.amount * pool.accShaggyPerShare / (1e12);
        user.scoobyRewardDebt = user.amount * pool.accScoobyPerShare / (1e12);
        emit Deposit(msg.sender, _pid, _amount);
    }

    // Withdraw LP tokens from MasterChef.
    function withdraw(uint256 _pid, uint256 _amount) public {
        require (_pid != 0, 'withdraw zoinks by unstaking');

        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");

        updatePool(_pid);

        uint256 zoinksPending = user.amount * pool.accZoinksPerShare / (1e12) - user.zoinksRewardDebt;

        if(zoinksPending > 0) {
            zoinks.transferFrom(address(this), msg.sender, zoinksPending);
        }

        uint256 shaggyPending = user.amount * pool.accShaggyPerShare / (1e12) - user.shaggyRewardDebt;

        if(shaggyPending > 0) {
            shaggy.transferFrom(address(this), msg.sender, shaggyPending);
        }

        uint256 scoobyPending = user.amount * pool.accScoobyPerShare / (1e12) - user.scoobyRewardDebt;

        if(scoobyPending > 0) {
            scooby.transferFrom(address(this), msg.sender, scoobyPending);
        }

        if(_amount > 0) {
            user.amount = user.amount - _amount;
            pool.lpToken.transfer(address(msg.sender), _amount);
        }
        user.zoinksRewardDebt = user.amount * pool.accZoinksPerShare / (1e12);
        user.shaggyRewardDebt = user.amount * pool.accShaggyPerShare / (1e12);
        user.scoobyRewardDebt = user.amount * pool.accScoobyPerShare / (1e12);
        emit Withdraw(msg.sender, _pid, _amount);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        
        pool.lpToken.transfer(address(msg.sender), user.amount);

        emit EmergencyWithdraw(msg.sender, _pid, user.amount);
        user.amount = 0;
        user.zoinksRewardDebt = 0;
        user.shaggyRewardDebt = 0;
        user.scoobyRewardDebt = 0;
    }
}