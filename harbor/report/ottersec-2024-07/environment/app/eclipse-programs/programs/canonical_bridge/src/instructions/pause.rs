use anchor_lang::prelude::*;

use crate::{state::Configuration, BRIDGE_AUTHORITY_PUBKEY};



#[derive(Accounts)]
pub struct Pause<'info> {
    #[account(mut, address = BRIDGE_AUTHORITY_PUBKEY)]
    pub authority: Signer<'info>,
    #[account(
        mut,
        seeds = [b"configure"],
        bump,
    )]
    pub configuration: Account<'info, Configuration>,
    pub system_program: Program<'info, System>,
}


pub fn pause_deposits(ctx: Context<Pause>) -> Result<()> {
    let config = &mut ctx.accounts.configuration;
    config.deposits_paused = true;

    Ok(())
}

pub fn resume_deposits(ctx: Context<Pause>) -> Result<()> {
    let config = &mut ctx.accounts.configuration;
    config.deposits_paused = false;

    Ok(())
}

pub fn pause_withdrawals(ctx: Context<Pause>) -> Result<()> {
    let config = &mut ctx.accounts.configuration;
    config.withdrawals_paused = true;

  Ok(())
}

pub fn resume_withdrawals(ctx: Context<Pause>) -> Result<()> {
    let config = &mut ctx.accounts.configuration;
    config.withdrawals_paused = false;

  Ok(())
}