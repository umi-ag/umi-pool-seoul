// https://github.com/hippospace/aptos-coin-list/blob/db87f3e7136f1119e299c70130f6fff9631cfa98/sources/devnet_coins.move
module umi_pool::coin_list {
    use std::signer;
    use std::string::{utf8};

    use aptos_std::type_info;
    use aptos_framework::coin;

    const MODULE_ADMIN: address = @umi_pool;

    struct RED {}
    struct BLUE {}
    struct GREEN {}

    struct BTC {}
    struct ETH {}
    struct DAI {}
    struct SOL {}
    struct USDT {}
    struct USDC {}

    struct USDI {}
    struct CUSDI {}

    struct CoinCaps<phantom T> has key {
        mint: coin::MintCapability<T>,
        freeze: coin::FreezeCapability<T>,
        burn: coin::BurnCapability<T>,
    }

    public fun initialize<TokenType>(admin: &signer, decimals: u8){
        let name = type_info::struct_name(&type_info::type_of<TokenType>());
        init_coin<TokenType>(admin, name, name, decimals)
    }

    public entry fun init_coin<CoinType>(
        admin: &signer,
        name: vector<u8>,
        symbol: vector<u8>,
        decimals: u8,
    ) {
        let (burn, freeze, mint) =
            coin::initialize<CoinType>(
                admin,
                utf8(name),
                utf8(symbol),
                decimals,
                false
            );
        move_to(admin, CoinCaps {
            mint,
            freeze,
            burn,
        });
    }

    fun check_coin_store<X>(to: &signer)
    {
        if (!coin::is_account_registered<X>(signer::address_of(to))) {
            coin::register<X>(to);
        };
    }

    public fun mint<CoinType>(amount: u64): coin::Coin<CoinType>
    acquires CoinCaps
    {
        let caps = borrow_global<CoinCaps<CoinType>>(MODULE_ADMIN);
        coin::mint(amount, &caps.mint)
    }

    public entry fun mint_to_wallet<CoinType>(user: &signer, amount: u64)
    acquires CoinCaps
    {
        let coin = mint<CoinType>(amount);
        check_coin_store<CoinType>(user);
        coin::deposit(signer::address_of(user), coin);
    }

    public entry fun burn<CoinType>(coin_tobe_burned: coin::Coin<CoinType>)
    acquires CoinCaps
    {
        let caps = borrow_global<CoinCaps<CoinType>>(MODULE_ADMIN);
        coin::burn(coin_tobe_burned, &caps.burn);
    }

    public fun check_and_deposit<X>(sender: &signer, coin: coin::Coin<X>) {
        let sender_addr = signer::address_of(sender);
        check_coin_store<X>(sender);
        coin::deposit(sender_addr, coin);
    }
}
