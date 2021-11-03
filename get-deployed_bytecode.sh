#!/bin/bash

set -e

rm -rf ./build
truffle compile

address_list_code=`cat ./build/contracts/AddressList.json |jq '.deployedBytecode'`
incentive_code=`cat ./build/contracts/Incentive.json |jq '.deployedBytecode'`
proposal_code=`cat ./build/contracts/Proposal.json |jq '.deployedBytecode'`
validators_code=`cat ./build/contracts/Validators.json |jq '.deployedBytecode'`
punish_code=`cat ./build/contracts/Punish.json |jq '.deployedBytecode'`


cat >output.txt <<EOF
//Mainnet
//TODO: change this on mainnet
var (
	AddressListContractCodeMainnet = common.FromHex($address_list_code)
	IncentiveContractCodeMainnet   = common.FromHex($incentive_code)
	ProposalContractCodeMainnet    = common.FromHex($proposal_code)
	ValidatorsContractCodeMainnet  = common.FromHex($validators_code)
	PunishContractCodeMainnet      = common.FromHex($punish_code)
)

//Testnet
var (
	AddressListContractCodeTestnet = common.FromHex($address_list_code)
	IncentiveContractCodeTestnet   = common.FromHex($incentive_code)
	ProposalContractCodeTestnet    = common.FromHex($proposal_code)
	ValidatorsContractCodeTestnet  = common.FromHex($validators_code)
	PunishContractCodeTestnet      = common.FromHex($punish_code)
)
EOF

echo "generated go code in output.txt"