use anchor_lang::prelude::*;
use instructions::*;
use anchor_lang::solana_program::pubkey;

pub mod instructions;
pub mod state;
pub mod errors;



declare_id!("3gcds6MrhVNPBxoWR8kaXnv486w4VxWgh8GYPsfJaMRt");

#[cfg(feature = "use_test_authority")]
pub const RELAYER_PUBKEY: Pubkey = pubkey!("T3STfZppYxqPCYS9fLoitN7RiADdRBsJ1c7rN3gNKTc");

#[cfg(not(feature = "use_test_authority"))]
pub const RELAYER_PUBKEY: Pubkey = pubkey!("ec1vCnQKsQSnTbcTyc3SH2azcDXZquiFB3QqtRvm3Px");

#[cfg(feature = "use_test_authority")]
pub const BRIDGE_AUTHORITY_PUBKEY: Pubkey = pubkey!("bobYFf6sXFHBk5ZUM3muhka4855fnc5tMg7pa3tFpVK");

#[cfg(not(feature = "use_test_authority"))]
pub const BRIDGE_AUTHORITY_PUBKEY: Pubkey = pubkey!("BoSSQCzuyEpRBC1eHQHMiJkxQPcCT7H7rMYjPTaFB59D");


#[program]
pub mod canonical_bridge {

    use super::*;

    pub fn deposit(
        ctx: Context<Deposit>,
        eth_deposit_nonce: u64,
        amount: u64,
        bump: u8,
    ) -> Result<()> {
        instructions::deposit(ctx, eth_deposit_nonce, amount, bump)
    }

    pub fn withdraw(
        ctx: Context<Withdraw>,
        destination_address: String,
        withdrawal_nonce: u64,
        amount: u64,
        bump: u8) -> Result<()> {
            instructions::withdraw(
                ctx,
                destination_address,
                withdrawal_nonce,
                amount,
                bump
            )
        }
    
    pub fn init_config(
        ctx: Context<InitConfig>,
    ) -> Result<()> {
            instructions::init_config(
                ctx,
            )
        }
    pub fn pause_deposits(
        ctx: Context<Pause>,
    ) -> Result<()> {
            instructions::pause_deposits(
                ctx,
            )
        }
    
    pub fn resume_deposits(
        ctx: Context<Pause>,
    ) -> Result<()> {
            instructions::resume_deposits(
                ctx,
            )
        }
    pub fn pause_withdrawals(
        ctx: Context<Pause>,
    ) -> Result<()> {
            instructions::pause_withdrawals(
                ctx,
            )
        }
    pub fn resume_withdrawals(
        ctx: Context<Pause>,
    ) -> Result<()> {
            instructions::resume_withdrawals(
                ctx,
            )
        }

}
