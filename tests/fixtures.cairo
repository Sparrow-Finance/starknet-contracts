use snforge_std::{declare, ContractClassTrait, DeclareResultTrait};
use starknet::{ContractAddress};
use openzeppelin::token::erc20::ERC20ABIDispatcher;

use sp_strk::interfaces::sp_strk::IspSTRKDispatcher;
use sp_strk::types::init::InitParams;
use crate::utils::serialize;

// Deploy spSTRK contract with given parameters
pub fn deploy_contract(params: InitParams) -> IspSTRKDispatcher {
    let contract_class = declare("spSTRK").unwrap().contract_class();
    let init_params = serialize(@params);
    let (contract_address, _) = contract_class.deploy(@init_params).expect('Deploy spSTRK failed');
    IspSTRKDispatcher { contract_address }
}

// Deploy mock ERC20 token with given recipient
pub fn deploy_mock_token(recipient: ContractAddress) -> ERC20ABIDispatcher {
    let contract_class = declare("MockERC20").unwrap().contract_class();
    let init_params = serialize(@recipient);
    let (contract_address, _) = contract_class
        .deploy(@init_params)
        .expect('Deploy mock erc20 failed');
    ERC20ABIDispatcher { contract_address }
}
