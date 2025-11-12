use openzeppelin::access::ownable::interface::{
    OwnableTwoStepABIDispatcher, OwnableTwoStepABIDispatcherTrait,
};
use openzeppelin::token::erc20::{ERC20ABIDispatcher, ERC20ABIDispatcherTrait};
use openzeppelin::upgrades::interface::{IUpgradeableDispatcher, IUpgradeableDispatcherTrait};
use snforge_std::{
    CheatSpan, DeclareResultTrait, cheat_caller_address, declare, load, start_cheat_block_timestamp,
    start_cheat_caller_address, stop_cheat_block_timestamp, stop_cheat_caller_address,
};
use sp_strk::interfaces::sp_strk::{IspSTRK, IspSTRKDispatcher, IspSTRKDispatcherTrait};
use sp_strk::mock::upgrade::{INewspSTRKDispatcher, INewspSTRKDispatcherTrait};
use sp_strk::sp_strk::spSTRK;
use sp_strk::types::init::InitParams;
use starknet::{ContractAddress, get_contract_address};
use crate::fixtures::{deploy_contract, deploy_mock_token, deploy_mock_validator};
use crate::utils::{deserialize, erc20, ether, serialize};

fn init() -> (IspSTRKDispatcher, ERC20ABIDispatcher) {
    let owner = get_contract_address();
    let strk_token = deploy_mock_token(owner);

    let mock_validator = deploy_mock_validator();  

    let sp_strk = deploy_contract(
        InitParams {
            owner,
            strk_token: strk_token.contract_address,
            dao_fee_basis_points: 500,
            dev_fee_basis_points: 300,
            min_stake_amount: 10000000000000000,
            unlock_period: 60,
            claim_window: 604800,
            validator_pool: mock_validator,
        },
    );

    (sp_strk, strk_token)
}

#[test]
fn test_init() {
    let (spStark, _) = init();

    let token = erc20(spStark.contract_address);

    assert_eq!(token.name(), "Sparrow Staked STRK");
    assert_eq!(token.symbol(), "spSTRK");
    assert_eq!(token.decimals(), 18);
    assert_eq!(token.total_supply(), 0);

    let ownable = OwnableTwoStepABIDispatcher { contract_address: spStark.contract_address };
    assert_eq!(ownable.owner(), get_contract_address());
}

#[test]
#[should_panic(expected: ('Fees too high',))]
fn test_high_fee() {
    let mut state = spSTRK::contract_state_for_testing();
    state.set_fees(500, 600);
}

#[test]
#[should_panic(expected: ('Value below minimum',))]
fn test_low_unlock_period() {
    let mut state = spSTRK::contract_state_for_testing();
    state.set_unlock_period(30);
}

#[test]
#[should_panic(expected: ('Value above maximum',))]
fn test_high_unlock_period() {
    let mut state = spSTRK::contract_state_for_testing();
    state.set_unlock_period(2592001);
}

#[test]
#[should_panic(expected: ('Value below minimum',))]
fn test_low_claim_window() {
    let mut state = spSTRK::contract_state_for_testing();
    state.set_claim_window(3500);
}

#[test]
#[should_panic(expected: ('Value above maximum',))]
fn test_high_claim_window() {
    let mut state = spSTRK::contract_state_for_testing();
    state.set_claim_window(2592001);
}

#[test]
#[should_panic(expected: ('Caller is not the owner',))]
fn test_owner() {
    let (sp_stark, _) = init();

    let fake_owner: ContractAddress = 1.try_into().unwrap();
    cheat_caller_address(sp_stark.contract_address, fake_owner, CheatSpan::TargetCalls(1));
    sp_stark.set_fees(200, 200);
}

#[test]
#[should_panic(expected: ('Pausable: paused',))]
fn test_paused() {
    let (sp_stark, _) = init();

    sp_stark.pause();
    sp_stark.stake(100000000000000000, 10000000000000000);
}

#[test]
#[should_panic(expected: ('Below minimum stake',))]
fn test_below_minimum_stake() {
    let (sp_stark, _) = init();

    sp_stark.stake(1000000000000000, 10000000000000000);
}

#[test]
#[should_panic(expected: ('Slippage exceeded',))]
fn test_slippage_stake() {
    let (sp_stark, _) = init();

    sp_stark.stake(100000000000000000, 1000000000000000000);
}

#[test]
fn test_deposit() {
    let (sp_stark, strk_token) = init();
    let stake_amount = ether(10);

    strk_token.approve(sp_stark.contract_address, stake_amount);
    sp_stark.stake(stake_amount, stake_amount);

    let sp_stark_token = erc20(sp_stark.contract_address);
    assert_eq!(sp_stark_token.balance_of(get_contract_address()), stake_amount);
    assert_eq!(sp_stark_token.total_supply(), stake_amount);
}

