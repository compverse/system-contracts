// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.8.0;

import "./IStakePool.sol";

interface IValidators {
    function improveRanking() external;

    function lowerRanking() external;

    function removeRanking() external;

    function pendingReward(IStakePool pool) external view returns (uint);

    function withdrawReward() external;

    function stakePools(address validator) external view returns (IStakePool);

    function isActiveValidator(address who) external view returns (bool);

    function getActiveValidators() external view returns (address[] memory);

    function punishIncome(address validator) external payable;
}
