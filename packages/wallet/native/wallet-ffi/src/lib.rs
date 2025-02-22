// SPDX-FileCopyrightText: 2022 Foundation Devices Inc.
//
// SPDX-License-Identifier: GPL-3.0-or-later

#[macro_use]
extern crate log;

use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::ptr;

use std::cell::RefCell;
use std::convert::TryFrom;
use std::error::Error;

use bdk::bitcoin::{Address, Network, OutPoint, Txid};
use bdk::database::{ConfigurableDatabase, MemoryDatabase};
use bdk::electrum_client::{ElectrumApi, Socks5Config};
use bdk::sled::Tree;
use bdk::wallet::AddressIndex;
use bdk::{electrum_client, miniscript, Balance, FeeRate, SignOptions, SyncOptions};
use std::str::FromStr;

use bdk::bitcoin::consensus::encode::deserialize;
use bdk::bitcoin::consensus::encode::serialize;

use std::ptr::null_mut;

use crate::electrum_client::Client;
use crate::miniscript::Segwitv0;
use bdk::bitcoin::secp256k1::Secp256k1;
use bdk::bitcoin::util::bip32::{DerivationPath, ExtendedPrivKey, KeySource};
use bdk::bitcoin::util::psbt::PartiallySignedTransaction;
use bdk::keys::bip39::MnemonicWithPassphrase;
use bdk::keys::DescriptorKey::Secret;
use bdk::keys::{
    DerivableKey, DescriptorKey, ExtendedKey, GeneratableDefaultOptions, GeneratedKey,
};
use bdk::miniscript::psbt::PsbtExt;
use bdk::psbt::PsbtUtils;
use bip39::{Language, Mnemonic};
use std::sync::Mutex;

mod util;

#[repr(C)]
#[derive(Debug, Clone, Copy)]
pub enum NetworkType {
    Mainnet,
    Testnet,
    Signet,
    Regtest,
}

impl Into<Network> for NetworkType {
    fn into(self) -> Network {
        match self {
            NetworkType::Mainnet => Network::Bitcoin,
            NetworkType::Testnet => Network::Testnet,
            NetworkType::Signet => Network::Signet,
            NetworkType::Regtest => Network::Regtest,
        }
    }
}

impl Into<String> for NetworkType {
    fn into(self) -> String {
        match self {
            NetworkType::Mainnet => "mainnet".to_string(),
            NetworkType::Testnet => "testnet".to_string(),
            NetworkType::Signet => "signet".to_string(),
            NetworkType::Regtest => "regtest".to_string(),
        }
    }
}

#[repr(C)]
pub struct Transaction {
    txid: *const c_char,
    received: u64,
    sent: u64,
    fee: u64,
    confirmation_height: u32,
    confirmation_time: u64,
    outputs_len: u8,
    outputs: *const *const c_char,
    inputs_len: u8,
    inputs: *const *const c_char,
    address: *const c_char,
}

#[repr(C)]
pub struct TransactionList {
    transactions_len: u32,
    transactions: *const Transaction,
}

#[repr(C)]
pub struct RawTransaction {
    version: i32,
    outputs_len: u8,
    outputs: *const RawTransactionOutput,
    inputs_len: u8,
    inputs: *const RawTransactionInput,
}

#[repr(C)]
pub struct RawTransactionOutput {
    amount: u64,
    address: *const c_char,
}

#[repr(C)]
pub struct RawTransactionInput {
    previous_output_index: u32,
    previous_output: *const c_char,
}

#[repr(C)]
pub struct Utxo {
    txid: *const c_char,
    vout: u32,
    value: u64,
}

#[repr(C)]
pub struct UtxoList {
    utxos_len: u32,
    utxos: *const Utxo,
}

#[repr(C)]
pub struct Seed {
    mnemonic: *const c_char,
    xprv: *const c_char,
    fingerprint: *const c_char,
}

#[repr(C)]
pub struct Psbt {
    sent: u64,
    received: u64,
    fee: u64,
    base64: *const c_char,
    txid: *const c_char,
    raw_tx: *const c_char,
}

#[repr(C)]
pub struct ServerFeatures {
    server_version: *const c_char,
    protocol_min: *const c_char,
    protocol_max: *const c_char,
    pruning: i64,
    genesis_hash: *const u8,
}

