use anchor_lang::prelude::*;
use anchor_lang::solana_program::pubkey;

pub mod instructions;
pub use instructions::*;
pub mod state;



declare_id!("bripkhe8bjXg5PUxub3raVpoqZVRBPjTjPgAC22AHHF");
pub const RELAYER_PUBKEY: Pubkey = pubkey!("ec1vCnQKsQSnTbcTyc3SH2azcDXZquiFB3QqtRvm3Px");

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

}