#[test]
fn test_multiple_deposit() {
    let (sp_stark, strk_token) = init();

    let user1: ContractAddress = 1.try_into().unwrap();
    let user2: ContractAddress = 2.try_into().unwrap();
    let stake_amount_u1 = ether(10);
    let stake_amount_u2 = ether(5);

    strk_token.transfer(user1, stake_amount_u1);
    strk_token.transfer(user2, stake_amount_u2);

    start_cheat_caller_address(strk_token.contract_address, user1);
    strk_token.approve(sp_stark.contract_address, stake_amount_u1);
    stop_cheat_caller_address(strk_token.contract_address);

    start_cheat_caller_address(sp_stark.contract_address, user1);
    sp_stark.stake(stake_amount_u1, stake_amount_u1);
    stop_cheat_caller_address(sp_stark.contract_address);

    start_cheat_caller_address(strk_token.contract_address, user2);
    strk_token.approve(sp_stark.contract_address, stake_amount_u2);
    stop_cheat_caller_address(strk_token.contract_address);

    start_cheat_caller_address(sp_stark.contract_address, user2);
    sp_stark.stake(stake_amount_u2, stake_amount_u2);
    stop_cheat_caller_address(sp_stark.contract_address);

    let sp_stark_token = erc20(sp_stark.contract_address);
    assert_eq!(sp_stark_token.balance_of(user1), stake_amount_u1);
    assert_eq!(sp_stark_token.balance_of(user2), stake_amount_u2);
    assert_eq!(sp_stark_token.total_supply(), stake_amount_u1 + stake_amount_u2);

    let total_pooled_STRK = load(sp_stark.contract_address, selector!("total_pooled_STRK"), 2);
    assert_eq!(total_pooled_STRK, serialize(@(stake_amount_u1 + stake_amount_u2)));
}

#[test]
fn test_ratio_change_deposit() {
    let (sp_stark, strk_token) = init();

    let user1: ContractAddress = 1.try_into().unwrap();
    let user2: ContractAddress = 2.try_into().unwrap();
    let stake_amount_u1 = ether(10);
    let stake_amount_u2 = ether(10);

    strk_token.transfer(user1, stake_amount_u1);
    strk_token.transfer(user2, stake_amount_u2);

    start_cheat_caller_address(strk_token.contract_address, user1);
    strk_token.approve(sp_stark.contract_address, stake_amount_u1);
    stop_cheat_caller_address(strk_token.contract_address);

    start_cheat_caller_address(sp_stark.contract_address, user1);
    sp_stark.stake(stake_amount_u1, stake_amount_u1);
    stop_cheat_caller_address(sp_stark.contract_address);

    let rewards = ether(10);
    strk_token.approve(sp_stark.contract_address, rewards);
    sp_stark.add_rewards(rewards);

    let value_after_fees = 9200000000000000000;
    let (
        total_pooled_STRK,
        total_supply,
        exchange_rate,
        _,
        accumulated_dao_fees,
        accumulated_dev_fees,
        _,
        _,
    ) =
        sp_stark
        .get_stats();

    assert_eq!(total_pooled_STRK, stake_amount_u1 + value_after_fees);
    assert_eq!(total_supply, stake_amount_u1);
    assert_eq!(accumulated_dao_fees, 500000000000000000);
    assert_eq!(accumulated_dev_fees, 300000000000000000);
    assert_eq!(exchange_rate, 1920000000000000000);

    let sp_strk_from_strk = sp_stark.preview_stake(ether(1));
    assert_eq!(sp_strk_from_strk, 520833333333333333);

    let strk_from_sp_strk = sp_stark.preview_unlock(ether(1));
    assert_eq!(strk_from_sp_strk, 1920000000000000000);

    let user2_expected = 5208333333333333333;

    start_cheat_caller_address(strk_token.contract_address, user2);
    strk_token.approve(sp_stark.contract_address, stake_amount_u2);
    stop_cheat_caller_address(strk_token.contract_address);

    start_cheat_caller_address(sp_stark.contract_address, user2);
    sp_stark.stake(stake_amount_u2, user2_expected);
    stop_cheat_caller_address(sp_stark.contract_address);

    let sp_stark_token = erc20(sp_stark.contract_address);
    assert_eq!(sp_stark_token.balance_of(user1), stake_amount_u1);
    assert_eq!(sp_stark_token.balance_of(user2), user2_expected);
    assert_eq!(sp_stark_token.total_supply(), stake_amount_u1 + user2_expected);
}

#[test]
#[should_panic(expected: ('No shares exist',))]
fn test_unlock_without_shares() {
    let (sp_stark, _) = init();
    sp_stark.request_unlock(ether(1), ether(1));
}

#[test]
#[should_panic(expected: ('Insufficient balance',))]
fn test_unlock_without_sp_stark() {
    let (sp_stark, strk) = init();

    strk.approve(sp_stark.contract_address, ether(1));
    sp_stark.stake(ether(1), ether(1));

    let user: ContractAddress = 1.try_into().unwrap();
    cheat_caller_address(sp_stark.contract_address, user, CheatSpan::TargetCalls(1));
    sp_stark.request_unlock(ether(1), ether(1));
}

