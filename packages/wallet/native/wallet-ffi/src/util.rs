// SPDX-FileCopyrightText: 2022 Foundation Devices Inc.
//
// SPDX-License-Identifier: GPL-3.0-or-later

use crate::{
    serialize, Address, Client, OutPoint, PartiallySignedTransaction, Psbt, Socks5Config, Txid,
    UtxoList,
};
use bdk::blockchain::{ConfigurableBlockchain, ElectrumBlockchain, ElectrumBlockchainConfig};
use bdk::database::BatchDatabase;
use bdk::electrum_client;
use bdk::electrum_client::ConfigBuilder;
use bdk::wallet::tx_builder::TxOrdering;
use bdk::wallet::AddressIndex;
use bdk::{FeeRate, TransactionDetails};
use bip39::{Language, Mnemonic};
use bitcoin_hashes::hex::ToHex;
use sled::Tree;
use std::ffi::{CStr, CString};
use std::str::FromStr;
use std::sync::{Mutex, MutexGuard};

pub unsafe fn get_wallet_mutex(
    wallet: *mut Mutex<bdk::Wallet<Tree>>,
) -> &'static mut Mutex<bdk::Wallet<Tree>> {
    let wallet = {
        assert!(!wallet.is_null());
        &mut *wallet
    };
    wallet
}

fn get_electrum_blockchain_config(
    tor_port: i32,
    electrum_address: &str,
) -> ElectrumBlockchainConfig {
    if tor_port > 0 {
        ElectrumBlockchainConfig {
            url: electrum_address.parse().unwrap(),
            socks5: Some("127.0.0.1:".to_owned() + &tor_port.to_string()),
            retry: 0,
            timeout: None,
            stop_gap: 50,
            validate_domain: false,
        }
    } else {
        ElectrumBlockchainConfig {
            url: electrum_address.parse().unwrap(),
            socks5: None,
            retry: 0,
            timeout: Some(5),
            stop_gap: 50,
            validate_domain: false,
        }
    }
}

pub fn get_electrum_blockchain(
    tor_port: i32,
    electrum_address: &str,
) -> Result<ElectrumBlockchain, bdk::Error> {
    let config = get_electrum_blockchain_config(tor_port, electrum_address);
    ElectrumBlockchain::from_config(&config)
}

pub fn get_electrum_client(
    tor_port: i32,
    electrum_address: &str,
) -> Result<Client, electrum_client::Error> {
    let config: electrum_client::Config;
    if tor_port > 0 {
        let tor_config = Socks5Config {
            addr: "127.0.0.1:".to_owned() + &tor_port.to_string(),
            credentials: None,
        };
        config = ConfigBuilder::new()
            .validate_domain(false)
            .socks5(Some(tor_config))
            .unwrap()
            .build();
    } else {
        config = ConfigBuilder::new()
            .validate_domain(false)
            .socks5(None)
            .unwrap()
            .timeout(Some(5))
            .unwrap()
            .build();
    }

    Client::from_config(electrum_address, config)
}

pub fn psbt_extract_details<T: BatchDatabase>(
    wallet: &bdk::Wallet<T>,
    psbt: &PartiallySignedTransaction,
) -> Psbt {
    let tx = psbt.clone().extract_tx();
    let raw_tx = serialize::<bdk::bitcoin::Transaction>(&tx).to_hex();

    let sent = tx
        .output
        .iter()
        .filter(|o| !wallet.is_mine(&o.script_pubkey).unwrap_or(false))
        .map(|o| o.value)
        .sum();

    let received = tx
        .output
        .iter()
        .filter(|o| wallet.is_mine(&o.script_pubkey).unwrap_or(false))
        .map(|o| o.value)
        .sum();

    let inputs_value: u64 = psbt
        .inputs
        .iter()
        .map(|i| match &i.witness_utxo {
            None => 0,
            Some(tx) => tx.value,
        })
        .sum();

    let encoded = base64::encode(&serialize(&psbt));
    let psbt = CString::new(encoded).unwrap().into_raw();

    return Psbt {
        sent,
        received,
        fee: inputs_value - sent - received,
        base64: psbt,
        txid: CString::new(tx.txid().to_hex()).unwrap().into_raw(),
        raw_tx: CString::new(raw_tx).unwrap().into_raw(),
    };
}

pub unsafe fn extract_utxo_list(utxos: *const UtxoList) -> Vec<OutPoint> {
    let mut must_spend = vec![];

    for i in 0..(*utxos).utxos_len as isize {
        let utxo_ptr = (*utxos).utxos.offset(i);

        let txid = CStr::from_ptr((*utxo_ptr).txid).to_str().unwrap();
        let vout = (*utxo_ptr).vout;

        must_spend.push(OutPoint::new(Txid::from_str(txid).unwrap(), vout));
    }
    must_spend
}

pub fn build_tx(
    amount: u64,
    fee_rate: f64,
    fee_absolute: Option<u64>,
    wallet: &MutexGuard<bdk::Wallet<Tree>>,
    send_to: Address,
    must_spend: &Vec<OutPoint>,
    dont_spend: &Vec<OutPoint>,
) -> Result<(PartiallySignedTransaction, TransactionDetails), bdk::Error> {
    let mut builder = wallet.build_tx();
    builder
        .change_address_index(AddressIndex::Current)
        .ordering(TxOrdering::Shuffle)
        .only_witness_utxo()
        .add_recipient(send_to.script_pubkey(), amount)
        .enable_rbf()
        .add_utxos(&*must_spend)
        .unwrap();

    match fee_absolute {
        None => {
            builder.fee_rate(FeeRate::from_sat_per_vb((fee_rate * 100000.0) as f32));
        }
        Some(fee) => {
            builder.fee_absolute(fee);
        }
    }

    for outpoint in dont_spend {
        builder.add_unspendable(*outpoint);
    }

    builder.finish()
}

pub fn generate_mnemonic() -> (Mnemonic, String) {
    let mnemonic = Mnemonic::generate_in(Language::English, 12).unwrap();
    let mnemonic_string = mnemonic.to_string();

    (mnemonic, mnemonic_string)
}