#[repr(C)]
pub struct Wallet {
    name: *const c_char,
    network: NetworkType,
    external_pub_descriptor: *const c_char,
    internal_pub_descriptor: *const c_char,
    external_prv_descriptor: *const c_char,
    internal_prv_descriptor: *const c_char,
    bkd_wallet_ptr: *mut usize,
}

thread_local! {
    static LAST_ERROR: RefCell<Option<Box<dyn Error>>> = RefCell::new(None);
}

/// Update the most recent error, clearing whatever may have been there before.
pub fn update_last_error<E: Error + 'static>(err: E) {
    error!("Setting LAST_ERROR: {}", err);

    {
        // Print a pseudo-backtrace for this error, following back each error's
        // cause until we reach the root error.
        let mut cause = err.source();
        while let Some(parent_err) = cause {
            warn!("Caused by: {}", parent_err);
            cause = parent_err.source();
        }
    }

    LAST_ERROR.with(|prev| {
        *prev.borrow_mut() = Some(Box::new(err));
    });
}

/// Retrieve the most recent error, clearing it in the process.
pub fn take_last_error() -> Option<Box<dyn Error>> {
    LAST_ERROR.with(|prev| prev.borrow_mut().take())
}

#[no_mangle]
pub unsafe extern "C" fn wallet_last_error_message() -> *const c_char {
    let last_error = match take_last_error() {
        Some(err) => err,
        None => return CString::new("").unwrap().into_raw(),
    };

    let error_message = last_error.to_string();
    CString::new(error_message).unwrap().into_raw()
}

macro_rules! unwrap_or_return {
    ($a:expr,$b:expr) => {
        match $a {
            Ok(x) => x,
            Err(e) => {
                update_last_error(e);
                return $b;
            }
        }
    };
}

#[no_mangle]
pub unsafe extern "C" fn wallet_init(
    name: *const c_char,
    external_descriptor: *const c_char,
    internal_descriptor: *const c_char,
    data_dir: *const c_char,
    network: NetworkType,
) -> *mut Mutex<bdk::Wallet<Tree>> {
    let name = unwrap_or_return!(CStr::from_ptr(name).to_str(), null_mut());
    let external_descriptor =
        unwrap_or_return!(CStr::from_ptr(external_descriptor).to_str(), null_mut());
    let internal_descriptor =
        unwrap_or_return!(CStr::from_ptr(internal_descriptor).to_str(), null_mut());
    let data_dir = unwrap_or_return!(CStr::from_ptr(data_dir).to_str(), null_mut());

    init(
        network,
        name,
        external_descriptor,
        internal_descriptor,
        data_dir,
    )
}

#[no_mangle]
pub unsafe extern "C" fn wallet_drop(wallet: *mut Mutex<bdk::Wallet<Tree>>) {
    drop(wallet);
}

