// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.8.0;

import "./Params.sol";
import "./library/SafeMath.sol";
import "./Proposal.sol";
import "./Punish.sol";
import "./StakePool.sol";
import "./library/SortedList.sol";
import "./interfaces/IStakePool.sol";
import "./interfaces/IValidators.sol";


contract Validators is Params, IValidators {
    using SafeMath for uint;
    using SortedLinkedList for SortedLinkedList.List;

    // System params
    uint8 public constant MaxActiveValidators = 21;
    uint8 public constant MaxBackupValidators = 11;

    // reward
    uint backupsRewardNumerator;
    uint validatorsRewardNumerator;
    uint incentiveRewardNumerator;

    address public admin;

    uint8 public activeCount;
    uint8 public backupCount;

    address[] activeValidators;
    address[] backupValidators;
    mapping(address => uint8) actives;

    address[] public allValidators;
    mapping(address => IStakePool) public override stakePools;

    enum Operation {Distribute, UpdateValidators}

    uint256 rewardLeft;
    mapping(IStakePool => uint) public override pendingReward;
    uint256 public PERCENT_INIT;

    // mapping key always is 1
    mapping(uint8 => SortedLinkedList.List) topStakePools;

    mapping(uint256 => mapping(Operation => bool)) operationsDone;

    event ChangeAdmin(address indexed admin);
    event UpdateValidatorCountParams(uint8 activeCount, uint8 backupCount);
    event CreateValidator(address indexed validator, address stakePool);
    event ActivationValidator(address indexed validator, address stakePool);
    event LogReactive(address indexed val, uint256 time);
    event LogPunishIncome(address indexed val, address stakePool, uint punishAmount);
    event LogDistributeBlockReward(
        address indexed coinbase,
        uint256 blockReward,
        uint256 time
    );
    event UpdateDistributionProportionParams(
        uint backupsRewardMolecule,
        uint validatorsRewardMolecule,
        uint incentiveRewardMolecule
    );

    modifier onlyAdmin() {
        require(msg.sender == admin, "Only admin");
        _;
    }

    modifier onlyRegistered() {
        IStakePool _pool = IStakePool(msg.sender);
        require(stakePools[_pool.validator()] == _pool, "Stake pool not registered");
        _;
    }

    modifier onlyNotOperated(Operation operation) {
        require(!operationsDone[block.number][operation], "Already operated");
        _;
    }

    function initialize(address[] memory _validators)
    external
    onlyNotInitialized {
        require(_validators.length > 0, "Invalid params. require _validators.length > 0 ");
        admin = 0x75990C4e397C0f83bB5C22e2d57ce44B8267A7B2;

        initialized = true;
        PERCENT_INIT = 1000;

        activeCount = 21;
        backupCount = 11;

        backupsRewardNumerator = 1000;
        validatorsRewardNumerator = 4000;
        incentiveRewardNumerator = 5000;

        for (uint8 i = 0; i < _validators.length; i++) {
            address _validator = _validators[i];
            require(stakePools[_validator] == IStakePool(0), "Validators already exists");
            StakePool _pool = new StakePool(_validator, _validator, PERCENT_INIT, State.Ready);

            activeValidators.push(_validator);
            actives[_validator] = 1;

            allValidators.push(_validator);
            stakePools[_validator] = _pool;
            _pool.initialize();
        }
    }

    function changeAdmin(address _newAdmin)
    external
    onlyValidAddress(_newAdmin)
    onlyAdmin {
        admin = _newAdmin;
        emit ChangeAdmin(admin);
    }

    function updateValidatorCountParams(uint8 _activeCount, uint8 _backupCount)
    external
    onlyAdmin {
        require(_activeCount <= MaxActiveValidators, "Invalid active counts");
        require(_backupCount <= MaxBackupValidators, "Invalid backup counts");

        activeCount = _activeCount;
        backupCount = _backupCount;

        emit UpdateValidatorCountParams(_activeCount, _backupCount);
    }

    function updateDistributionProportionParams(
        uint _backupsRewardMolecule,
        uint _validatorsRewardMolecule,
        uint _incentiveRewardMolecule
    ) external onlyAdmin {
        require(_backupsRewardMolecule + _validatorsRewardMolecule + _incentiveRewardMolecule == PERCENT_BASE, "proportion error");

        backupsRewardNumerator = _backupsRewardMolecule;
        validatorsRewardNumerator = _validatorsRewardMolecule;
        incentiveRewardNumerator = _incentiveRewardMolecule;

        emit UpdateDistributionProportionParams(backupsRewardNumerator, validatorsRewardNumerator, incentiveRewardNumerator);
    }

    function createValidator(address _manager, uint _percent) external onlyInitialized returns (address) {
        require(stakePools[msg.sender] == IStakePool(0), "Validators already exists");
        require(proposalContract.pass(msg.sender), "You must bee authorized first");
        require(_manager != address(0), "Invalid manager address");

        StakePool _pool = new StakePool(msg.sender, _manager, _percent, State.Idle);
        stakePools[msg.sender] = _pool;
        allValidators.push(msg.sender);

        emit CreateValidator(msg.sender, address(_pool));

        return address(_pool);
    }


    function getTopValidators()
    external
    view
    returns (address[] memory) {
        uint8 _count = 0;

        SortedLinkedList.List storage _list = topStakePools[1];
        if (_list.length < activeCount) {
            _count += _list.length;
        } else {
            _count += activeCount;
        }

        address[] memory _topValidators = new address[](_count);

        uint8 _index = 0;
        uint8 _size = activeCount;

        IStakePool cur = _list.head;
        while (_size > 0 && cur != IStakePool(0)) {
            _topValidators[_index] = cur.validator();
            _index++;
            _size--;
            cur = _list.next[cur];
        }

        return _topValidators;
    }


    function updateActiveValidatorSet(address[] memory newSet, uint256 epoch)
    external
    onlyMiner
    onlyNotOperated(Operation.UpdateValidators)
    onlyBlockEpoch(epoch)
    onlyInitialized
    {
        operationsDone[block.number][Operation.UpdateValidators] = true;

        for (uint8 i = 0; i < activeValidators.length; i ++) {
            actives[activeValidators[i]] = 0;
        }

        activeValidators = newSet;
        for (uint8 i = 0; i < activeValidators.length; i ++) {
            actives[activeValidators[i]] = 1;
        }

        delete backupValidators;

        uint8 _size = backupCount;
        SortedLinkedList.List storage _topList = topStakePools[1];
        IStakePool _cur = _topList.head;
        while (_size > 0 && _cur != IStakePool(0)) {
            if (actives[_cur.validator()] == 0) {
                backupValidators.push(_cur.validator());
                _size--;
            }
            _cur = _topList.next[_cur];
        }
    }

    function getActiveValidators()
    external
    override
    view
    returns (address[] memory){
        return activeValidators;
    }

    function getBackupValidators()
    external
    view
    returns (address[] memory){
        return backupValidators;
    }

    function getAllValidatorsLength()
    external
    view
    returns (uint){
        return allValidators.length;
    }

    function distributeBlockReward()
    external
    payable
    onlyMiner
    onlyNotOperated(Operation.Distribute)
    onlyInitialized
    {
        operationsDone[block.number][Operation.Distribute] = true;

        address val = msg.sender;
        uint256 blockReward = msg.value;

        uint _left = blockReward.add(rewardLeft);
        rewardLeft = distribution(_left);

        emit LogDistributeBlockReward(val, blockReward, block.timestamp);
    }

    function punishIncome(address validator)
    external
    override
    payable
    onlyRegistered {
        uint punishAmount = msg.value;
        uint _left = punishAmount.add(rewardLeft);
        rewardLeft = distribution(_left);

        emit LogPunishIncome(validator, msg.sender, punishAmount);
    }

    function distribution(uint _left) internal returns (uint) {
        // 10% to backups
        uint _firstPart = _left.mul(backupsRewardNumerator).div(PERCENT_BASE);
        // 40% to validators by stake
        uint _secondPartTotal = _left.mul(validatorsRewardNumerator).div(PERCENT_BASE);
        // 50% to TOKEN incentive
        uint _thirdPart = _left.mul(incentiveRewardNumerator).div(PERCENT_BASE);

        // backups
        if (backupValidators.length > 0) {
            uint _totalStake = 0;
            for (uint8 i = 0; i < backupValidators.length; i++) {
                _totalStake = _totalStake.add(stakePools[backupValidators[i]].totalStake());
            }

            if (_totalStake > 0) {
                for (uint8 i = 0; i < backupValidators.length; i++) {
                    IStakePool _pool = stakePools[backupValidators[i]];
                    uint256 _reward = _firstPart.mul(_pool.totalStake()).div(_totalStake);
                    pendingReward[_pool] = pendingReward[_pool].add(_reward);
                    _left = _left.sub(_reward);
                }
            }
        }

        // validators
        if (activeValidators.length > 0) {
            uint _totalStake = 0;
            for (uint8 i = 0; i < activeValidators.length; i++) {
                _totalStake = _totalStake.add(stakePools[activeValidators[i]].totalStake());
            }

            if (_totalStake > 0) {
                for (uint8 i = 0; i < activeValidators.length; i++) {
                    IStakePool _pool = stakePools[activeValidators[i]];
                    uint256 _reward = _secondPartTotal.mul(_pool.totalStake()).div(_totalStake);
                    pendingReward[_pool] = pendingReward[_pool].add(_reward);
                    _left = _left.sub(_reward);
                }
            } else {
                uint256 _reward = _secondPartTotal.div(activeValidators.length);
                for (uint8 i = 0; i < activeValidators.length; i++) {
                    IStakePool _pool = stakePools[activeValidators[i]];
                    pendingReward[_pool] = pendingReward[_pool].add(_reward);
                    _left = _left.sub(_reward);
                }
            }
        }

        // incentive
        incentiveContract.receiveReward{value : _thirdPart}();
        _left = _left.sub(_thirdPart);

        return _left;
    }

    function withdrawReward() override external {
        uint _amount = pendingReward[IStakePool(msg.sender)];
        if (_amount == 0) {
            return;
        }

        pendingReward[IStakePool(msg.sender)] = 0;
        StakePool(msg.sender).receiveReward{value : _amount}();
    }

    function isActiveValidator(address _validator) public override view returns (bool) {
        for (uint256 i = 0; i < activeValidators.length; i++) {
            if (activeValidators[i] == _validator) {
                return true;
            }
        }

        return false;
    }

    function updateValidatorState(address _validator, bool pause)
    external
    onlyAdmin {
        require(stakePools[_validator] != IStakePool(0), "Corresponding stake pool not found");
        stakePools[_validator].switchState(pause);
    }

    function improveRanking()
    external
    override
    onlyRegistered {
        IStakePool _pool = IStakePool(msg.sender);
        require(_pool.state() == State.Ready, "Incorrect state");

        SortedLinkedList.List storage _list = topStakePools[1];
        _list.improveRanking(_pool);
    }

    function lowerRanking()
    external
    override
    onlyRegistered {
        IStakePool _pool = IStakePool(msg.sender);
        require(_pool.state() == State.Ready, "Incorrect state");

        SortedLinkedList.List storage _list = topStakePools[1];
        _list.lowerRanking(_pool);
    }

    function removeRanking()
    external
    override
    onlyRegistered {
        IStakePool _pool = IStakePool(msg.sender);

        SortedLinkedList.List storage _list = topStakePools[1];
        _list.removeRanking(_pool);
    }

}
