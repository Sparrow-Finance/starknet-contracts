use starknet::ContractAddress;

#[starknet::interface]
pub trait IValidatorPool<TContractState> {
    // enter delegation pool --> stake to validator
    fn enter_delegation_pool(ref self: TContractState, reward_address: ContractAddress, amount: u128);

    // add more to existing delegation  ---> stake more
    fn add_to_delegation_pool(ref self: TContractState, pool_member: ContractAddress, amount: u128) -> u128;

    // Request to exit delegation (unstake) ---> requestUnlock
    fn exit_delegation_pool_intent(ref self: TContractState, amount: u128);

    // Finalize exit after waiting period  ----> claimUnlock
    fn exit_delegation_pool_action(
        ref self: TContractState, 
        pool_member: ContractAddress
    ) -> u128;

    // Claim staking rewards              ----> add rewards
    fn claim_rewards(
        ref self: TContractState, 
        pool_member: ContractAddress
    ) -> u128;
}