// Get wallet public/private pair from seed words, path and network
#[no_mangle]
pub unsafe extern "C" fn wallet_derive(
    seed_words: *const c_char,
    passphrase: *const c_char,
    path: *const c_char,
    network: NetworkType,
    init_wallet: bool,
    data_dir: *const c_char,
    private: bool, // Which BDK wallet to return
) -> Wallet {
    let error_return = Wallet {
        name: ptr::null(),
        network,
        external_pub_descriptor: ptr::null(),
        internal_pub_descriptor: ptr::null(),
        external_prv_descriptor: ptr::null(),
        internal_prv_descriptor: ptr::null(),
        bkd_wallet_ptr: null_mut(),
    };

    let seed_words = unwrap_or_return!(CStr::from_ptr(seed_words).to_str(), error_return);
    let path = unwrap_or_return!(CStr::from_ptr(path).to_str(), error_return);

    // Parse seed words
    let mnemonic_words = unwrap_or_return!(Mnemonic::parse(seed_words), error_return);

    let mnemonic: MnemonicWithPassphrase = {
        if !passphrase.is_null() {
            let passphrase = unwrap_or_return!(CStr::from_ptr(passphrase).to_str(), error_return);
            (mnemonic_words, Some(passphrase.parse().unwrap()))
        } else {
            (mnemonic_words, None)
        }
    };

    let xkey: ExtendedKey = unwrap_or_return!(mnemonic.into_extended_key(), error_return);

    let derivation_path = unwrap_or_return!(DerivationPath::from_str(path), error_return);
    let secp = Secp256k1::new();

    // Derive
    let xprv = match xkey.into_xprv(network.clone().into()) {
        None => {
            return error_return;
        }
        Some(p) => p,
    };

    let derived_xprv = &xprv.derive_priv(&secp, &derivation_path).unwrap();
    let origin: KeySource = (xprv.fingerprint(&secp), derivation_path);

    // Get descriptors
    let derived_xprv_desc_key: DescriptorKey<Segwitv0> = derived_xprv
        .into_descriptor_key(Some(origin), DerivationPath::default())
        .unwrap();

    let (descriptor_prv, descriptor_pub) = match derived_xprv_desc_key {
        DescriptorKey::Public(_, _, _) => {
            return error_return;
        }
        Secret(desc_seckey, _, _) => (desc_seckey.to_string(), {
            let desc_pubkey = desc_seckey.to_public(&secp).unwrap();
            desc_pubkey.to_string()
        }),
    };

    let external_pub_descriptor = format!("wpkh({descriptor_pub})").replace("/*", "/0/*");
    let internal_pub_descriptor = external_pub_descriptor.replace("/0/*", "/1/*");

    let external_prv_descriptor = format!("wpkh({descriptor_prv})").replace("/*", "/0/*");
    let internal_prv_descriptor = external_prv_descriptor.replace("/0/*", "/1/*");

    let xfp = &descriptor_prv[1..9];
    let network_str: String = network.into();

    let name = format!("{xfp}-{network_str}");

    let data_dir = unwrap_or_return!(CStr::from_ptr(data_dir).to_str(), error_return);
    let wallet_dir = format!("{data_dir}{name}");

    let ptr = {
        if !init_wallet {
            null_mut()
        } else if private {
            init(
                network,
                &*name,
                &*external_prv_descriptor,
                &*internal_prv_descriptor,
                &*wallet_dir,
            )
        } else {
            init(
                network,
                &*name,
                &*external_pub_descriptor,
                &*internal_pub_descriptor,
                &*wallet_dir,
            )
        }
    };

    Wallet {
        name: CString::new(name).unwrap().into_raw(),
        network,
        external_pub_descriptor: CString::new(external_pub_descriptor).unwrap().into_raw(),
        internal_pub_descriptor: CString::new(internal_pub_descriptor).unwrap().into_raw(),
        external_prv_descriptor: CString::new(external_prv_descriptor).unwrap().into_raw(),
        internal_prv_descriptor: CString::new(internal_prv_descriptor).unwrap().into_raw(),
        bkd_wallet_ptr: ptr as *mut usize,
    }
}

#[no_mangle]
pub unsafe extern "C" fn wallet_get_address(
    wallet: *mut Mutex<bdk::Wallet<Tree>>,
) -> *const c_char {
    let wallet = util::get_wallet_mutex(wallet).lock().unwrap();

    let address = wallet
        .get_address(AddressIndex::New)
        .unwrap()
        .address
        .to_string();

    // SFT-1580: unreliable fsync on mobile platforms occasionally causes address reuse
    let _ = wallet.database().flush();

    CString::new(address).unwrap().into_raw()
}

#[no_mangle]
pub unsafe extern "C" fn wallet_get_change_address(
    wallet: *mut Mutex<bdk::Wallet<Tree>>,
) -> *const c_char {
    let wallet = util::get_wallet_mutex(wallet).lock().unwrap();

    let address = wallet
        .get_internal_address(AddressIndex::New)
        .unwrap()
        .address
        .to_string();

    // SFT-1580: unreliable fsync on mobile platforms occasionally causes address reuse
    let _ = wallet.database().flush();

    CString::new(address).unwrap().into_raw()
}

#[no_mangle]
pub unsafe extern "C" fn wallet_sync(
    wallet: *mut Mutex<bdk::Wallet<Tree>>,
    electrum_address: *const c_char,
    tor_port: i32,
) -> bool {
    let wallet = unwrap_or_return!(util::get_wallet_mutex(wallet).lock(), false);

    let electrum_address = unwrap_or_return!(CStr::from_ptr(electrum_address).to_str(), false);

    let blockchain = unwrap_or_return!(
        util::get_electrum_blockchain(tor_port, electrum_address),
        false
    );
    unwrap_or_return!(
        wallet.sync(&blockchain, SyncOptions { progress: None }),
        false
    );

    // Successful sync
    true
}

