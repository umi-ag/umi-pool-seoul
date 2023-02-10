
import assert from "assert";
import fs from "fs";
import path from "path";
import { AptosAccount, AptosClient, TxnBuilderTypes, MaybeHexString, HexString, FaucetClient, Types } from "aptos";
import { excuteuTransaction, FAUCET_URL, NODE_URL, printTx, sleep, umi_pool } from "../src/utils";
import { admin, alice } from "../src/utils/accounts";
import { PrivateKeys } from '../src/types'
import yaml from 'js-yaml'


class CoinClient extends AptosClient {
  constructor() {
    super(NODE_URL);
  }

  /** Register the receiver account to receive transfers for the new coin. */
  async registerCoin(coinType: string, coinReceiver: AptosAccount): Promise<string> {
    const rawTxn = await this.generateTransaction(coinReceiver.address(), {
      function: "0x1::managed_coin::register",
      type_arguments: [coinType],
      arguments: [],
    });
    const bcsTxn = await this.signTransaction(coinReceiver, rawTxn);
    const pendingTxn = await this.submitTransaction(bcsTxn);
    return pendingTxn.hash;
  }

  /** Mints the newly created coin to a specified receiver address */
  async mintCoin(minter: AptosAccount, receiverAddress: HexString, coinType: string, amount: number | bigint): Promise<string> {
    const rawTxn = await this.generateTransaction(minter.address(), {
      function: "0x1::managed_coin::mint",
      type_arguments: [coinType],
      arguments: [receiverAddress.hex(), amount],
    });

    const bcsTxn = await this.signTransaction(minter, rawTxn);
    const pendingTxn = await this.submitTransaction(bcsTxn);

    return pendingTxn.hash;
  }

  /** Return the balance of the newly created coin */
  async getBalance(accountAddress: MaybeHexString, coinType: string): Promise<string | number> {
    try {
      const resource = await this.getAccountResource(
        accountAddress,
        `0x1::coin::CoinStore<${coinType}>`,
      );

      return parseInt((resource.data as any)["coin"]["value"]);
    } catch (_) {
      return 0;
    }
  }
}

const client = new AptosClient(NODE_URL)
const faucetClient = new FaucetClient(NODE_URL, FAUCET_URL)

await faucetClient.fundAccount(admin.address(), 5_000)


const registerCoin = async (coinType: string, account: AptosAccount) => {
  const payload: Types.EntryFunctionPayload =
  {
    'function': "0x1::managed_coin::register",
    "type_arguments": [coinType],
    "arguments": [],
  }
  console.log('payload', payload)
  const txHash = await excuteuTransaction(client, account, payload)
    .catch(e => {
      console.error(e)
    })
  printTx(txHash)
}

const initializeCoin = async (coinType: string, coin: {
  name: string,
  symbol: string,
  decimals: number,
  monitorSupply: boolean,
}) => {
  const { name, symbol, decimals, monitorSupply } = coin
  const payload: Types.EntryFunctionPayload =
  {
    'function': "0x1::managed_coin::initialize",
    "type_arguments": [coinType],
    "arguments": [name, symbol, decimals, monitorSupply],
  }
  console.log('payload', payload)
  const txHash = await excuteuTransaction(client, admin, payload)
    .catch(e => {
      console.error(e)
    })
  printTx(txHash)
}

const mintCoin = async (coinType: string, admin: AptosAccount, to: HexString, amount: number | bigint) => {
  const payload: Types.EntryFunctionPayload =
  {
    'function': "0x1::managed_coin::mint",
    "type_arguments": [coinType],
    "arguments": [to.hex(), amount],
  }
  console.log('payload', payload)
  const txHash = await excuteuTransaction(client, admin, payload)
    .catch(e => {
      console.error(e)
    })
  printTx(txHash)
}

const coinType = `${umi_pool}::coin_list::USDI`
await registerCoin(coinType, admin)
await registerCoin(coinType, alice)
await initializeCoin(coinType, {
  name: 'USDI',
  symbol: 'USDI',
  decimals: 6,
  monitorSupply: true,
})
await mintCoin(coinType, admin, alice.address(), 999999)

await sleep(3e3)
// console.log(
//   alice.address(),
//   `0x1::coin:CoinStore<${coinType}>`
// )
let r = await client.getAccountResource(
  alice.address(),
  `0x1::coin::CoinStore<${coinType}>`
)
console.log(r)