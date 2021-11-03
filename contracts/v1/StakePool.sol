// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.8.0;

import "./Params.sol";
import "./library/SafeMath.sol";
import "./library/ReentrancyGuard.sol";
import "./interfaces/IStakePool.sol";
import "./interfaces/IValidators.sol";
import "./interfaces/IPunish.sol";

contract StakePool is Params, ReentrancyGuard, IStakePool {
    using SafeMath for uint;

    uint constant Coefficient = 1e18;
    uint public constant MinMargin = 50000 ether;
    uint public constant PunishAmount = 1000 ether;
    // validator
    uint public constant JailPeriod = 17280; // 3 day
    uint public constant MarginLockPeriod = 172800; // 30 day
    uint public constant ValidatorWithdrawRewardLockPeriod = 80640; // 14 day
    uint public constant PercentChangeLockPeriod = 17280; // 3 day
    // user
    uint public constant WithdrawLockPeriod = 17280; // 3 day
    uint public constant WithdrawRewardLockPeriod = 5760; // 1 day
    // 10%
    uint256 constant public OffLinePenaltyNumerator = 1000;

    uint public margin;
    //reward for validator not for stakes
    uint validatorReward;
    //base on 10000
    uint public percent;

    address public override validator;
    address public manager;

    uint accRewardPerShare;
    uint public override totalStake;

    uint public punishBlk;
    uint public exitBlk;
    uint public withdrawRewardBlk;

    uint public offLinePenaltyTOKEN;
    uint public offLineNumber;
    uint public offLineLastBlk;

    PercentChange public pendingPercentChange;
    mapping(address => StakeInfo) public stakes;
    State public override state;


    // Description
    string moniker;
    string identity;
    string website;
    string email;
    string details;

    struct StakeInfo {
        uint amount;
        uint lastAccRewardPerShare;
        uint withdrawPendingAmount;
        uint withdrawPendingReward;
        uint withdrawExitBlock;
        uint withdrawRewardBlock;
    }

    struct PercentChange {
        uint newPercent;
        uint submitBlk;
    }

    modifier onlyManager() {
        require(msg.sender == manager, "Only manager allowed");
        _;
    }

    modifier onlyValidPercent(uint _percent) {
        //zero represents null value, trade as invalid
        require(_percent >= PERCENT_BASE.mul(1).div(100) && _percent <= PERCENT_BASE.mul(1).div(10), "Invalid percent");
        _;
    }

    modifier onlyValidator() {
        require(msg.sender == validator, "Only validator allowed");
        _;
    }

    event ChangeManager(address indexed manager);
    event SubmitPercentChange(uint indexed percent);
    event ConfirmPercentChange(uint indexed percent);
    event AddMargin(address indexed sender, uint amount);
    event ChangeState(State indexed state);
    event Exit(address indexed validator);
    event WithdrawValidatorMargin(address indexed sender, uint amount);
    event ExitStake(address indexed sender, uint amount);
    event WithdrawValidatorReward(address indexed sender, uint amount);
    event WithdrawUserReward(address indexed sender, uint amount);
    event Stake(address indexed sender, uint amount);
    event WithdrawUserStake(address indexed sender, uint amount);
    event Punish(address indexed validator, uint amount);
    event RemoveIncoming(address indexed validator, uint amount);


    constructor(
        address _validator,
        address _manager,
        uint _percent,
        State _state)
    public
    onlyValidatorsContract
    onlyValidAddress(_validator)
    onlyValidAddress(_manager)
    onlyValidPercent(_percent) {
        validator = _validator;
        manager = _manager;
        percent = _percent;
        state = _state;
    }

    function editValidatorDescription(
        string calldata _moniker,
        string calldata _identity,
        string calldata _website,
        string calldata _email,
        string calldata _details
    ) external onlyManager returns (bool){
        require(
            verifyValidatorDescription(_moniker, _identity, _website, _email, _details),
            "Invalid description"
        );
        moniker = _moniker;
        identity = _identity;
        website = _website;
        email = _email;
        details = _details;
        return true;
    }

    function initialize()
    external
    onlyValidatorsContract
    onlyNotInitialized {
        initialized = true;
        validatorsContract.improveRanking();
    }


    function changeManager(address _manager)
    external
    onlyValidator {
        manager = _manager;
        emit ChangeManager(_manager);
    }

    //base on 10000
    function submitPercentChange(uint _percent)
    external
    onlyManager
    onlyValidPercent(_percent) {
        pendingPercentChange.newPercent = _percent;
        pendingPercentChange.submitBlk = block.number;

        emit SubmitPercentChange(_percent);
    }

    function confirmPercentChange()
    external
    onlyManager
    onlyValidPercent(pendingPercentChange.newPercent) {
        require(pendingPercentChange.submitBlk > 0 && block.number.sub(pendingPercentChange.submitBlk) > PercentChangeLockPeriod, "Interval not long enough");

        validatorsContract.withdrawReward();

        percent = pendingPercentChange.newPercent;
        pendingPercentChange.newPercent = 0;
        pendingPercentChange.submitBlk = 0;

        emit ConfirmPercentChange(percent);
    }

    function isIdleStateLike()
    internal
    view returns (bool) {
        return state == State.Idle || (state == State.Jail && block.number.sub(punishBlk) > JailPeriod);
    }

    function switchState(bool pause)
    external
    override
    onlyValidatorsContract {
        if (pause) {
            require(isIdleStateLike() || state == State.Ready, "Incorrect state");

            state = State.Pause;
            emit ChangeState(state);
            validatorsContract.removeRanking();
            return;
        } else {
            require(state == State.Pause, "Incorrect state");

            state = State.Idle;
            emit ChangeState(state);
            return;
        }
    }

    function punish()
    external
    override
    onlyPunishContract {
        punishBlk = block.number;

        if (state != State.Pause) {
            state = State.Jail;
            emit ChangeState(state);
        }
        validatorsContract.removeRanking();

        uint _punishAmount = margin >= PunishAmount ? PunishAmount : margin;
        if (_punishAmount > 0) {
            margin = margin.sub(_punishAmount);
            validatorsContract.punishIncome{value : _punishAmount}(validator);
            emit Punish(validator, _punishAmount);
        }

        return;
    }

    function addMargin()
    external
    payable
    onlyManager {
        require(isIdleStateLike(), "Incorrect state");
        require(exitBlk == 0 || block.number.sub(exitBlk) > MarginLockPeriod, "Interval not long enough");

        exitBlk = 0;
        margin = margin.add(msg.value);

        emit AddMargin(msg.sender, msg.value);

        uint minMargin;
        minMargin = MinMargin;

        if (margin >= minMargin) {
            state = State.Ready;
            punishContract.cleanPunishRecord(validator);
            validatorsContract.improveRanking();

            emit ChangeState(state);
        }
    }

    function exit()
    external
    onlyManager {
        require(state == State.Ready || isIdleStateLike(), "Incorrect state");
        require(exitBlk == 0 || block.number.sub(exitBlk) > MarginLockPeriod, "Interval not long enough");

        if (margin == 0) {
            exitBlk = 0;
        } else {
            exitBlk = block.number;
        }

        if (state != State.Idle) {
            state = State.Idle;
            emit ChangeState(state);

            validatorsContract.removeRanking();
        }

        emit Exit(validator);
    }

    function withdrawValidatorMargin()
    external
    nonReentrant
    onlyManager {
        require(isIdleStateLike(), "Incorrect state");
        require(exitBlk > 0 && block.number.sub(exitBlk) > MarginLockPeriod, "Interval not long enough");
        require(margin > 0, "No more margin");

        exitBlk = 0;

        uint _amount = margin;
        margin = 0;
        sendValue(msg.sender, _amount);

        emit WithdrawValidatorMargin(msg.sender, _amount);
    }

    function withdrawValidatorReward()
    external
    nonReentrant
    onlyManager {
        require(block.number.sub(withdrawRewardBlk) > ValidatorWithdrawRewardLockPeriod, "Interval too small");

        validatorsContract.withdrawReward();
        require(validatorReward > 0, "No more reward");

        uint _amount = validatorReward;

        withdrawRewardBlk = block.number;
        validatorReward = 0;
        sendValue(msg.sender, _amount);
        emit WithdrawValidatorReward(msg.sender, _amount);
    }

    function removeValidatorIncoming()
    external
    override
    onlyPunishContract {
        validatorsContract.withdrawReward();

        uint _punishAmount = validatorReward.mul(OffLinePenaltyNumerator).div(PERCENT_BASE);

        offLinePenaltyTOKEN = offLinePenaltyTOKEN.add(_punishAmount);
        offLineNumber = offLineNumber.add(1);
        offLineLastBlk = block.number;

        validatorReward = validatorReward.sub(_punishAmount);
        if (_punishAmount > 0) {
            validatorsContract.punishIncome{value : _punishAmount}(validator);
            emit RemoveIncoming(validator, _punishAmount);
        }
    }

    function receiveReward()
    external
    payable
    onlyValidatorsContract {
        uint _rewardForValidator = msg.value.mul(percent).div(PERCENT_BASE);
        validatorReward = validatorReward.add(_rewardForValidator);

        if (totalStake > 0) {
            accRewardPerShare = msg.value.sub(_rewardForValidator).mul(Coefficient).div(totalStake).add(accRewardPerShare);
        }
    }

    function stake()
    external
    payable {
        require(msg.value > 0, "Deposit quantity cannot be less than 0!");

        validatorsContract.withdrawReward();

        uint _pendingReward = accRewardPerShare.
        sub(stakes[msg.sender].lastAccRewardPerShare).
        mul(stakes[msg.sender].amount).
        div(Coefficient);

        stakes[msg.sender].amount = stakes[msg.sender].amount.add(msg.value);
        stakes[msg.sender].lastAccRewardPerShare = accRewardPerShare;
        stakes[msg.sender].withdrawPendingReward = stakes[msg.sender].withdrawPendingReward.add(_pendingReward);

        totalStake = totalStake.add(msg.value);
        emit Stake(msg.sender, msg.value);

        if (state == State.Ready) {
            validatorsContract.improveRanking();
        }
    }

    function exitStake(uint _amount)
    external {
        require(_amount > 0, "Value should not be zero");
        require(_amount <= stakes[msg.sender].amount, "Insufficient amount");

        validatorsContract.withdrawReward();

        uint _pendingReward = accRewardPerShare.
        sub(stakes[msg.sender].lastAccRewardPerShare).
        mul(stakes[msg.sender].amount).
        div(Coefficient);


        totalStake = totalStake.sub(_amount);

        stakes[msg.sender].amount = stakes[msg.sender].amount.sub(_amount);
        stakes[msg.sender].lastAccRewardPerShare = accRewardPerShare;

        if (state == State.Ready) {
            validatorsContract.lowerRanking();
        }

        stakes[msg.sender].withdrawPendingAmount = stakes[msg.sender].withdrawPendingAmount.add(_amount);
        stakes[msg.sender].withdrawPendingReward = stakes[msg.sender].withdrawPendingReward.add(_pendingReward);
        stakes[msg.sender].withdrawExitBlock = block.number;

        emit ExitStake(msg.sender, _amount);
    }

    function withdrawUserStake()
    nonReentrant
    external {
        require(block.number.sub(stakes[msg.sender].withdrawExitBlock) > WithdrawLockPeriod, "Interval too small");
        require(stakes[msg.sender].withdrawPendingAmount > 0, "Value should not be zero");

        uint _amount = stakes[msg.sender].withdrawPendingAmount;
        stakes[msg.sender].withdrawPendingAmount = 0;
        stakes[msg.sender].withdrawExitBlock = 0;

        sendValue(msg.sender, _amount);
        emit WithdrawUserStake(msg.sender, _amount);
    }

    function withdrawUserReward()
    nonReentrant
    external {
        require(block.number.sub(stakes[msg.sender].withdrawRewardBlock) > WithdrawRewardLockPeriod, "Interval too small");
        stakes[msg.sender].withdrawRewardBlock = block.number;

        validatorsContract.withdrawReward();

        uint _pendingReward = accRewardPerShare.
        sub(stakes[msg.sender].lastAccRewardPerShare).
        mul(stakes[msg.sender].amount).
        div(Coefficient);

        _pendingReward = _pendingReward.add(stakes[msg.sender].withdrawPendingReward);

        stakes[msg.sender].lastAccRewardPerShare = accRewardPerShare;
        stakes[msg.sender].withdrawPendingReward = 0;

        sendValue(msg.sender, _pendingReward);

        emit WithdrawUserReward(msg.sender, _pendingReward);
    }

    function getValidatorPendingReward() external view returns (uint) {
        uint _poolPendingReward = validatorsContract.pendingReward(IStakePool(address(this)));
        uint _rewardForValidator = _poolPendingReward.mul(percent).div(PERCENT_BASE);
        uint _validatorReward = validatorReward;

        return _validatorReward.add(_rewardForValidator);
    }

    function getUserPendingReward(address _stake) external view returns (uint){
        uint _poolPendingReward = validatorsContract.pendingReward(IStakePool(address(this)));
        uint _rewardForValidator = _poolPendingReward.mul(percent).div(PERCENT_BASE);

        uint _share = accRewardPerShare;
        if (totalStake > 0) {
            _share = _poolPendingReward.sub(_rewardForValidator).mul(Coefficient).div(totalStake).add(_share);
        }

        uint _reward = _share.sub(stakes[_stake].lastAccRewardPerShare).mul(stakes[_stake].amount).div(Coefficient);
        uint _userPendingReward = stakes[_stake].withdrawPendingReward;

        return _reward.add(_userPendingReward);
    }


    function verifyValidatorDescription(
        string memory _moniker,
        string memory _identity,
        string memory _website,
        string memory _email,
        string memory _details
    ) public pure returns (bool) {
        require(bytes(_moniker).length <= 70, "Invalid moniker length");
        require(bytes(_identity).length <= 3000, "Invalid identity length");
        require(bytes(_website).length <= 140, "Invalid website length");
        require(bytes(_email).length <= 140, "Invalid email length");
        require(bytes(_details).length <= 280, "Invalid details length");

        return true;
    }


    function validatorDescription() external view returns (
        string memory,
        string memory,
        string memory,
        string memory,
        string memory
    ){
        return (
        moniker,
        identity,
        website,
        email,
        details
        );
    }

    /**
      * @dev Replacement for Solidity's `transfer`: sends `amount` wei to
      * `recipient`, forwarding all available gas and reverting on errors.
      *
      * https://eips.ethereum.org/EIPS/eip-1884[EIP1884] increases the gas cost
      * of certain opcodes, possibly making contracts go over the 2300 gas limit
      * imposed by `transfer`, making them unable to receive funds via
      * `transfer`. {sendValue} removes this limitation.
      *
      * https://diligence.consensys.net/posts/2019/09/stop-using-soliditys-transfer-now/[Learn more].
      *
      * IMPORTANT: because control is transferred to `recipient`, care must be
      * taken to not create reentrancy vulnerabilities. Consider using
      * {ReentrancyGuard} or the
      * https://solidity.readthedocs.io/en/v0.5.11/security-considerations.html#use-the-checks-effects-interactions-pattern[checks-effects-interactions pattern].
      */
    function sendValue(address payable recipient, uint256 amount) internal {
        require(address(this).balance >= amount, "Address: insufficient balance");

        // solhint-disable-next-line avoid-low-level-calls, avoid-call-value
        (bool success,) = recipient.call{value : amount}("");
        require(success, "Address: unable to send value, recipient may have reverted");
    }
}
