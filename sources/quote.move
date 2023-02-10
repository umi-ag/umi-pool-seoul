module umi_pool::quote {
    use std::signer;

    use umi_pool::decimal;
    use umi_pool::decimal::Decimal;

    const ERR_NON_POSITIVE_PRICE: u64 = 0;

    struct Price<phantom X, phantom Y> has key, copy, drop {
        price: Decimal,
    }

    public fun new<X, Y>(price: &Decimal): Price<X, Y>
    {
        Price<X, Y> {
            price: *price
        }
    }

    public entry fun get_price<X, Y>(quote: &Price<X, Y>): Decimal
    {
        quote.price
    }

    public entry fun register<X, Y>(account: &signer)
    {
        let account_addr = signer::address_of(account);
        if (!exists<Price<X, Y>>(account_addr)) {
            let price = decimal::new(1, 0, true);
            move_to(account, Price<X, Y> { price });
        };
    }

    public entry fun set_price<X, Y>(account: &signer, value: u64, decimals: u8)
    acquires Price
    {
        let price = decimal::new((value as u128), decimals, false);
        let account_addr = signer::address_of(account);
        let price_quote = borrow_global_mut<Price<X, Y>>(account_addr);
        price_quote.price = price;
    }

    #[test(account = @0x1, coin_addr = @0x2)]
    fun test_set_price(account: signer)
    acquires Price {
        use umi_pool::coin_list;

        let addr = signer::address_of(&account);
        aptos_framework::account::create_account_for_test(addr);

        register<coin_list::RED, coin_list::BLUE>(&account);
        set_price<coin_list::RED, coin_list::BLUE>(&account, 8901, 2);
    }
}