// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.8.0;

interface IStakePool {
    function state() external view returns (State);

    function totalStake() external view returns (uint);

    function validator() external view returns (address);

    function switchState(bool pause) external;

    function punish() external;

    function removeValidatorIncoming() external;
}

enum State {
    Idle,
    Ready,
    Pause,
    Jail
}