#[no_mangle]
pub unsafe extern "C" fn wallet_get_balance(wallet: *mut Mutex<bdk::Wallet<Tree>>) -> u64 {
    let wallet = util::get_wallet_mutex(wallet).lock().unwrap();
    let balance = wallet.get_balance().unwrap();
    get_total_balance(balance)
}

fn get_total_balance(balance: Balance) -> u64 {
    balance.confirmed + balance.immature + balance.trusted_pending + balance.untrusted_pending
}

#[no_mangle]
pub unsafe extern "C" fn wallet_get_utxos(wallet: *mut Mutex<bdk::Wallet<Tree>>) -> UtxoList {
    let wallet = util::get_wallet_mutex(wallet).lock().unwrap();

    let utxos = wallet.list_unspent().unwrap();
    let utxos_len = utxos.len() as u32;

    let mut utxos_vec: Vec<Utxo> = vec![];

    for utxo in utxos {
        utxos_vec.push(Utxo {
            txid: CString::new(format!("{}", utxo.outpoint.txid))
                .unwrap()
                .into_raw(),
            vout: utxo.outpoint.vout,
            value: utxo.txout.value,
        });
    }

    let utxos_box = utxos_vec.into_boxed_slice();
    let utxos_ptr = Box::into_raw(utxos_box);

    UtxoList {
        utxos_len,
        utxos: utxos_ptr as _,
    }
}

#[no_mangle]
pub unsafe extern "C" fn wallet_get_fee_rate(
    electrum_address: *const c_char,
    tor_port: i32,
    target: u16,
) -> f64 {
    let electrum_address = CStr::from_ptr(electrum_address).to_str().unwrap();
    let client = match util::get_electrum_client(tor_port, electrum_address) {
        Ok(c) => c,
        Err(e) => {
            update_last_error(e);
            return -1.0;
        }
    };

    // BTC per kb
    client.estimate_fee(target as usize).unwrap_or(-1.0)
}

#[no_mangle]
pub unsafe extern "C" fn wallet_get_server_features(
    electrum_address: *const c_char,
    tor_port: i32,
) -> ServerFeatures {
    let error_return = ServerFeatures {
        server_version: ptr::null(),
        protocol_min: ptr::null(),
        protocol_max: ptr::null(),
        pruning: 0,
        genesis_hash: ptr::null(),
    };

    let electrum_address = CStr::from_ptr(electrum_address).to_str().unwrap();
    let client = unwrap_or_return!(
        util::get_electrum_client(tor_port, electrum_address),
        error_return
    );

    match client.server_features() {
        Ok(f) => {
            let genesis_hash = f.genesis_hash.clone();

            // Freed on Dart side
            std::mem::forget(genesis_hash);

            ServerFeatures {
                server_version: CString::new(f.server_version).unwrap().into_raw(),
                protocol_min: CString::new(f.protocol_min).unwrap().into_raw(),
                protocol_max: CString::new(f.protocol_max).unwrap().into_raw(),
                pruning: f.pruning.unwrap_or(-1),
                genesis_hash: genesis_hash.as_ptr(),
            }
        }
        Err(e) => {
            update_last_error(e);
            error_return
        }
    }
}

