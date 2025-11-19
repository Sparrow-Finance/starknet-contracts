use snforge_std::{declare, ContractClassTrait, DeclareResultTrait};
use starknet::{ContractAddress};
use openzeppelin_interfaces::erc20::{IERC20Dispatcher};

use sp_strk::interfaces::sp_strk::IspSTRKDispatcher;
use sp_strk::interfaces::withdrawal_queue::{IWithdrawalQueueNFTDispatcher};
use sp_strk::types::init::InitParams;
use crate::utils::serialize;

// Deploy spSTRK contract with given parameters
pub fn deploy_contract(params: InitParams) -> IspSTRKDispatcher {
    let contract_class = declare("spSTRK").unwrap().contract_class();
    let init_params = serialize(@params);
    let (contract_address, _) = contract_class.deploy(@init_params).expect('Deploy spSTRK failed');
    IspSTRKDispatcher { contract_address }
}

pub fn deploy_mock_validator() -> ContractAddress {
    let contract = declare("MockValidatorPool").unwrap().contract_class();
    let calldata = array![];
    
    let (contract_address, _) = contract.deploy(@calldata).unwrap();
    
    contract_address
}

// Deploy mock ERC20 token with given recipient
pub fn deploy_mock_token(recipient: ContractAddress) -> IERC20Dispatcher {
    let contract_class = declare("MockERC20").unwrap().contract_class();
    let init_params = serialize(@recipient);
    let (contract_address, _) = contract_class
        .deploy(@init_params)
        .expect('Deploy mock erc20 failed');
    IERC20Dispatcher { contract_address }
}

// Deploy WithdrawalQueueNFT contract
pub fn deploy_withdrawal_nft(vault_address: ContractAddress) -> IWithdrawalQueueNFTDispatcher {
    let contract_class = declare("WithdrawalQueueNFT").unwrap().contract_class();
    let mut calldata = array![vault_address.into()];
    let (contract_address, _) = contract_class.deploy(@calldata).expect('Deploy NFT failed');
    IWithdrawalQueueNFTDispatcher { contract_address }
}