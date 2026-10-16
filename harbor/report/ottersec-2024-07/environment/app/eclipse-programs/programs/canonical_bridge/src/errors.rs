use anchor_lang::prelude::*;
#[error_code]
pub enum ErrorCode {
    #[msg("Deposit is currently paused.")]
    DepositPaused,
    #[msg("Withdrawal is currently paused.")]
    WithdrawalPaused,
}

