use starknet::ContractAddress;

/// Interface for Starknet Delegation Pool Contract
/// Based on official Starknet pool ABI
#[starknet::interface]
pub trait IDelegationPool<TContractState> {
    /// Enter the delegation pool (delegate STRK to validator)
    /// # Arguments
    /// * `reward_address` - Address to receive rewards
    /// * `amount` - Amount to delegate (u128)
    fn enter_delegation_pool(
        ref self: TContractState, 
        reward_address: ContractAddress, 
        amount: u128
    );

    /// Add more STRK to existing delegation pool membership
    /// # Arguments
    /// * `amount` - Amount to add (u128)
    fn add_to_delegation_pool(ref self: TContractState, amount: u128);

    /// Signal intent to exit delegation pool (step 1 of 2)
    /// # Arguments
    /// * `amount` - Amount to exit (u128)
    fn exit_delegation_pool_intent(ref self: TContractState, amount: u128);

    /// Complete exit from delegation pool (step 2 of 2)
    /// # Arguments
    /// * `pool_member` - Address of the pool member exiting
    /// # Returns
    /// Amount of STRK returned (u128)
    fn exit_delegation_pool_action(
        ref self: TContractState, 
        pool_member: ContractAddress
    ) -> u128;

    /// Claim rewards from delegation pool
    /// # Arguments
    /// * `pool_member` - Address of the pool member claiming
    /// # Returns
    /// Amount of rewards claimed (u128)
    fn claim_rewards(ref self: TContractState, pool_member: ContractAddress) -> u128;
}
