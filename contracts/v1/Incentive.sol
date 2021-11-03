//SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.8.0;

import "./library/SafeMath.sol";
import "./Params.sol";

contract Incentive is Params {
    using SafeMath for uint256;

    enum Part {
        TeamReward,
        EcologyReward,
        PowerReward
    }

    struct reward {
        // address to receive reward
        address rewardAddr;
        // percent part
        uint part;
        // received reward
        uint receivedReward;
        // total reward
        uint totalReward;
    }

    Part[] parts;

    address public admin;
    address public pendingAdmin;
    uint256 public totalReward;

    mapping(Part => reward) public rewards;

    event LogWithdraw(
        address indexed to,
        uint256 indexed amount,
        Part part
    );
    event AdminChanging(address indexed newAdmin);
    event AdminChanged(address indexed newAdmin);

    modifier onlyAdmin(){
        require(msg.sender == admin, "Only admin");
        _;
    }

    function initialize() external onlyNotInitialized {
        Part first = Part.TeamReward;
        Part second = Part.EcologyReward;
        Part third = Part.PowerReward;
        parts.push(first);
        parts.push(second);
        parts.push(third);
        rewards[first].rewardAddr = 0xa7B7cBdaa54039bB88Fb5bB94C187AC9E9087137;
        rewards[second].rewardAddr = 0x3416F78C08d3E32851196Aaa3eF58b36C70F5fD9;
        rewards[third].rewardAddr = 0xdbf882abdFb3141430287ea94f698c1047e7106A;
        rewards[first].part = 1000;
        rewards[second].part = 2000;
        rewards[third].part = 7000;
        admin = 0x75990C4e397C0f83bB5C22e2d57ce44B8267A7B2;
        initialized = true;
    }

    function submitChangeAdmin(address newAdmin) external onlyAdmin {
        pendingAdmin = newAdmin;

        emit AdminChanging(newAdmin);
    }

    function confirmChangeAdmin() external {
        require(msg.sender == pendingAdmin, "New admin only");

        admin = pendingAdmin;
        pendingAdmin = address(0);

        emit AdminChanged(admin);
    }

    // update reward
    function _updateCumulativeReward(uint256 amount) internal {
        totalReward = totalReward + amount;
        uint256 added;
        for (uint8 i = 0; i < parts.length; i++) {
            if (i == parts.length.sub(1)) {
                uint _reward = amount.sub(added);
                rewards[parts[i]].totalReward = rewards[parts[i]].totalReward.add(_reward);
                break;
            }
            uint _reward = amount.mul(rewards[parts[i]].part).div(PERCENT_BASE);
            rewards[parts[i]].totalReward = rewards[parts[i]].totalReward.add(_reward);
            added = added + _reward;
        }
    }

    // withdraw reward
    function withdraw(Part _part) public {
        require(rewards[_part].rewardAddr == msg.sender, "address error");
        uint _reward = rewards[_part].totalReward.sub(rewards[_part].receivedReward);
        require(_reward > 0, "reward need >0");
        rewards[_part].receivedReward = rewards[_part].receivedReward.add(_reward);
        sendValue(msg.sender, _reward);

        emit LogWithdraw(msg.sender, _reward, _part);
    }

    // set reward incentive infomation by manager
    function setReward(address[] memory _addrs, uint256[] memory _parts) public onlyAdmin {
        require(_addrs.length == _parts.length, "params error");
        require(_parts.length == 3, "params error");
        uint p;
        for (uint i = 0; i < parts.length; i++) {
            require(_addrs[i] != address(0));
            rewards[parts[i]].rewardAddr = _addrs[i];
            rewards[parts[i]].part = _parts[i];
            p = p + _parts[i];
        }
        require(p == PERCENT_BASE, "params error");
    }

    function receiveReward() external payable {
        uint256 amount = msg.value;
        if (amount > 0) {
            _updateCumulativeReward(amount);
        }
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
