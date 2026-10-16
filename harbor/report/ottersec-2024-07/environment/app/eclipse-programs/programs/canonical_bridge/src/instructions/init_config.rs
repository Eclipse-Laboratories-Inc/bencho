use anchor_lang::prelude::*;

use crate::{state::Configuration, BRIDGE_AUTHORITY_PUBKEY};



#[derive(Accounts)]
pub struct InitConfig<'info> {
    #[account(mut, address = BRIDGE_AUTHORITY_PUBKEY)]
    pub authority: Signer<'info>,
    #[account(
        init,
        payer = authority,
        seeds = [b"configure"],
        space = Configuration::size(),
        bump,
    )]
    pub configuration: Account<'info, Configuration>,
    pub system_program: Program<'info, System>,
}


pub fn init_config(ctx: Context<InitConfig>) -> Result<()> {
    let config = &mut ctx.accounts.configuration;
    config.deposits_paused = false;
    config.withdrawals_paused = false;
    config.bump = ctx.bumps.configuration;

    Ok(())
}