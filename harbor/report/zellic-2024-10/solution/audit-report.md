# Zellic audit, 2024-10-30

## High: Relayer can become insolvent from many small withdrawals

Location: smart-contracts/src/v1/CanonicalBridge.sol: CanonicalBridge.authorizeWithdraws / _authorizeWithdraw

The relayer pays gas to authorize every withdrawal on Ethereum, but it is only compensated when the withdrawal is claimed. An attacker can request many tiny withdrawals on Eclipse, forcing expensive authorizeWithdraws calls until the relayer runs out of ether and withdrawals stall.

## Medium: 64-bit withdraw ids can collide

Location: smart-contracts/src/v1/CanonicalBridge.sol: withdrawMsgIdProcessed, _authorizeWithdraw, validWithdrawMessage

_authorizeWithdraw rejects any message whose 64-bit withdrawId was already processed. As ids accumulate, random ids collide and legitimate withdrawals revert; an attacker can submit many messages early to raise the collision rate. Keying on the message hash or a wider id avoids this.

## Low: Deployment script does not grant the treasury withdraw role to the bridge

Location: smart-contracts/script/v1/deploy/DeployV1.s.sol

Treasury.withdrawEth requires WITHDRAW_AUTHORITY_ROLE, but DeployV1 never grants that role to the CanonicalBridge. After deployment with this script every claimWithdrawal reverts.
