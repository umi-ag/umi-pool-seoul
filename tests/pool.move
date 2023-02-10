#[test_only]
module umi_pool::test_pool {
    use std::debug;
    use std::signer;
    use aptos_framework::coin;

    use umi_pool::coin_list::{Self, mint_to_wallet, check_and_deposit};
    use umi_pool::coin_list::{BTC, ETH, USDI};
    use umi_pool::pool;
    use umi_pool::math::expand_to_decimals;

    #[test(admin = @umi_pool)]
    fun test_register(admin: signer)
    {
        pool::init_pot<BTC>(&admin);

        pool::set_config_pot<BTC>(
            &admin,
            expand_to_decimals(20, 6),

            expand_to_decimals(5, 6),
            expand_to_decimals(3, 3),
            expand_to_decimals(1, 3),
        );
    }

    #[test_only]
    fun debug_balance<X>(addr: address)
    {
        debug::print(&coin::balance<X>(addr));
    }

    #[test(admin = @umi_pool, _token_owner = @0x02, _treasury = @0x21, alice = @0x41)]
    fun test_alice_mint_and_burn_usdi(admin: signer, _token_owner: signer, _treasury: signer, alice: signer)
    {
        use aptos_framework::aptos_account;

        pool::init_pot<BTC>(&admin);
        pool::set_config_pot<BTC>(
            &admin,
            expand_to_decimals(20, 6),
            expand_to_decimals(5, 6),
            expand_to_decimals(3, 3),
            expand_to_decimals(1, 3),
        );

        aptos_account::create_account(signer::address_of(&alice));

        coin_list::init_coin<USDI>(&admin, b"USDI", b"USDI", 6);
        coin_list::init_coin<BTC>(&admin, b"bitcoin", b"BTC", 6);

        mint_to_wallet<BTC>(&alice, 100);
        debug_balance<BTC>(signer::address_of(&alice));

        pool::mint_x_to_u<BTC, USDI>(&alice, 10);
        debug_balance<BTC>(signer::address_of(&alice));
        debug_balance<USDI>(signer::address_of(&alice));

        pool::burn_u_to_x<USDI, BTC>(&alice, 5);
        debug_balance<BTC>(signer::address_of(&alice));
        debug_balance<USDI>(signer::address_of(&alice));
    }

    #[test(admin = @umi_pool, _token_owner = @0x02, _treasury = @0x21, alice = @0x41)]
    fun test_alice_swap(admin: signer, _token_owner: signer, _treasury: signer, alice: signer)
    {
        use aptos_framework::aptos_account;

        pool::init_pot<BTC>(&admin);
        pool::set_config_pot<BTC>(
            &admin,
            expand_to_decimals(20, 6),
            expand_to_decimals(5, 6),
            expand_to_decimals(3, 3),
            expand_to_decimals(1, 3),
        );

        pool::init_pot<ETH>(&admin);
        pool::set_config_pot<ETH>(
            &admin,
            expand_to_decimals(20, 6),
            expand_to_decimals(5, 6),
            expand_to_decimals(3, 3),
            expand_to_decimals(1, 3),
        );

        aptos_account::create_account(signer::address_of(&alice));

        coin_list::init_coin<USDI>(&admin, b"USDI", b"USDI", 6);
        coin_list::init_coin<BTC>(&admin, b"bitcoin", b"BTC", 6);
        coin_list::init_coin<ETH>(&admin, b"ethereum", b"ETH", 8);

        mint_to_wallet<BTC>(&alice, 100);
        pool::mint_x_to_u<BTC, USDI>(&alice, 10);
        mint_to_wallet<ETH>(&alice, 100);
        pool::mint_x_to_u<ETH, USDI>(&alice, 10);

        debug_balance<BTC>(signer::address_of(&alice));
        debug_balance<ETH>(signer::address_of(&alice));

        pool::swap_x_to_y<BTC, ETH>(&alice, 40);
        debug_balance<BTC>(signer::address_of(&alice));
        debug_balance<ETH>(signer::address_of(&alice));
    }

    #[test(admin = @umi_pool, _token_owner = @0x02, _treasury = @0x21, alice = @0x41)]
    fun test_alice_swap_direct(admin: signer, _token_owner: signer, _treasury: signer, alice: signer)
    {
        use aptos_framework::aptos_account;

        pool::init_pot<BTC>(&admin);
        pool::set_config_pot<BTC>(
            &admin,
            expand_to_decimals(20, 6),
            expand_to_decimals(5, 6),
            expand_to_decimals(3, 3),
            expand_to_decimals(1, 3),
        );

        pool::init_pot<ETH>(&admin);
        pool::set_config_pot<ETH>(
            &admin,
            expand_to_decimals(20, 6),
            expand_to_decimals(5, 6),
            expand_to_decimals(3, 3),
            expand_to_decimals(1, 3),
        );

        aptos_account::create_account(signer::address_of(&alice));

        coin_list::init_coin<USDI>(&admin, b"USDI", b"USDI", 6);
        coin_list::init_coin<BTC>(&admin, b"bitcoin", b"BTC", 6);
        coin_list::init_coin<ETH>(&admin, b"ethereum", b"ETH", 8);

        mint_to_wallet<BTC>(&alice, 100);
        pool::mint_x_to_u<BTC, USDI>(&alice, 10);
        mint_to_wallet<ETH>(&alice, 100);
        pool::mint_x_to_u<ETH, USDI>(&alice, 10);

        let coin_x = coin::withdraw<ETH>(&alice, 30);
        let coin_y = pool::swap_direct<ETH, BTC>(coin_x);
        check_and_deposit(&alice, coin_y);
        debug_balance<BTC>(signer::address_of(&alice));
        debug_balance<ETH>(signer::address_of(&alice));
        debug_balance<USDI>(signer::address_of(&alice));

        let coin_x = coin::withdraw<ETH>(&alice, 30);
        let coin_y = pool::swap_direct<ETH, USDI>(coin_x);
        check_and_deposit(&alice, coin_y);
        debug_balance<BTC>(signer::address_of(&alice));
        debug_balance<ETH>(signer::address_of(&alice));
        debug_balance<USDI>(signer::address_of(&alice));

        let coin_x = coin::withdraw<USDI>(&alice, 30);
        let coin_y = pool::swap_direct<USDI, ETH>(coin_x);
        check_and_deposit(&alice, coin_y);
        debug_balance<BTC>(signer::address_of(&alice));
        debug_balance<ETH>(signer::address_of(&alice));
        debug_balance<USDI>(signer::address_of(&alice));
    }
}
