import { AptosAccount, AptosClient, FaucetClient, HexString, MaybeHexString, TxnBuilderTypes, Types } from "aptos";
import fs from 'fs'
import yaml from 'js-yaml'
import { PrivateKeys } from '../types'

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

const configProfile: AptosConfigProfile = yaml.load(fs.readFileSync(
  '.aptos/config.yaml', 'utf-8'
))

export const admin = new AptosAccount(
  Buffer.from(configProfile.profiles.default.private_key.replace('0x', ''), 'hex'),
  configProfile.profiles.default.account,
)

const aliceKeys: PrivateKeys = yaml.load(fs.readFileSync(
  'keys/devnet/keys/alice/private-keys.yaml', 'utf-8'
))

export const alice = new AptosAccount(
  Buffer.from(aliceKeys.account_private_key.replace('0x', ''), 'hex'),
  aliceKeys.account_address,
)