#[no_mangle]
pub unsafe extern "C" fn wallet_get_transactions(
    wallet: *mut Mutex<bdk::Wallet<Tree>>,
) -> TransactionList {
    let err_ret = TransactionList {
        transactions_len: 0,
        transactions: ptr::null(),
    };

    let wallet = unwrap_or_return!(util::get_wallet_mutex(wallet).lock(), err_ret);

    let transactions = unwrap_or_return!(wallet.list_transactions(true), err_ret);
    let transactions_len = transactions.len() as u32;

    let mut transactions_vec: Vec<Transaction> = vec![];

    for transaction in transactions {
        let confirmation_height: u32;
        let confirmation_time: u64;

        match transaction.confirmation_time.as_ref() {
            None => {
                confirmation_height = 0;
                confirmation_time = 0;
            }
            Some(block_time) => {
                confirmation_height = block_time.height.clone();
                confirmation_time = block_time.timestamp.clone();
            }
        }

        let tx = match transaction.transaction.clone() {
            Some(t) => t,
            None => {
                continue;
            }
        };

        let outputs_iter = tx.output.into_iter();

        let address = {
            let mut ret = "".to_string();

            for output in outputs_iter.clone() {
                let is_mine = wallet.is_mine(&output.script_pubkey).unwrap_or(false);
                if (is_mine.clone() && transaction.received.clone() > 0)
                    || (!is_mine && transaction.sent.clone() > 0)
                {
                    ret = match Address::from_script(&output.script_pubkey, wallet.network()) {
                        Ok(a) => a,
                        Err(_) => {
                            continue; // keep looking
                        }
                    }
                    .to_string();

                    break;
                }
            }

            ret
        };

        let outputs: Vec<_> = outputs_iter
            .map(|o| {
                CString::new(
                    match Address::from_script(&o.script_pubkey, wallet.network()) {
                        Ok(a) => a.to_string(),
                        Err(_) => "".to_string(), // These are OP_RETURNS
                    },
                )
                .unwrap()
                .into_raw() as *const c_char
            })
            .collect();

        let outputs_len = outputs.len() as u8;
        let outputs_ptr = outputs.as_ptr();
        std::mem::forget(outputs);

        let inputs: Vec<_> = tx
            .input
            .into_iter()
            .map(|i| {
                CString::new(format!("{}", i.previous_output.txid))
                    .unwrap()
                    .into_raw() as *const c_char
            })
            .collect();

        let inputs_len = inputs.len() as u8;
        let inputs_ptr = inputs.as_ptr();
        std::mem::forget(inputs);

        let tx = Transaction {
            txid: CString::new(format!("{}", transaction.txid))
                .unwrap()
                .into_raw(),
            received: transaction.received,
            sent: transaction.sent,
            fee: transaction.fee.unwrap_or(0),
            confirmation_height,
            confirmation_time,
            outputs_len,
            outputs: outputs_ptr,
            inputs_len,
            inputs: inputs_ptr,
            address: CString::new(address).unwrap().into_raw(),
        };

        transactions_vec.push(tx);
    }

    let transactions_box = transactions_vec.into_boxed_slice();
    let txs_ptr = Box::into_raw(transactions_box);

    TransactionList {
        transactions_len,
        transactions: txs_ptr as _,
    }
}

#[no_mangle]
pub unsafe extern "C" fn wallet_get_max_feerate(
    wallet: *mut Mutex<bdk::Wallet<Tree>>,
    send_to: *const c_char,
    amount: u64,
    must_spend: *const UtxoList,
    dont_spend: *const UtxoList,
) -> f64 {
    let error_return = 0.0;

    let wallet = unwrap_or_return!(util::get_wallet_mutex(wallet).lock(), error_return);
    let address = CStr::from_ptr(send_to).to_str().unwrap();
    let send_to = unwrap_or_return!(Address::from_str(address), error_return);

    let must_spend = util::extract_utxo_list(must_spend);
    let dont_spend = util::extract_utxo_list(dont_spend);

    let balance = get_total_balance(wallet.get_balance().unwrap());

    match util::build_tx(
        amount.clone(),
        0.0,
        Some(balance - amount),
        &wallet,
        send_to.clone(),
        &must_spend,
        &dont_spend,
    ) {
        Ok((psbt, _)) => {
            return match psbt.fee_rate() {
                None => error_return,
                Some(r) => r.as_sat_per_vb() as f64,
            };
        }
        Err(e) => {
            update_last_error(e);
            return error_return;
        }
    }
}

#[no_mangle]
pub unsafe extern "C" fn wallet_create_psbt(
    wallet: *mut Mutex<bdk::Wallet<Tree>>,
    send_to: *const c_char,
    amount: u64,
    fee_rate: f64,
    must_spend: *const UtxoList,
    dont_spend: *const UtxoList,
) -> Psbt {
    let error_return = Psbt {
        sent: 0,
        received: 0,
        fee: 0,
        base64: ptr::null(),
        txid: ptr::null(),
        raw_tx: ptr::null(),
    };
    let wallet = unwrap_or_return!(util::get_wallet_mutex(wallet).lock(), error_return);
    let address = CStr::from_ptr(send_to).to_str().unwrap();
    let send_to = unwrap_or_return!(Address::from_str(address), error_return);
    let must_spend = util::extract_utxo_list(must_spend);
    let dont_spend = util::extract_utxo_list(dont_spend);

    let tx = util::build_tx(
        amount,
        fee_rate,
        None,
        &wallet,
        send_to,
        &must_spend,
        &dont_spend,
    );
    match tx {
        Ok((mut psbt, _)) => {
            let sign_options = SignOptions {
                trust_witness_utxo: true,
                ..Default::default()
            };

            // Always try signing
            let _finalized = match wallet.sign(&mut psbt, sign_options) {
                Ok(f) => f,
                Err(_) => false,
            };

            util::psbt_extract_details(&wallet, &psbt)
        }
        Err(e) => {
            update_last_error(e);
            return error_return;
        }
    }
}

