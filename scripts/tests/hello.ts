import { AptosAccount, AptosClient, FaucetClient, Types, } from "aptos";

import fs from 'fs'
import fetch from 'node-fetch'
import yaml from 'js-yaml'
import { excuteuTransaction, FAUCET_URL, NODE_URL, umi_pool } from "../src/utils";

const client = new AptosClient(NODE_URL)
const faucetClient = new FaucetClient(NODE_URL, FAUCET_URL)

interface PrivateKeys {
  account_address: string
  account_private_key: string
  consensus_private_key: string
  full_node_network_private_key: string
  validator_network_private_key: string
}

const aliceKeys: PrivateKeys = yaml.load(fs.readFileSync(
  'keys/devnet/keys/alice/private-keys.yaml', 'utf-8'
))

const alice = new AptosAccount(
  Buffer.from(aliceKeys.account_private_key.replace('0x', ''), 'hex'),
  aliceKeys.account_address,
)

console.log('alice', alice.toPrivateKeyObject())

await faucetClient.fundAccount(alice.address(), 5_000)

const payload: Types.EntryFunctionPayload =
{
  "function": `${umi_pool}::message::set_message`,
  "type_arguments": [
  ],
  "arguments": [
    "Hello, Umi Protocol",
  ],
}
console.log('payload', payload)

const txHash = await excuteuTransaction(
  client,
  alice,
  payload,
)
console.log(txHash)

let addr = alice.address()
let resourceType = `${umi_pool}::message::MessageHolder`
let url = `https://fullnode.devnet.aptoslabs.com/v1/accounts/${addr}/resource/${resourceType}`

let r = await fetch(url)
let d = await r.json() as {
  data: {
    message: string
  }
}

console.log(d)

console.log(
  decodeURIComponent(d.data.message)
)