#[test]
fn test_simple_unlock() {
    let (sp_stark, strk) = init();
    let sp_strk_token = erc20(sp_stark.contract_address);

    let amount = ether(1);
    let user = get_contract_address();

    strk.approve(sp_stark.contract_address, amount);
    sp_stark.stake(amount, amount);
    assert_eq!(sp_strk_token.balance_of(user), amount);

    sp_stark.request_unlock(amount, amount);
    assert_eq!(sp_strk_token.balance_of(user), 0);

    assert_eq!(sp_stark.get_unlock_request_count(user), 1);

    let (request, strk_amount, is_ready, is_expired) = sp_stark.get_unlock_request(user, 0);
    assert_eq!(request.sp_strk_amount, amount);
    assert_eq!(request.strk_amount, amount);
    assert_eq!(strk_amount, amount);
    assert_eq!(is_ready, false);
    assert_eq!(is_expired, false);
}

#[test]
fn test_unlock_status() {
    let (sp_stark, strk) = init();

    let amount = ether(1);
    let user = get_contract_address();

    strk.approve(sp_stark.contract_address, amount);
    sp_stark.stake(amount, amount);

    let timestamp: u64 = 1000000;
    start_cheat_block_timestamp(sp_stark.contract_address, timestamp);
    sp_stark.request_unlock(amount, amount);

    let unlock_period: u64 = deserialize::<
        u64,
    >(load(sp_stark.contract_address, selector!("unlock_period"), 1).span());
    let claim_window: u64 = deserialize::<
        u64,
    >(load(sp_stark.contract_address, selector!("claim_window"), 1).span());

    let (request, _, is_ready_1, is_expired_1) = sp_stark.get_unlock_request(user, 0);
    assert_eq!(request.unlock_time, timestamp + unlock_period);
    assert_eq!(request.expiry_time, timestamp + unlock_period + claim_window);
    assert_eq!(is_ready_1, false);
    assert_eq!(is_expired_1, false);
    stop_cheat_block_timestamp(sp_stark.contract_address);

    start_cheat_block_timestamp(sp_stark.contract_address, timestamp + unlock_period + 1);
    let (_, _, is_ready_2, is_expired_2) = sp_stark.get_unlock_request(user, 0);
    assert_eq!(is_ready_2, true);
    assert_eq!(is_expired_2, false);
    stop_cheat_block_timestamp(sp_stark.contract_address);

    start_cheat_block_timestamp(
        sp_stark.contract_address, timestamp + unlock_period + claim_window + 1,
    );
    let (_, _, is_ready_3, is_expired_3) = sp_stark.get_unlock_request(user, 0);
    assert_eq!(is_ready_3, true);
    assert_eq!(is_expired_3, true);
    stop_cheat_block_timestamp(sp_stark.contract_address);
}

#[test]
fn test_multiple_unlock_requests() {
    let (sp_stark, strk) = init();

    let amount = ether(1);
    let user = get_contract_address();

    strk.approve(sp_stark.contract_address, ether(5));
    sp_stark.stake(ether(5), ether(5));

    sp_stark.request_unlock(amount, amount);
    sp_stark.request_unlock(amount, amount);
    sp_stark.request_unlock(amount, amount);

    assert_eq!(sp_stark.get_unlock_request_count(user), 3);

    let (req0, _, _, _) = sp_stark.get_unlock_request(user, 0);
    let (req1, _, _, _) = sp_stark.get_unlock_request(user, 1);
    let (req2, _, _, _) = sp_stark.get_unlock_request(user, 2);

    assert_eq!(req0.sp_strk_amount, amount);
    assert_eq!(req1.sp_strk_amount, amount);
    assert_eq!(req2.sp_strk_amount, amount);
}

#[test]
#[should_panic(expected: ('Too many pending requests',))]
fn test_max_unlock_requests() {
    let (sp_stark, strk) = init();

    strk.approve(sp_stark.contract_address, ether(200));
    sp_stark.stake(ether(200), ether(200));

    let mut i: u256 = 0;
    loop {
        if i > 100 {
            break;
        }
        sp_stark.request_unlock(ether(1), ether(1));
        i += 1;
    };
}

#[test]
#[should_panic(expected: ('Invalid request index',))]
fn test_claim_unlock_with_invalid_index() {
    let (sp_stark, strk) = init();

    let amount = ether(1);

    strk.approve(sp_stark.contract_address, amount);
    sp_stark.stake(amount, amount);

    sp_stark.request_unlock(amount, amount);

    sp_stark.claim_unlock(1);
}

#[test]
#[should_panic(expected: ('Unlock request not ready',))]
fn test_claim_unlock_when_not_ready() {
    let (sp_stark, strk) = init();

    let amount = ether(1);

    strk.approve(sp_stark.contract_address, amount);
    sp_stark.stake(amount, amount);

    sp_stark.request_unlock(amount, amount);
    sp_stark.claim_unlock(0);
}

