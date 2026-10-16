# Minimum deposit is below Solana rent-exemption

## Summary

`EtherBridge.MIN_DEPOSIT` is meant to cover a rent-exempt deposit receipt on Eclipse. The constant uses Solar Eclipse's rent formula:

`lamports_per_byte_year * data_len * exemption_threshold`

with `lamports_per_byte_year = 3480`, `exemption_threshold = 2`, and a deposit-receipt data length of 49 bytes. Solana also adds a 128-byte account storage overhead before that data length. The overhead is not included, so the published minimum is too small to make the receipt rent-exempt.

## Expected behavior

`MIN_DEPOSIT / 1e9` lamports is at least `3480 * 2 * (49 + 128)`, and no more than twice that amount — raising the minimum far above the rent-exempt requirement is not a fix. Deposits below the configured minimum still revert. A deposit of exactly `MIN_DEPOSIT` still succeeds.