#[no_mangle]
pub unsafe extern "C" fn wallet_decode_psbt(
    wallet: *mut Mutex<bdk::Wallet<Tree>>,
    psbt: *const c_char,
) -> Psbt {
    let error_return = Psbt {
        sent: 0,
        received: 0,
        fee: 0,
        base64: ptr::null(),
        txid: ptr::null(),
        raw_tx: ptr::null(),
    };

    let wallet = unwrap_or_return!(util::get_wallet_mutex(wallet).lock(), error_return);
    let data = unwrap_or_return!(
        base64::decode(CStr::from_ptr(psbt).to_str().unwrap()),
        error_return
    );

    match deserialize::<PartiallySignedTransaction>(&data) {
        Ok(psbt) => {
            let secp = Secp256k1::verification_only();
            let finalized_psbt = PsbtExt::finalize(psbt, &secp).unwrap();
            util::psbt_extract_details(&wallet, &finalized_psbt)
        }
        Err(e) => {
            update_last_error(e);
            error_return
        }
    }
}

#[no_mangle]
pub unsafe extern "C" fn wallet_decode_raw_tx(
    raw_tx: *const c_char,
    network: NetworkType,
) -> RawTransaction {
    let error_return = RawTransaction {
        version: -1,
        outputs_len: 0,
        outputs: ptr::null(),
        inputs_len: 0,
        inputs: ptr::null(),
    };

    let data = unwrap_or_return!(
        hex::decode(CStr::from_ptr(raw_tx).to_str().unwrap()),
        error_return
    );

    let tx: Result<bdk::bitcoin::blockdata::transaction::Transaction, _> = deserialize(&data);
    let decoded_tx = unwrap_or_return!(tx, error_return);

    let outputs: Vec<_> = decoded_tx
        .output
        .iter()
        .map(|o| RawTransactionOutput {
            amount: o.value.clone(),
            address: CString::new(
                Address::from_script(&o.script_pubkey, network.into())
                    .unwrap()
                    .to_string(),
            )
            .unwrap()
            .into_raw() as *const c_char,
        })
        .collect();

    let outputs_len = outputs.len() as u8;
    let outputs_ptr = outputs.as_ptr();
    std::mem::forget(outputs);

    let inputs: Vec<_> = decoded_tx
        .input
        .iter()
        .into_iter()
        .map(|i| RawTransactionInput {
            previous_output_index: i.previous_output.vout.clone(),
            previous_output: CString::new(format!("{}", i.previous_output.txid))
                .unwrap()
                .into_raw() as *const c_char,
        })
        .collect();

    let inputs_len = inputs.len() as u8;
    let inputs_ptr = inputs.as_ptr();
    std::mem::forget(inputs);

    RawTransaction {
        version: decoded_tx.version,
        outputs_len,
        outputs: outputs_ptr,
        inputs_len,
        inputs: inputs_ptr,
    }
}

#[no_mangle]
pub unsafe extern "C" fn wallet_broadcast_tx(
    electrum_address: *const c_char,
    tor_port: i32,
    tx: *const c_char,
) -> *const c_char {
    let error_return = CString::new("").unwrap().into_raw();

    let electrum_address =
        unwrap_or_return!(CStr::from_ptr(electrum_address).to_str(), error_return);
    let client = unwrap_or_return!(
        util::get_electrum_client(tor_port, electrum_address),
        error_return
    );

    let hex_tx = unwrap_or_return!(CStr::from_ptr(tx).to_str(), error_return);
    let raw_tx = unwrap_or_return!(hex::decode(hex_tx), error_return);

    let tx: bdk::bitcoin::Transaction = unwrap_or_return!(deserialize(&*raw_tx), error_return);
    let txid = unwrap_or_return!(client.transaction_broadcast(&tx), error_return);

    unwrap_or_return!(CString::new(txid.to_string()), error_return).into_raw()
}

