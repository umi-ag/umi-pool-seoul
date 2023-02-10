
import { AptosAccount, AptosClient, FaucetClient, Types, } from "aptos";
import { FAUCET_URL, NODE_URL, excuteuTransaction, umi_pool, sleep } from '../src/utils'
import { admin } from '../src/utils/accounts'
import Decimal from 'decimal.js'

import fs from 'fs'
import fetch from 'node-fetch'
import yaml from 'js-yaml'

const client = new AptosClient(NODE_URL)
const faucetClient = new FaucetClient(NODE_URL, FAUCET_URL)


const oracleV1 = admin

console.log('oracle v1:', oracleV1.toPrivateKeyObject())

await faucetClient.fundAccount(oracleV1.address(), 5_000)

const coin_RED = `${umi_pool}::coin_list::RED`;
const coin_BLUE = `${umi_pool}::coin_list::BLUE`;

const fee_rate = 3000 // 0.3%
const greedy_alpha = 1000000 // 1
const slack_mu = 2000000 // 2


const test_register = async () => {
  const payload: Types.EntryFunctionPayload =
  {
    "function": `${umi_pool}::pool::register`,
    "type_arguments": [coin_RED, coin_BLUE],
    "arguments": [fee_rate, greedy_alpha, slack_mu],
  }

  console.log('payload', payload)

  const txHash = await excuteuTransaction(client, oracleV1, payload)
    .catch(e => { console.error(e) })
  console.log("tx:", txHash)
}


const test_set_price = async () => {
  const quote = await fetch(
    'https://www.binance.com/api/v3/ticker/price?symbol=SOLUSDT'
  ).then(async r => {
    const d = await r.json() as {
      symbol: string,
      price: string,
    }
    return d
  }).catch(e => {
    console.error(e)
  })


  const price = new Decimal(quote.price).mul(1.73)

  const payload: Types.EntryFunctionPayload =
  {
    "function": `${umi_pool}::pool::set_price`,
    "type_arguments": [
      coin_RED,
      coin_BLUE,
    ],
    "arguments": [
      price.mul(10 ** price.decimalPlaces()).toNumber(), // 114514
      price.decimalPlaces(), // 3
    ],
  }

  console.log('payload', payload)

  const txHash2 = await excuteuTransaction(client, oracleV1, payload)
    .catch(e => { console.error(e) })
  console.log("tx:", txHash2)

  let addr = oracleV1.address()
  let resourceType = `${umi_pool}::pool::Price<${coin_RED}, ${coin_BLUE}>`
  let url = `https://fullnode.devnet.aptoslabs.com/v1/accounts/${addr}/resource/${resourceType}`

  let r = await fetch(url)
  let d = await r.json() as {
    data: {
      price: {
        value: string
        dec: number
        neg: false
      }
    }
  }
  console.log(d)
  let p = new Decimal(d.data.price.value).div(10 ** d.data.price.dec)
  console.log(p.toFixed())
}

await test_register()
await sleep(10e3)
await test_set_price()