// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.8.0;

interface IProposal {
    function pass(address val) external view returns (bool);
}
