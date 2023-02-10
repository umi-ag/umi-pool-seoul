
module umi_pool::asset {
    use aptos_framework::coin;

    use umi_pool::math;
    use umi_pool::decimal;
    use umi_pool::decimal::Decimal;
    use umi_pool::coin_info;
    use umi_pool::coin_info::CoinInfo;

    #[test_only] use std::string;

    const RED_DECIMAL: u8 = 9;
    const BLUE_DECIMAL: u8 = 8;
    const GREEN_DECIMAL: u8 = 6;

    #[derive(Debug)]
    struct Asset<phantom X> has copy, drop {
        amount: u64,
        coin: CoinInfo<X>
    }

    public fun new<X>(amount: u64, coin: &CoinInfo<X>): Asset<X> {
        Asset<X> { amount, coin: *coin }
    }

    public fun from_u64<X>(value: u64, coin: &CoinInfo<X>): Asset<X> {
        let decimals = coin_info::get_decimals(coin);
        let amount = math::expand_to_decimals(value, decimals);
        Asset<X> { amount, coin: *coin }
    }

    public fun from_decimal<X>(value: &Decimal, coin: &CoinInfo<X>): Asset<X> {
        let decimals = coin_info::get_decimals(coin);
        let v = decimal::expand_to_decimals(value, decimals);
        let amount = decimal::to_u64(v);

        Asset<X> { amount, coin: *coin }
    }

    public fun from_coin<X>(coin_amount: &coin::Coin<X>, coininfo: &CoinInfo<X>): Asset<X> {
        let amount = coin::value(coin_amount);
        Asset<X> { amount, coin: *coininfo }
    }

    public fun to_u64<X>(asset: Asset<X>): u64 {
        asset.amount
    }

    public fun to_decimal<X>(asset: Asset<X>): Decimal {
        let decimals = coin_info::get_decimals(&asset.coin);
        let amount = (asset.amount as u128);
        decimal::new(amount, decimals, false)
    }

    #[test]
    fun test_asset() {
        use umi_pool::coin_list;

        let coin_red = coin_info::new<coin_list::RED>(
            string::utf8(b"redcoin"),
            string::utf8(b"RED"),
            RED_DECIMAL,
            true,
        );

        let coin_blue = coin_info::new<coin_list::BLUE>(
            string::utf8(b"bluecoin"),
            string::utf8(b"BLUE"),
            BLUE_DECIMAL,
            true,
        );

        let asset_red = from_decimal<coin_list::RED>(&decimal::new(114514, 3, false), &coin_red);
        let asset_blue = from_decimal<coin_list::BLUE>(&decimal::new(100, 0, false), &coin_blue);

        assert!(to_u64(asset_red) == 114514000000, 0);
        assert!(to_u64(asset_blue) == 10000000000, 0);
    }

    #[test]
    fun test_from_decimal() {
        use umi_pool::coin_list;

        let value = decimal::from_u64(math::expand_to_decimals(4004, 0));
        let coin_red = coin_info::new<coin_list::RED>(
            string::utf8(b"redcoin"),
            string::utf8(b"RED"),
            6,
            true,
        );

        let asset = from_decimal(&value, &coin_red);

        assert!(to_u64(asset) == 4004000000, 0);
    }

    #[test]
    fun test_to_decimal() {
        use std::debug;
        use umi_pool::coin_list;

        let coin_red = coin_info::new<coin_list::RED>(
            string::utf8(b"redcoin"),
            string::utf8(b"RED"),
            RED_DECIMAL,
            true,
        );

        let coin_blue = coin_info::new<coin_list::BLUE>(
            string::utf8(b"bluecoin"),
            string::utf8(b"BLUE"),
            BLUE_DECIMAL,
            true,
        );

        let asset_red = from_decimal<coin_list::RED>(&decimal::new(114514, 3, false), &coin_red);
        let asset_blue = from_decimal<coin_list::BLUE>(&decimal::new(100, 0, false), &coin_blue);

        debug::print(&22222222);
        assert!(decimal::equal(&to_decimal(asset_red), &decimal::new(114514, 3, false)), 0);
        debug::print(&to_decimal(asset_blue));
        debug::print(&22222225);

        debug::print(&decimal::new(114514,3,false));
        debug::print(&decimal::new(105,2,false));


        assert!(decimal::equal(&to_decimal(asset_blue), &decimal::new(100, 0, false)), 0);
    }
}