#[no_mangle]
pub unsafe extern "C" fn wallet_validate_address(
    wallet: *mut Mutex<bdk::Wallet<Tree>>,
    address: *const c_char,
) -> bool {
    let wallet = unwrap_or_return!(util::get_wallet_mutex(wallet).lock(), false);

    match Address::from_str(CStr::from_ptr(address).to_str().unwrap()) {
        Ok(a) => wallet.network() == a.network, // Only valid if it's on same network
        Err(_) => false,
    }
}

#[no_mangle]
pub unsafe extern "C" fn wallet_sign_offline(
    psbt: *const c_char,
    external_descriptor: *const c_char,
    internal_descriptor: *const c_char,
    network: NetworkType,
) -> Psbt {
    let error_return = Psbt {
        sent: 0,
        received: 0,
        fee: 0,
        base64: ptr::null(),
        txid: ptr::null(),
        raw_tx: ptr::null(),
    };

    let external_descriptor = CStr::from_ptr(external_descriptor).to_str().unwrap();
    let internal_descriptor = CStr::from_ptr(internal_descriptor).to_str().unwrap();

    let wallet = bdk::Wallet::new(
        external_descriptor,
        Some(internal_descriptor),
        network.into(),
        MemoryDatabase::new(),
    )
    .unwrap();

    let data = base64::decode(CStr::from_ptr(psbt).to_str().unwrap()).unwrap();
    let mut psbt = deserialize::<PartiallySignedTransaction>(&data).unwrap();

    match wallet.sign(&mut psbt, SignOptions::default()) {
        Ok(_) => util::psbt_extract_details(&wallet, &psbt),
        Err(e) => {
            update_last_error(e);
            error_return
        }
    }
}

#[no_mangle]
pub unsafe extern "C" fn wallet_sign_psbt(
    wallet: *mut Mutex<bdk::Wallet<Tree>>,
    psbt: *const c_char,
) -> Psbt {
    let error_return = Psbt {
        sent: 0,
        received: 0,
        fee: 0,
        base64: ptr::null(),
        txid: ptr::null(),
        raw_tx: ptr::null(),
    };

    let wallet = util::get_wallet_mutex(wallet).lock().unwrap();

    let data = base64::decode(CStr::from_ptr(psbt).to_str().unwrap()).unwrap();
    let mut psbt = deserialize::<PartiallySignedTransaction>(&data).unwrap();

    match wallet.sign(&mut psbt, SignOptions::default()) {
        Ok(_) => util::psbt_extract_details(&wallet, &psbt),
        Err(e) => {
            update_last_error(e);
            error_return
        }
    }
}

#[no_mangle]
pub unsafe extern "C" fn wallet_generate_seed(network: NetworkType) -> Seed {
    let secp = Secp256k1::new();

    let (mut mnemonic, mut mnemonic_string) = util::generate_mnemonic();

    // SFT-2340: try until we get a valid mnemonic (moon rays bug)
    while Mnemonic::parse(mnemonic_string.clone()).is_err() {
        (mnemonic, mnemonic_string) = util::generate_mnemonic();
    }

    let xkey: ExtendedKey<miniscript::BareCtx> = mnemonic.into_extended_key().unwrap();
    let xprv = xkey.into_xprv(network.into()).unwrap();

    let fingerprint = xprv.fingerprint(&secp);

    Seed {
        mnemonic: CString::new(mnemonic_string).unwrap().into_raw(),
        xprv: CString::new(xprv.to_string()).unwrap().into_raw(),
        fingerprint: CString::new(fingerprint.to_string()).unwrap().into_raw(),
    }
}

#[no_mangle]
pub unsafe extern "C" fn wallet_validate_seed(seed_words: *const c_char) -> bool {
    let seed_words = CStr::from_ptr(seed_words).to_str().unwrap();

    // We only deal with Wnglish seeds for now
    Mnemonic::parse_in(Language::English, seed_words).is_ok()
}

