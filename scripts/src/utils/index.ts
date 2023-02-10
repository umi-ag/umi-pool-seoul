import { AptosAccount, AptosClient, FaucetClient, HexString, MaybeHexString, TxnBuilderTypes, Types } from "aptos";
import fs from 'fs'
import yaml from 'js-yaml'

export const NODE_URL = 'https://fullnode.devnet.aptoslabs.com/v1'
export const FAUCET_URL = 'https://faucet.devnet.aptoslabs.com'

interface AptosConfigProfile {
  profiles: {
    default: {
      private_key: string
      public_key: string
      account: string
      rest_url: string
      faucet_url: string
    }
  }
}



export const sleep = (milliseconds) => {
  return new Promise((resolve) => setTimeout(resolve, milliseconds))
}

export const printTx = (txHash: string) => {
  console.log(`https://explorer.devnet.aptos.dev/txn/${txHash}`)
}


const configProfile: AptosConfigProfile = yaml.load(fs.readFileSync(
  '.aptos/config.yaml', 'utf-8'
))

export const umi_pool = `0x${configProfile.profiles.default.account}`

export const admin = new AptosAccount(
  Buffer.from(configProfile.profiles.default.private_key.replace('0x', ''), 'hex'),
  configProfile.profiles.default.account,
)

export const excuteuTransaction = async (
  client: AptosClient,
  account: AptosAccount,
  payload: Types.EntryFunctionPayload
) => {
  const txnRequest = await client.generateTransaction(account.address(), payload)
  const signedTxn = await client.signTransaction(account, txnRequest)
  const transactionRes = await client.submitTransaction(signedTxn)
  await client.waitForTransaction(transactionRes.hash)
  return transactionRes.hash
}

export const stringToHex = (text: string) => {
  const encoder = new TextEncoder();
  const encoded = encoder.encode(text);
  return Array.from(encoded, (i) => i.toString(16).padStart(2, "0")).join("");
}
