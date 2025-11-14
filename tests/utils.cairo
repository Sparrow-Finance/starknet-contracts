use starknet::ContractAddress;
use openzeppelin_interfaces::erc20::{IERC20Dispatcher};
use openzeppelin_interfaces::erc721::{IERC721Dispatcher};

// Serialize data to felt252 array
pub fn serialize<T, +Serde<T>>(t: @T) -> Array<felt252> {
    let mut result: Array<felt252> = ArrayTrait::new();
    Serde::serialize(t, ref result);
    result
}

// Deserialize felt252 array to data
pub fn deserialize<T, +Serde<T>>(mut data: Span<felt252>) -> T {
    Serde::deserialize(ref data).expect('DESERIALIZE_INPUT_FAILED')
}

// Convert amount in ether to wei
pub fn ether(amount: u256) -> u256 {
    amount * 1_000_000_000_000_000_000
}

// Create IERC20Dispatcher from given address
pub fn erc20(address: ContractAddress) -> IERC20Dispatcher {
    IERC20Dispatcher { contract_address: address }
}

// Create IERC721Dispatcher from given address
pub fn erc721(address: ContractAddress) -> IERC721Dispatcher {
    IERC721Dispatcher { contract_address: address }
}