
use anchor_lang::prelude::*;
use anchor_lang::solana_program::system_instruction;

use crate::{state::DepositReceipt, RELAYER_PUBKEY};

#[derive(Accounts)]
#[instruction(eth_deposit_nonce: u64)]
pub struct Deposit<'info> {
    #[account(mut, address = RELAYER_PUBKEY)]
    relayer: Signer<'info>,
    #[account(
        init,
        payer = relayer,
        space = DepositReceipt::size(),
        seeds = [b"deposit", eth_deposit_nonce.to_le_bytes().as_ref()],
        bump,
    )]
    deposit_receipt: Account<'info, DepositReceipt>,
    /// CHECK: no need to write or read from this account
    #[account(mut)]
    pub to: AccountInfo<'info>,
    rent: Sysvar<'info, Rent>,
    system_program: Program<'info, System>,
}



pub fn deposit(
  ctx: Context<Deposit>,
  eth_deposit_nonce: u64,
  amount: u64,
  bump: u8,
) -> Result<()> {
  let from_account = &ctx.accounts.relayer;
  let to_account = &ctx.accounts.to;

  let deposit_receipt = &mut ctx.accounts.deposit_receipt;
  deposit_receipt.to = ctx.accounts.to.key();
  deposit_receipt.eth_deposit_nonce = eth_deposit_nonce;
  deposit_receipt.bump = bump;

  let transfer_instruction =
      system_instruction::transfer(from_account.key, to_account.key, amount);

  anchor_lang::solana_program::program::invoke_signed(
      &transfer_instruction,
      &[
          from_account.to_account_info(),
          to_account.clone(),
          ctx.accounts.system_program.to_account_info(),
      ],
      &[],
  )?;

  Ok(())
}
