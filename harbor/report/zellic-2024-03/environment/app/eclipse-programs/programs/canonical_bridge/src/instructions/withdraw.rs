use anchor_lang::prelude::*;
use anchor_lang::solana_program::system_instruction;
use crate::state::{WithdrawalReceipt, Data, WithdrawalMessageSent, Message};
use alloy_rlp::encode;
use base64::prelude::*;


#[derive(Accounts)]
#[instruction(destination_address: String, withdrawal_nonce: u64, amount: u64)]
pub struct Withdraw<'info> {
    #[account(mut)]
    withdrawer: Signer<'info>,
    #[account(
        init,
        payer = withdrawer,
        space = WithdrawalReceipt::size(),
        seeds = [
            b"withdrawal",
            withdrawal_nonce.to_le_bytes().as_ref()
            ],
        bump,
    )]
    withdrawal_receipt: Account<'info, WithdrawalReceipt>,
    #[account(mut)]
    /// CHECK: we transfer into this account
    pub relayer: AccountInfo<'info>,
    rent: Sysvar<'info, Rent>,
    system_program: Program<'info, System>,
}

pub fn withdraw(ctx: Context<Withdraw>, destination_address: String,  withdrawal_nonce: u64, amount: u64, bump: u8) -> Result<()> {
  let from_account = &ctx.accounts.withdrawer;
  let to_account = &ctx.accounts.relayer;

  let withdrawal_receipt = &mut ctx.accounts.withdrawal_receipt;
  withdrawal_receipt.destination_address = destination_address.clone();
  withdrawal_receipt.withdrawal_nonce = withdrawal_nonce;
  withdrawal_receipt.amount = amount;
  withdrawal_receipt.bump = bump;
  
  
  let transfer_instruction = system_instruction::transfer(from_account.key, to_account.key, amount);

  anchor_lang::solana_program::program::invoke_signed(
      &transfer_instruction,
      &[
          from_account.to_account_info(),
          to_account.clone(),
          ctx.accounts.system_program.to_account_info(),
      ],
      &[],
  )?;


  let message = Message {
      destination_address: destination_address.clone(),
      amount,
  };
  
  let data = Data {
      nonce: withdrawal_nonce
  };

  let withdrawal_message = WithdrawalMessageSent {
      chainId: String::from("Eclipse"),
      receiver: String::from("EtherBridge"),
      message,
      data,
  };

  log_outbox_message(withdrawal_message);


  Ok(())
}

pub fn log_outbox_message(message: WithdrawalMessageSent) -> () {
  let encoded_message = encode(message);
  msg!("{:?}", BASE64_STANDARD.encode(encoded_message));
}
