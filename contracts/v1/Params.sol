// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.8.0;

import "./interfaces/IValidators.sol";
import "./interfaces/IPunish.sol";
import "./interfaces/IIncentive.sol";
import "./interfaces/IProposal.sol";

contract Params {
    bool public initialized;

    // System contracts
    IIncentive public constant incentiveContract = IIncentive(0x000000000000000000000000000000000000F001);
    IProposal public constant proposalContract = IProposal(0x000000000000000000000000000000000000F002);
    IValidators public constant validatorsContract = IValidators(0x000000000000000000000000000000000000F003);
    IPunish public constant punishContract = IPunish(0x000000000000000000000000000000000000F004);


    uint constant PERCENT_BASE = 10000;

    modifier onlyMiner() {
        require(msg.sender == block.coinbase, "Miner only");
        _;
    }

    modifier onlyNotInitialized() {
        require(!initialized, "Already initialized");
        _;
    }

    modifier onlyInitialized() {
        require(initialized, "Not init yet");
        _;
    }

    modifier onlyPunishContract() {
        require(msg.sender == address(punishContract), "Punish contract only");
        _;
    }

    modifier onlyBlockEpoch(uint256 epoch) {
        require(block.number % epoch == 0, "Block epoch only");
        _;
    }

    modifier onlyValidatorsContract() {
        require(msg.sender == address(validatorsContract), "Validators contract only");
        _;
    }

    modifier onlyProposalContract() {
        require(msg.sender == address(proposalContract), "Validators contract only");
        _;
    }

    modifier onlyValidAddress(address _address) {
        require(_address != address(0), "Invalid address");
        _;
    }

}