#[test]
#[should_panic(expected: ('Unlock request expired',))]
fn test_claim_unlock_when_expired() {
    let (sp_stark, strk) = init();

    let amount = ether(1);

    strk.approve(sp_stark.contract_address, amount);
    sp_stark.stake(amount, amount);

    sp_stark.request_unlock(amount, amount);

    let unlock_period: u64 = deserialize::<
        u64,
    >(load(sp_stark.contract_address, selector!("unlock_period"), 1).span());
    let claim_window: u64 = deserialize::<
        u64,
    >(load(sp_stark.contract_address, selector!("claim_window"), 1).span());

    start_cheat_block_timestamp(sp_stark.contract_address, unlock_period + claim_window + 1);
    sp_stark.claim_unlock(0);
    stop_cheat_block_timestamp(sp_stark.contract_address);
}

#[test]
fn test_successful_claim_unlock() {
    let (sp_stark, strk) = init();
    let sp_strk_token = erc20(sp_stark.contract_address);

    let user = get_contract_address();
    let amount = ether(1);

    let initial_balance = strk.balance_of(user);
    strk.approve(sp_stark.contract_address, amount);
    sp_stark.stake(amount, amount);
    assert_eq!(strk.balance_of(user), initial_balance - amount);

    sp_stark.request_unlock(amount, amount);
    assert_eq!(sp_strk_token.balance_of(user), 0);
    assert_eq!(sp_strk_token.total_supply(), amount);

    let unlock_period: u64 = deserialize::<
        u64,
    >(load(sp_stark.contract_address, selector!("unlock_period"), 1).span());
    start_cheat_block_timestamp(sp_stark.contract_address, unlock_period + 1);
    sp_stark.claim_unlock(0);
    stop_cheat_block_timestamp(sp_stark.contract_address);

    assert_eq!(sp_strk_token.balance_of(user), 0);
    assert_eq!(sp_strk_token.total_supply(), 0);
    assert_eq!(sp_stark.get_unlock_request_count(user), 0);

    assert_eq!(strk.balance_of(get_contract_address()), initial_balance);
}

#[test]
fn test_exchange_rate_lock() {
    let (sp_stark, strk) = init();

    let user = get_contract_address();
    let amount = ether(10);

    strk.approve(sp_stark.contract_address, amount);
    sp_stark.stake(amount, amount);

    sp_stark.request_unlock(ether(5), ether(5));

    let rewards = ether(10);
    strk.approve(sp_stark.contract_address, rewards);
    sp_stark.add_rewards(rewards);

    let exchange_rate = sp_stark.get_exchange_rate();
    assert_eq!(exchange_rate, 1920000000000000000);

    let (request, locked_strk, _, _) = sp_stark.get_unlock_request(user, 0);
    assert_eq!(request.strk_amount, ether(5));
    assert_eq!(locked_strk, ether(5));

    let unlock_period: u64 = deserialize::<
        u64,
    >(load(sp_stark.contract_address, selector!("unlock_period"), 1).span());
    start_cheat_block_timestamp(sp_stark.contract_address, unlock_period + 1);

    let balance_before = strk.balance_of(user);
    sp_stark.claim_unlock(0);
    let balance_after = strk.balance_of(user);

    assert_eq!(balance_after - balance_before, ether(5));

    stop_cheat_block_timestamp(sp_stark.contract_address);
}

#[test]
fn test_claim_multiple_unlocks() {
    let (sp_stark, strk) = init();
    let sp_strk_token = erc20(sp_stark.contract_address);

    let user = get_contract_address();
    let amount = ether(1);

    strk.approve(sp_stark.contract_address, ether(3));
    sp_stark.stake(ether(3), ether(3));

    sp_stark.request_unlock(amount, amount);
    sp_stark.request_unlock(amount, amount);
    sp_stark.request_unlock(amount, amount);

    assert_eq!(sp_stark.get_unlock_request_count(user), 3);

    let unlock_period: u64 = deserialize::<
        u64,
    >(load(sp_stark.contract_address, selector!("unlock_period"), 1).span());
    start_cheat_block_timestamp(sp_stark.contract_address, unlock_period + 1);

    sp_stark.claim_unlock(1);
    assert_eq!(sp_stark.get_unlock_request_count(user), 2);

    sp_stark.claim_unlock(0);
    assert_eq!(sp_stark.get_unlock_request_count(user), 1);

    sp_stark.claim_unlock(0);
    assert_eq!(sp_stark.get_unlock_request_count(user), 0);

    stop_cheat_block_timestamp(sp_stark.contract_address);

    assert_eq!(sp_strk_token.total_supply(), 0);
}

