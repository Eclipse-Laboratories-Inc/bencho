"""Write tasks/*/reference/fix.patch from the isolated remediation for each finding."""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from harness import reset_worktree, worktree  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]

REPLACEMENTS = {
    "eclipse-001": (
        "70b57c23334778c4072cb8e60b4e2bbf23a034ed",
        [
            (
                "smart-contracts/src/v1/EtherBridge.sol",
                "payable(address(treasury)).call{value: message.amount}(\"\");",
                "payable(address(treasury)).call{value: amount}(\"\");",
            )
        ],
    ),
    "eclipse-002": (
        "70b57c23334778c4072cb8e60b4e2bbf23a034ed",
        [
            (
                "smart-contracts/src/v1/EtherBridge.sol",
                """        require(address(treasury).balance >= message.amount, "Insufficient funds in treasury for withdrawal");

        // Call the Treasury contract to withdraw funds to the recipient
        treasury.withdraw(payable(message.recipient), message.amount);

        // Emit the Withdrawn event
        emit Withdrawn(message.sender, message.recipient, message.amount);""",
                """        uint256 amountWei = message.amount * 1_000_000_000;
        require(amountWei <= 1 ether, "Amount cannot be more than the max withdraw amount");
        require(address(treasury).balance >= amountWei, "Insufficient funds in treasury for withdrawal");

        // Call the Treasury contract to withdraw funds to the recipient
        treasury.withdraw(payable(message.recipient), amountWei);

        // Emit the Withdrawn event
        emit Withdrawn(message.sender, message.recipient, amountWei);""",
            )
        ],
    ),
    "eclipse-003": (
        "70b57c23334778c4072cb8e60b4e2bbf23a034ed",
        [
            (
                "smart-contracts/src/v1/EtherBridge.sol",
                'require(address(treasury).balance >= message.amount, "Insufficient funds in treasury for withdrawal");',
                """require(message.recipient != address(0), "CommonUtility: zero address");
        require(address(treasury).balance >= message.amount, "Insufficient funds in treasury for withdrawal");""",
            ),
            (
                "smart-contracts/src/v1/Mailbox.sol",
                """    {
        // Increment and update the outbound nonce for the recipient
        uint64 outboundNonce = generateRandomNonce();""",
                """    {
        require(to_.length > 0, "CommonUtility: empty bytes");
        // Increment and update the outbound nonce for the recipient
        uint64 outboundNonce = generateRandomNonce();""",
            ),
        ],
    ),
    "eclipse-004": (
        "70b57c23334778c4072cb8e60b4e2bbf23a034ed",
        [
            (
                "smart-contracts/src/v1/Mailbox.sol",
                """        // Route the message
        router.routeIncomingMessage(sender_, message_);

        // Update the nonce
        receiveNonces[secParam.nonce] = true;""",
                """        // Update the nonce before the external call.
        receiveNonces[secParam.nonce] = true;

        // Route the message
        router.routeIncomingMessage(sender_, message_);""",
            )
        ],
    ),
    "eclipse-005": (
        "bcbec05047af74c9d5bbcd819c829c655e544bb6",
        [
            (
                "smart-contracts/src/v1/EtherBridge.sol",
                "uint256 private constant MIN_DEPOSIT_LAMPORTS = (LAMPORTS_PER_YEAR * EXEMPTION_THRESHOLD * DEPOSIT_RECEIPT_DATA_LEN);",
                "uint256 private constant MIN_DEPOSIT_LAMPORTS = 2_000_000;",
            )
        ],
    ),
    "eclipse-006": (
        "bcbec05047af74c9d5bbcd819c829c655e544bb6",
        [
            (
                "smart-contracts/src/v1/Mailbox.sol",
                "emit MessageSent(receiver_, encodeChainId($.ethereumChainId), message_, param);",
                "emit MessageSent(receiver_, encodeChainId($.eclipseChainId), message_, param);",
            )
        ],
    ),
    "eclipse-007": (
        "061cba3992df91a3fced5078f6915d929bbeb4f8",
        [
            (
                "smart-contracts/src/v1/Treasury.sol",
                """        uint256 totalAmount = amountWei + feeWei;
        if (address(this).balance < totalAmount) {""",
                """        if (address(this).balance < amountWei) {""",
            )
        ],
    ),
    "eclipse-008": (
        "ffb018a68bdcc3a07d34e22ffc48e2d2ed20efe1",
        [
            (
                "smart-contracts/src/v1/CanonicalBridge.sol",
                """        deleteWithdrawMessage(withdrawMessageHash(message));
        emit WithdrawMessageDeleted(msg.sender, message);""",
                """        withdrawMsgIdProcessed[message.withdrawId] = 0;
        deleteWithdrawMessage(withdrawMessageHash(message));
        emit WithdrawMessageDeleted(msg.sender, message);""",
            )
        ],
    ),
    "eclipse-009": (
        "9b3f09d6a78f6d4dd690bb3b7fd7a8c7607d24bc",
        [
            (
                "smart-contracts/src/v1/CanonicalBridge.sol",
                """        whenNotPaused
        validWithdrawMessage(message)
    {
        bytes32 messageHash = withdrawMessageHash(message);
        if (withdrawMessageStatus(messageHash) != WithdrawStatus.PENDING) revert WithdrawUnauthorized();

        // Transfer funds to recipient.
        bool success = ITreasury(TREASURY).withdrawEth(
            message.destination,
            message.amountWei,
            message.feeReceiver,
            message.feeWei
        );
        /// @dev The following condition should never occur and the error should be unreachable code.
        if (!success) revert WithdrawFailed();
        startTime[messageHash] = NEVER;
        emit WithdrawClaimed(message.destination, message.from, messageHash, message);
    }""",
                """        whenNotPaused
        nonReentrant
        validWithdrawMessage(message)
    {
        bytes32 messageHash = withdrawMessageHash(message);
        if (withdrawMessageStatus(messageHash) != WithdrawStatus.PENDING) revert WithdrawUnauthorized();

        startTime[messageHash] = NEVER;
        emit WithdrawClaimed(message.destination, message.from, messageHash, message);

        // Transfer funds to recipient.
        bool success = ITreasury(TREASURY).withdrawEth(
            message.destination,
            message.amountWei,
            message.feeReceiver,
            message.feeWei
        );
        /// @dev The following condition should never occur and the error should be unreachable code.
        if (!success) revert WithdrawFailed();
    }""",
            )
        ],
    ),
    "eclipse-010": (
        "26c409b8c563367602f0b8df9f205744a98731c1",
        [
            (
                "smart-contracts/src/v1/CanonicalBridge.sol",
                """        if (message.feeWei > message.amountWei) {
            revert CanonicalBridgeTransactionRejected(message.withdrawId, "message.fee exceeds message.amount");
        }
        _;""",
                """        if (message.feeWei > message.amountWei) {
            revert CanonicalBridgeTransactionRejected(message.withdrawId, "message.fee exceeds message.amount");
        }
        if (message.feeReceiver == NULL_ADDRESS) {
            revert CanonicalBridgeTransactionRejected(message.withdrawId, "Null fee receiver");
        }
        _;""",
            )
        ],
    ),
}


