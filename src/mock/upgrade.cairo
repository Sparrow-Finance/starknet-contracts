#[starknet::interface]
pub trait INewspSTRK<TContractState> {
    fn new_function(self: @TContractState) -> u8;
}

#[starknet::contract]
pub mod NewspSTRK {
    use starknet::{ContractAddress, ClassHash};
    use starknet::storage::{Map};
    use openzeppelin::token::erc20::{ERC20Component, ERC20HooksEmptyImpl};
    use openzeppelin::access::ownable::OwnableComponent;
    use openzeppelin::upgrades::UpgradeableComponent;
    use openzeppelin::upgrades::interface::IUpgradeable;

    use sp_strk::interfaces::sp_strk::{UnlockRequest};
    use sp_strk::types::init::InitParams;
    use super::INewspSTRK;

    component!(path: ERC20Component, storage: erc20, event: ERC20Event);
    component!(path: OwnableComponent, storage: ownable, event: OwnableEvent);
    component!(path: UpgradeableComponent, storage: upgradeable, event: UpgradeableEvent);

    // ERC20 Mixin
    #[abi(embed_v0)]
    impl ERC20MixinImpl = ERC20Component::ERC20MixinImpl<ContractState>;
    impl ERC20InternalImpl = ERC20Component::InternalImpl<ContractState>;

    // Ownable Mixin
    #[abi(embed_v0)]
    impl OwnableTwoStepMixinImpl =
        OwnableComponent::OwnableTwoStepMixinImpl<ContractState>;
    impl OwnableInternalImpl = OwnableComponent::InternalImpl<ContractState>;

    // Upgradeable
    impl UpgradeableInternalImpl = UpgradeableComponent::InternalImpl<ContractState>;


    #[storage]
    struct Storage {
        total_pooled_STRK: u256,
        dao_fee_basis_points: u16,
        dev_fee_basis_points: u16,
        accumulated_dao_fees: u256,
        accumulated_dev_fees: u256,
        min_stake_amount: u256,
        unlock_period: u64,
        claim_window: u64,
        unlock_requests: Map<ContractAddress, UnlockRequest>,
        strk_token: ContractAddress,
        #[substorage(v0)]
        erc20: ERC20Component::Storage,
        #[substorage(v0)]
        ownable: OwnableComponent::Storage,
        #[substorage(v0)]
        upgradeable: UpgradeableComponent::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        ERC20Event: ERC20Component::Event,
        #[flat]
        OwnableEvent: OwnableComponent::Event,
        #[flat]
        UpgradeableEvent: UpgradeableComponent::Event,
    }

    #[constructor]
    fn constructor(ref self: ContractState, params: InitParams) {
        // Initialize Ownable
        self.ownable.initializer(params.owner);

        // Initialize ERC20
        self.erc20.initializer("Sparrow Staked STRK", "spSTRK");
    }

    // ====================================
    // Upgradeable Implementation
    // ====================================

    #[abi(embed_v0)]
    impl UpgradeableImpl of IUpgradeable<ContractState> {
        fn upgrade(ref self: ContractState, new_class_hash: ClassHash) {
            self.ownable.assert_only_owner();
            self.upgradeable.upgrade(new_class_hash);
        }
    }

    #[abi(embed_v0)]
    impl NewspSTRKImpl of INewspSTRK<ContractState> {
        fn new_function(self: @ContractState) -> u8 {
            10
        }
    }
}