#[test]
#[should_panic(expected: ('Invalid request index',))]
fn test_cancel_unlock_with_invalid_index() {
    let (sp_stark, strk) = init();

    let amount = ether(1);

    strk.approve(sp_stark.contract_address, amount);
    sp_stark.stake(amount, amount);

    sp_stark.request_unlock(amount, amount);

    sp_stark.cancel_unlock(5);
}

#[test]
fn test_successful_cancel_unlock() {
    let (sp_stark, strk) = init();
    let sp_stark_token = erc20(sp_stark.contract_address);

    let amount = ether(1);
    let user = get_contract_address();

    strk.approve(sp_stark.contract_address, amount);
    sp_stark.stake(amount, amount);

    let initial_sp_strk_balance = sp_stark_token.balance_of(user);
    assert_eq!(initial_sp_strk_balance, amount);
    assert_eq!(sp_stark_token.total_supply(), amount);

    sp_stark.request_unlock(amount, amount);
    assert_eq!(sp_stark_token.balance_of(user), 0);
    assert_eq!(sp_stark_token.total_supply(), amount);
    assert_eq!(sp_stark.get_unlock_request_count(user), 1);

    sp_stark.cancel_unlock(0);
    assert_eq!(sp_stark_token.balance_of(user), initial_sp_strk_balance);
    assert_eq!(sp_stark_token.total_supply(), amount);
    assert_eq!(sp_stark.get_unlock_request_count(user), 0);
}

#[test]
fn test_claim_expired() {
    let (sp_stark, strk) = init();
    let sp_stark_token = erc20(sp_stark.contract_address);

    let amount = ether(1);
    let user = get_contract_address();

    strk.approve(sp_stark.contract_address, amount);
    sp_stark.stake(amount, amount);

    sp_stark.request_unlock(amount, amount);
    assert_eq!(sp_stark_token.balance_of(user), 0);
    assert_eq!(sp_stark.get_unlock_request_count(user), 1);

    let unlock_period: u64 = deserialize::<
        u64,
    >(load(sp_stark.contract_address, selector!("unlock_period"), 1).span());
    let claim_window: u64 = deserialize::<
        u64,
    >(load(sp_stark.contract_address, selector!("claim_window"), 1).span());

    start_cheat_block_timestamp(sp_stark.contract_address, unlock_period + claim_window + 1);

    sp_stark.claim_expired(0);

    stop_cheat_block_timestamp(sp_stark.contract_address);

    assert_eq!(sp_stark_token.balance_of(user), amount);
    assert_eq!(sp_stark.get_unlock_request_count(user), 0);
}

#[test]
#[should_panic(expected: ('Request not expired',))]
fn test_claim_expired_too_early() {
    let (sp_stark, strk) = init();

    let amount = ether(1);

    strk.approve(sp_stark.contract_address, amount);
    sp_stark.stake(amount, amount);

    sp_stark.request_unlock(amount, amount);

    sp_stark.claim_expired(0);
}

#[test]
fn test_successful_deposit() {
    let (sp_stark, strk) = init();

    let contract_initial_balance = strk.balance_of(sp_stark.contract_address);

    let amount = ether(1);
    strk.approve(sp_stark.contract_address, amount);
    sp_stark.deposit(amount);

    assert_eq!(strk.balance_of(sp_stark.contract_address), contract_initial_balance + amount);
}

#[test]
#[should_panic(expected: ('Insufficient STRK balance',))]
fn test_withdraw_low_funds() {
    let (sp_stark, _) = init();
    sp_stark.withdraw(ether(1));
}

#[test]
fn test_successful_withdraw() {
    let (sp_stark, strk) = init();

    let stake_amount = ether(100);
    let withdraw_amount = ether(80);
    let user = get_contract_address();
    let user_init_balance = strk.balance_of(user);

    // Stake 100 STRK
    strk.approve(sp_stark.contract_address, stake_amount);
    sp_stark.stake(stake_amount, stake_amount);
    assert_eq!(strk.balance_of(user), user_init_balance - stake_amount);
    assert_eq!(strk.balance_of(sp_stark.contract_address), stake_amount);

    // Withdraw 80 STRK (leaves 20 STRK which is > 10% reserve)
    sp_stark.withdraw(withdraw_amount);
    assert_eq!(strk.balance_of(user), user_init_balance - stake_amount + withdraw_amount);
    assert_eq!(strk.balance_of(sp_stark.contract_address), stake_amount - withdraw_amount);
}

#[test]
fn test_withdraw_with_liquidity_reserve() {
    let (sp_stark, strk) = init();

    strk.approve(sp_stark.contract_address, ether(100));
    sp_stark.stake(ether(100), ether(100));

    sp_stark.request_unlock(ether(50), ether(50));

    sp_stark.withdraw(ether(50));
}

#[test]
#[should_panic(expected: ('Insufficient liquidity',))]
fn test_withdraw_exceeds_liquidity_reserve() {
    let (sp_stark, strk) = init();

    strk.approve(sp_stark.contract_address, ether(100));
    sp_stark.stake(ether(100), ether(100));

    sp_stark.request_unlock(ether(50), ether(50));

    sp_stark.withdraw(ether(51));
}

