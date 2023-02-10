module umi_pool::coin_info {
    use std::string;

    use aptos_framework::coin;

    #[derive(Debug)]
    struct CoinInfo<phantom X> has copy, drop, store {
        name: string::String,
        symbol: string::String,
        decimals: u8,
        monitor_supply: bool,
    }

    public fun new<X>(
        name: string::String,
        symbol: string::String,
        decimals: u8,
        monitor_supply: bool,
    ): CoinInfo<X> {
        CoinInfo<X> { name, symbol, decimals, monitor_supply }
    }

    public fun initialize<X>(admin: &signer, coin: &CoinInfo<X>)
    : (coin::BurnCapability<X>, coin::FreezeCapability<X>, coin::MintCapability<X>)
    {
        let (burn_cap, freeze_cap, mint_cap) = coin::initialize<X>(
            admin,
            coin.name,
            coin.symbol,
            coin.decimals,
            coin.monitor_supply,
        );
        (burn_cap, freeze_cap, mint_cap)
    }

    public fun get_decimals<X>(coin: &CoinInfo<X>): u8 {
        coin.decimals
    }
}
