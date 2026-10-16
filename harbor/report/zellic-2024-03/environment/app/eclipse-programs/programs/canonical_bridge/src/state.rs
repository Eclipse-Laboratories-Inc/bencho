use anchor_lang::prelude::*;
use alloy_rlp::{RlpDecodable, RlpEncodable};

#[account]
pub struct WithdrawalReceipt {
    pub withdrawal_nonce: u64,
    pub destination_address: String,
    pub amount: u64,
    pub bump: u8,

}
#[derive(RlpEncodable, RlpDecodable)]
pub struct Message {
    pub(crate) destination_address: String,
    pub(crate) amount: u64,
}

#[derive(RlpEncodable, RlpDecodable)]
pub struct Data {
    pub(crate) nonce: u64
}
#[derive(RlpEncodable, RlpDecodable)]
pub struct WithdrawalMessageSent {
    pub receiver: String,
    pub chainId: String,
    pub message: Message,
    pub data: Data
}


pub struct MessageSentEvent {
    pub encoded_message: Vec<u8>,
    pub message: WithdrawalMessageSent
}

impl WithdrawalReceipt {
    // TODO: optimize here
    pub fn size() -> usize {
        1024
    }
}

#[account]
pub struct DepositReceipt {
    pub bump: u8,
    pub to: Pubkey,
    pub eth_deposit_nonce: u64,
}

impl DepositReceipt {
    pub fn size() -> usize {
        8 + // delimiter
        32 + // to pubkey
        8 + // eth deposit nonce
        1 // bump
    }
}