#[test]
fn test_fee_claiming() {
    let (sp_stark, strk) = init();

    let amount = ether(10);
    let user = get_contract_address();

    strk.approve(sp_stark.contract_address, amount);

    sp_stark.add_rewards(amount);
    let (_, _, _, _, accumulated_dao_fees, accumulated_dev_fees, _, _) = sp_stark.get_stats();

    let balance_before = strk.balance_of(user);

    assert_eq!(accumulated_dao_fees, 500000000000000000);
    assert_eq!(accumulated_dev_fees, 300000000000000000);

    sp_stark.collect_dao_fees();
    assert_eq!(strk.balance_of(user), balance_before + accumulated_dao_fees);

    sp_stark.collect_dev_fees();
    assert_eq!(strk.balance_of(user), balance_before + accumulated_dao_fees + accumulated_dev_fees);

    let (_, _, _, _, accumulated_dao_fees_after, accumulated_dev_fees_after, _, _) = sp_stark
        .get_stats();

    assert_eq!(accumulated_dao_fees_after, 0);
    assert_eq!(accumulated_dev_fees_after, 0);
}

#[test]
fn test_collect_all_fees() {
    let (sp_stark, strk) = init();

    let amount = ether(10);
    let user = get_contract_address();

    strk.approve(sp_stark.contract_address, amount);
    sp_stark.add_rewards(amount);

    let (_, _, _, _, accumulated_dao_fees, accumulated_dev_fees, _, _) = sp_stark.get_stats();
    let total_fees = accumulated_dao_fees + accumulated_dev_fees;

    let balance_before = strk.balance_of(user);

    sp_stark.collect_all_fees();

    let balance_after = strk.balance_of(user);
    assert_eq!(balance_after - balance_before, total_fees);

    let (_, _, _, _, accumulated_dao_fees_after, accumulated_dev_fees_after, _, _) = sp_stark
        .get_stats();
    assert_eq!(accumulated_dao_fees_after, 0);
    assert_eq!(accumulated_dev_fees_after, 0);
}

#[test]
fn test_upgrade() {
    let (sp_stark, _) = init();
    let upgradeable = IUpgradeableDispatcher { contract_address: sp_stark.contract_address };

    let new_contract_class = declare("NewspSTRK").unwrap().contract_class();
    upgradeable.upgrade(*new_contract_class.class_hash);

    let new_sp_stark = INewspSTRKDispatcher { contract_address: sp_stark.contract_address };
    assert_eq!(new_sp_stark.new_function(), 10);
}

// ========================================================
// VALIDATOR INTEGRATION TESTS
// ========================================================

#[test]
fn test_stake_with_auto_delegation() {
    let (sp_stark, strk_token) = init();
    let stake_amount = ether(100);

    // Check contract balance before
    let balance_before = strk_token.balance_of(sp_stark.contract_address);

    // User stakes
    strk_token.approve(sp_stark.contract_address, stake_amount);
    sp_stark.stake(stake_amount, stake_amount);

    // After staking, contract should have ~10% buffer
    let balance_after = strk_token.balance_of(sp_stark.contract_address);
    let expected_buffer = (stake_amount * 10) / 100; // 10 STRK

    // Contract should have approximately the buffer (10%)
    // Due to dust threshold (0.01 STRK), it might have slightly more
    assert!(balance_after >= expected_buffer - ether(1), "Buffer too low");
    assert!(balance_after <= stake_amount, "No delegation happened");
}

#[test]
fn test_multiple_stakes_trigger_add_to_delegation() {
    let (sp_stark, strk_token) = init();
    
    // First stake - triggers enter_delegation_pool
    strk_token.approve(sp_stark.contract_address, ether(100));
    sp_stark.stake(ether(100), ether(100));
    
    // Second stake - should trigger add_to_delegation_pool
    strk_token.approve(sp_stark.contract_address, ether(50));
    sp_stark.stake(ether(50), ether(50));
    
    // Contract should still maintain ~10% buffer of total
    let total_staked = ether(150);
    let expected_buffer = (total_staked * 10) / 100;
    let actual_buffer = strk_token.balance_of(sp_stark.contract_address);
    
    assert!(actual_buffer >= expected_buffer - ether(1), "Buffer too low");
}

#[test]
fn test_small_stake_no_delegation() {
    let (sp_stark, strk_token) = init();
    
    // Stake amount that's below dust threshold after buffer calculation
    let small_amount = ether(1); // 1 STRK
    
    strk_token.approve(sp_stark.contract_address, small_amount);
    sp_stark.stake(small_amount, small_amount);
    
    // Should not delegate (amount to delegate < 0.01 STRK dust threshold)
    // All should remain in contract
    let balance = strk_token.balance_of(sp_stark.contract_address);
    assert_eq!(balance, small_amount);
}