// #[no_mangle]
// pub unsafe extern "C" fn wallet_get_seed_words(seed: *const u8) -> Seed {
//     // let mnemonic = Mnemonic::generate_in_with(&mut rng, Language::English, 12).unwrap();
//     // let mnemonic_string = mnemonic.to_string();
//
//     let xkey: ExtendedKey<miniscript::BareCtx> = mnemonic.into_extended_key().unwrap();
//     let xprv = xkey.into_xprv(network.into()).unwrap();
//
//     let fingerprint = xprv.fingerprint(&secp);
//
//     Seed {
//         mnemonic: CString::new(mnemonic_string).unwrap().into_raw(),
//         xprv: CString::new(xprv.to_string()).unwrap().into_raw(),
//         fingerprint: CString::new(fingerprint.to_string()).unwrap().into_raw(),
//     }
// }

#[no_mangle]
pub unsafe extern "C" fn wallet_get_xpub_desc_key(
    xprv: *const c_char,
    path: *const c_char,
) -> *const c_char {
    let secp = Secp256k1::new();

    let xprv = ExtendedPrivKey::from_str(CStr::from_ptr(xprv).to_str().unwrap()).unwrap();
    let path = DerivationPath::from_str(CStr::from_ptr(path).to_str().unwrap()).unwrap();

    let derived_xprv = &xprv.derive_priv(&secp, &path).unwrap();

    let origin: KeySource = (xprv.fingerprint(&secp), path);

    let derived_xprv_desc_key: DescriptorKey<Segwitv0> = derived_xprv
        .into_descriptor_key(Some(origin), DerivationPath::default())
        .unwrap();

    let derived_xpub_desc_key = match derived_xprv_desc_key {
        DescriptorKey::Public(_, _, _) => {
            panic!("Can't get public descriptor")
        }
        Secret(desc_seckey, _, _) => desc_seckey.to_public(&secp).unwrap().to_string(),
    };

    CString::new(derived_xpub_desc_key).unwrap().into_raw()
}

#[no_mangle]
pub unsafe extern "C" fn wallet_generate_xkey_with_entropy(entropy: *const u8) -> *const c_char {
    let entropy_slice = std::slice::from_raw_parts(entropy, 32);
    let entropy_arr = <[u8; 32]>::try_from(entropy_slice).unwrap();
    let xkey: GeneratedKey<ExtendedPrivKey, Segwitv0> =
        ExtendedPrivKey::generate_with_entropy_default(entropy_arr).unwrap();

    CString::new(xkey.to_string()).unwrap().into_raw()
}

#[no_mangle]
pub unsafe extern "C" fn wallet_get_seed_from_entropy(
    network: NetworkType,
    entropy: *const u8,
) -> Seed {
    let secp = Secp256k1::new();

    let entropy = std::slice::from_raw_parts(entropy, 16);

    let mnemonic = Mnemonic::from_entropy(entropy).unwrap();
    let mnemonic_string = mnemonic.to_string();

    let xkey: ExtendedKey = mnemonic.into_extended_key().unwrap();
    let xprv = xkey.into_xprv(network.into()).unwrap();

    let fingerprint = xprv.fingerprint(&secp);

    Seed {
        mnemonic: CString::new(mnemonic_string).unwrap().into_raw(),
        xprv: CString::new(xprv.to_string()).unwrap().into_raw(),
        fingerprint: CString::new(fingerprint.to_string()).unwrap().into_raw(),
    }
}

// Due to its simple signature this function is the one added (unused) to iOS swift codebase to force Xcode to link the lib
#[no_mangle]
pub unsafe extern "C" fn wallet_hello() {
    println!("Hello wallet");
}

pub unsafe fn init(
    network: NetworkType,
    name: &str,
    external_descriptor: &str,
    internal_descriptor: &str,
    data_dir: &str,
) -> *mut Mutex<bdk::Wallet<Tree>> {
    let db_conf = bdk::database::any::SledDbConfiguration {
        path: data_dir.to_string(),
        tree_name: name.to_string(),
    };

    let db = unwrap_or_return!(sled::Tree::from_config(&db_conf), null_mut());

    let wallet = Mutex::new(unwrap_or_return!(
        bdk::Wallet::new(
            external_descriptor,
            Some(internal_descriptor),
            network.into(),
            db
        ),
        null_mut()
    ));

    let wallet_box = Box::new(wallet);
    Box::into_raw(wallet_box)
}