def export_one(task_id: str, commit: str, edits: list[tuple[str, str, str]]) -> None:
    dest = worktree(commit)
    reset_worktree(dest, commit)
    for rel, old, new in edits:
        path = dest / rel
        text = path.read_text()
        count = text.count(old)
        if count != 1:
            raise SystemExit(f"{task_id}: expected 1 occurrence of target in {rel}, found {count}")
        path.write_text(text.replace(old, new, 1))
    diff = subprocess.run(
        ["git", "-C", str(dest), "diff", "--", *[rel for rel, _, _ in edits]],
        check=True,
        capture_output=True,
        text=True,
    ).stdout
    if not diff.strip():
        raise SystemExit(f"{task_id}: empty diff")
    out = ROOT / "tasks" / task_id / "reference"
    out.mkdir(parents=True, exist_ok=True)
    (out / "fix.patch").write_text(diff)
    reset_worktree(dest, commit)
    check = subprocess.run(
        ["git", "-C", str(dest), "apply", "--check", str(out / "fix.patch")],
        capture_output=True,
        text=True,
    )
    if check.returncode != 0:
        raise SystemExit(f"{task_id}: patch does not apply\n{check.stderr}")
    print(f"wrote {task_id} ({len(diff.splitlines())} lines)")


def main() -> None:
    for task_id, (commit, edits) in REPLACEMENTS.items():
        export_one(task_id, commit, edits)


if __name__ == "__main__":
    main()