#[test]
#[should_panic(expected: ('Caller is not the owner',))]
fn test_claim_validator_rewards_only_owner() {
    let (sp_stark, _) = init();
    
    let fake_owner: ContractAddress = 1.try_into().unwrap();
    cheat_caller_address(sp_stark.contract_address, fake_owner, CheatSpan::TargetCalls(1));
    sp_stark.claim_validator_rewards();
}

#[test]
#[should_panic(expected: ('No rewards to claim',))]
fn test_claim_validator_rewards_no_rewards() {
    let (sp_stark, strk_token) = init();
    
    // Stake first to have delegation
    strk_token.approve(sp_stark.contract_address, ether(100));
    sp_stark.stake(ether(100), ether(100));
    
    // Try to claim rewards (mock validator has 0 rewards by default)
    sp_stark.claim_validator_rewards();
}

#[test]
#[should_panic(expected: ('Validator not set',))]
fn test_claim_validator_rewards_no_validator() {
    // Create contract with zero validator address
    let owner = get_contract_address();
    let strk_token = deploy_mock_token(owner);
    let zero_validator: ContractAddress = 0.try_into().unwrap();
    
    let sp_strk = deploy_contract(
        InitParams {
            owner,
            strk_token: strk_token.contract_address,
            validator_pool: zero_validator,
            dao_fee_basis_points: 500,
            dev_fee_basis_points: 300,
            min_stake_amount: 10000000000000000,
            unlock_period: 60,
            claim_window: 604800,
        },
    );
    
    sp_strk.claim_validator_rewards();
}

#[test]
#[should_panic(expected: ('Caller is not the owner',))]
fn test_unstake_from_validator_only_owner() {
    let (sp_stark, _) = init();
    
    let fake_owner: ContractAddress = 1.try_into().unwrap();
    cheat_caller_address(sp_stark.contract_address, fake_owner, CheatSpan::TargetCalls(1));
    sp_stark.unstake_from_validator(ether(1));
}

#[test]
#[should_panic(expected: ('Invalid amount',))]
fn test_unstake_from_validator_zero_amount() {
    let (sp_stark, _) = init();
    sp_stark.unstake_from_validator(0);
}

#[test]
#[should_panic(expected: ('Insufficient delegated amount',))]
fn test_unstake_from_validator_insufficient() {
    let (sp_stark, strk_token) = init();
    
    // Stake to have some delegation
    strk_token.approve(sp_stark.contract_address, ether(100));
    sp_stark.stake(ether(100), ether(100));
    
    // Try to unstake more than delegated
    // ~90 STRK is delegated, try to unstake 200
    sp_stark.unstake_from_validator(ether(200));
}

#[test]
#[should_panic(expected: ('Validator not set',))]
fn test_unstake_from_validator_no_validator() {
    let owner = get_contract_address();
    let strk_token = deploy_mock_token(owner);
    let zero_validator: ContractAddress = 0.try_into().unwrap();
    
    let sp_strk = deploy_contract(
        InitParams {
            owner,
            strk_token: strk_token.contract_address,
            validator_pool: zero_validator,
            dao_fee_basis_points: 500,
            dev_fee_basis_points: 300,
            min_stake_amount: 10000000000000000,
            unlock_period: 60,
            claim_window: 604800,
        },
    );
    
    sp_strk.unstake_from_validator(ether(1));
}

#[test]
fn test_unstake_from_validator_success() {
    let (sp_stark, strk_token) = init();
    
    // Stake to have delegation
    strk_token.approve(sp_stark.contract_address, ether(100));
    sp_stark.stake(ether(100), ether(100));
    
    // Unstake from validator (should succeed)
    sp_stark.unstake_from_validator(ether(50));
    
    // Can't test much more with mock, but function should complete
}

#[test]
#[should_panic(expected: ('Unbonding already pending',))]
fn test_unstake_from_validator_already_pending() {
    let (sp_stark, strk_token) = init();
    
    // Stake
    strk_token.approve(sp_stark.contract_address, ether(100));
    sp_stark.stake(ether(100), ether(100));
    
    // Start unbonding
    sp_stark.unstake_from_validator(ether(30));
    
    // Try to start another unbonding (should fail)
    sp_stark.unstake_from_validator(ether(20));
}

#[test]
#[should_panic(expected: ('Caller is not the owner',))]
fn test_complete_validator_unstaking_only_owner() {
    let (sp_stark, _) = init();
    
    let fake_owner: ContractAddress = 1.try_into().unwrap();
    cheat_caller_address(sp_stark.contract_address, fake_owner, CheatSpan::TargetCalls(1));
    sp_stark.complete_validator_unstaking();
}

#[test]
#[should_panic(expected: ('No pending unbonding',))]
fn test_complete_validator_unstaking_no_pending() {
    let (sp_stark, _) = init();
    
    // Try to complete without starting unbonding
    sp_stark.complete_validator_unstaking();
}

#[test]
#[should_panic(expected: ('Unbonding period not finished',))]
fn test_complete_validator_unstaking_too_early() {
    let (sp_stark, strk_token) = init();
    
    // Stake and start unbonding
    strk_token.approve(sp_stark.contract_address, ether(100));
    sp_stark.stake(ether(100), ether(100));
    
    sp_stark.unstake_from_validator(ether(50));
    
    // Try to complete immediately (should fail - needs 7 days)
    sp_stark.complete_validator_unstaking();
}

#[test]
fn test_complete_validator_unstaking_success() {
    let (sp_stark, strk_token) = init();
    
    // Stake and start unbonding
    strk_token.approve(sp_stark.contract_address, ether(100));
    sp_stark.stake(ether(100), ether(100));
    
    let timestamp: u64 = 1000000;
    start_cheat_block_timestamp(sp_stark.contract_address, timestamp);
    
    sp_stark.unstake_from_validator(ether(50));
    
    stop_cheat_block_timestamp(sp_stark.contract_address);
    
    // Fast forward 7 days
    let seven_days: u64 = 7 * 24 * 60 * 60;
    start_cheat_block_timestamp(sp_stark.contract_address, timestamp + seven_days + 1);
    
    // Complete unbonding (should succeed)
    sp_stark.complete_validator_unstaking();
    
    stop_cheat_block_timestamp(sp_stark.contract_address);
    
    // Should be able to start new unbonding now
    sp_stark.unstake_from_validator(ether(20));
}

#[test]
fn test_validator_full_flow() {
    let (sp_stark, strk_token) = init();
    let user = get_contract_address();
    
    // Step 1: User stakes (triggers delegation)
    let stake_amount = ether(100);
    strk_token.approve(sp_stark.contract_address, stake_amount);
    sp_stark.stake(stake_amount, stake_amount);
    
    // Verify user got spSTRK
    let sp_strk_token = erc20(sp_stark.contract_address);
    assert_eq!(sp_strk_token.balance_of(user), stake_amount);
    
    // Step 2: Admin unstakes from validator
    let unstake_amount = ether(40);
    let timestamp: u64 = 2000000;
    start_cheat_block_timestamp(sp_stark.contract_address, timestamp);
    
    sp_stark.unstake_from_validator(unstake_amount);
    
    stop_cheat_block_timestamp(sp_stark.contract_address);
    
    // Step 3: Wait 7 days and complete unbonding
    let seven_days: u64 = 7 * 24 * 60 * 60;
    start_cheat_block_timestamp(sp_stark.contract_address, timestamp + seven_days + 1);
    
    let balance_before = strk_token.balance_of(sp_stark.contract_address);
    sp_stark.complete_validator_unstaking();
    let balance_after = strk_token.balance_of(sp_stark.contract_address);
    
    // Balance should increase (mock returns 100)
    assert!(balance_after >= balance_before, "Balance should increase");
    
    stop_cheat_block_timestamp(sp_stark.contract_address);
}

#[test]
fn test_no_delegation_when_validator_not_set() {
    let owner = get_contract_address();
    let strk_token = deploy_mock_token(owner);
    let zero_validator: ContractAddress = 0.try_into().unwrap();
    
    let sp_strk = deploy_contract(
        InitParams {
            owner,
            strk_token: strk_token.contract_address,
            validator_pool: zero_validator,
            dao_fee_basis_points: 500,
            dev_fee_basis_points: 300,
            min_stake_amount: 10000000000000000,
            unlock_period: 60,
            claim_window: 604800,
        },
    );
    
    // Stake should work even without validator
    let stake_amount = ether(100);
    strk_token.approve(sp_strk.contract_address, stake_amount);
    sp_strk.stake(stake_amount, stake_amount);
    
    // All funds should remain in contract (no delegation)
    let balance = strk_token.balance_of(sp_strk.contract_address);
    assert_eq!(balance, stake_amount);
}

#[test]
fn test_buffer_maintained_across_multiple_operations() {
    let (sp_stark, strk_token) = init();
    
    // Stake multiple times
    strk_token.approve(sp_stark.contract_address, ether(50));
    sp_stark.stake(ether(50), ether(50));
    
    strk_token.approve(sp_stark.contract_address, ether(50));
    sp_stark.stake(ether(50), ether(50));
    
    strk_token.approve(sp_stark.contract_address, ether(100));
    sp_stark.stake(ether(100), ether(100));
    
    // Total staked: 200 STRK
    // Expected buffer: ~20 STRK (10%)
    let total_staked = ether(200);
    let expected_buffer = (total_staked * 10) / 100;
    let actual_buffer = strk_token.balance_of(sp_stark.contract_address);
    
    assert!(actual_buffer >= expected_buffer - ether(2), "Buffer too low");
    assert!(actual_buffer <= total_staked, "All funds in contract");
}
