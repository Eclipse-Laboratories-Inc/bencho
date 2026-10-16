import * as anchor from "@coral-xyz/anchor";
import { Program } from "@coral-xyz/anchor";
import { LAMPORTS_PER_SOL, PublicKey } from "@solana/web3.js";
import { assert } from "chai";
import { CanonicalBridge } from "../target/types/canonical_bridge";

const deriveDepositPda = (ethDepositNonce, program): [anchor.web3.PublicKey, number] => {
  const [depositReceiptPda, depositReceiptPdaBump ] = PublicKey.findProgramAddressSync(
    [
      Buffer.from('deposit'),
      new anchor.BN(ethDepositNonce).toArrayLike(Buffer, "le", 8),
    ],
    program.programId
  );
  return [depositReceiptPda, depositReceiptPdaBump];
}

describe("canonical_bridge", () => {
  // Configure the client to use the local cluster.
  anchor.setProvider(anchor.AnchorProvider.env());

  const program = anchor.workspace.CanonicalBridge as Program<CanonicalBridge>;
  const relayer = anchor.web3.Keypair.generate();
  const depositor = anchor.web3.Keypair.generate();
  const withdrawer = anchor.web3.Keypair.generate();
  const hackerDepositor = anchor.web3.Keypair.generate();
  let ethDepositNonce = 123456;
  const amount = LAMPORTS_PER_SOL;
  it('prevents deposits not signed by the relayer', async () => {

    const signature = await program.provider.connection.requestAirdrop(relayer.publicKey, LAMPORTS_PER_SOL * 2)
    const latestBlockhash = await program.provider.connection.getLatestBlockhash();
    await program.provider.connection.confirmTransaction(
      {
        signature,
        ...latestBlockhash,
      },
      "confirmed"
    );

    const [depositReceiptPda, depositReceiptPdaBump ] = deriveDepositPda(ethDepositNonce, program)
    try {

    const tx = await program.methods
      .deposit(
        new anchor.BN(ethDepositNonce), 
        new anchor.BN(amount),
        depositReceiptPdaBump
      )
      .accounts({
        depositReceipt: depositReceiptPda,
        to: depositor.publicKey,
        relayer: relayer.publicKey,
      })
      .signers([relayer])
      .rpc();
    } catch(err) {
      console.log("hm: ", err.error.errorCode.code)
      const errorCode = err.error.errorCode.code
      assert.ok(errorCode === "ConstraintAddress")
    }
  })

  it("makes a deposit", async () => {

    const signature = await program.provider.connection.requestAirdrop(relayer.publicKey, LAMPORTS_PER_SOL * 2)
    const latestBlockhash = await program.provider.connection.getLatestBlockhash();
    await program.provider.connection.confirmTransaction(
      {
        signature,
        ...latestBlockhash,
      },
      "confirmed"
    );

    const [depositReceiptPda, depositReceiptPdaBump ] = deriveDepositPda(ethDepositNonce, program)

    const tx = await program.methods
      .deposit(
        new anchor.BN(ethDepositNonce), 
        new anchor.BN(amount),
        depositReceiptPdaBump
      )
      .accounts({
        depositReceipt: depositReceiptPda,
        to: depositor.publicKey,
        relayer: relayer.publicKey,
      })
      .signers([relayer])
      .rpc();

    // verify new balance for depositor
    const depositorBalance = await program.provider.connection.getBalance(depositor.publicKey);
    assert.ok(Number(depositorBalance) === amount );


    // check pda
    const onchainPda = await program.account.depositReceipt.fetch(depositReceiptPda);
    interface ReadableDepositReceipt {
      bump: Number;
      to: String;
      ethDepositNonce: Number
    };
    const readable: ReadableDepositReceipt = {
      bump: onchainPda.bump,
      to: onchainPda.to.toString(),
      ethDepositNonce: onchainPda.ethDepositNonce.toNumber()
    };
    assert.ok(readable.ethDepositNonce === ethDepositNonce);
    assert.ok(readable.to === depositor.publicKey.toString());

  });

  it("prevents duplicate deposits", async () => {
    ethDepositNonce = ethDepositNonce + 1;

    const signature = await program.provider.connection.requestAirdrop(relayer.publicKey, LAMPORTS_PER_SOL * 4)
    const latestBlockhash = await program.provider.connection.getLatestBlockhash();
    await program.provider.connection.confirmTransaction(
      {
        signature,
        ...latestBlockhash,
      },
      "confirmed"
    );

    const [depositReceiptPda, depositReceiptPdaBump ] = deriveDepositPda(ethDepositNonce, program);

    const tx = await program.methods
      .deposit(
        new anchor.BN(ethDepositNonce), 
        new anchor.BN(amount),
        depositReceiptPdaBump
      )
      .accounts({
        depositReceipt: depositReceiptPda,
        to: hackerDepositor.publicKey,
        relayer: relayer.publicKey,
      })
      .signers([relayer])
      .rpc();

      let error;
      try {

      const tx2 = await program.methods
      .deposit(
        new anchor.BN(ethDepositNonce), 
        new anchor.BN(amount),
        depositReceiptPdaBump
      )
      .accounts({
        depositReceipt: depositReceiptPda,
        to: hackerDepositor.publicKey,
        relayer: relayer.publicKey,
      })
      .signers([relayer])
      .rpc();
      } catch(err) {
        error = err;
      }


  // verify new balance for depositor
  const depositorBalance2 = await program.provider.connection.getBalance(hackerDepositor.publicKey);
  assert.ok(Number(depositorBalance2) === (amount) ); // this is what one deposit would get you
  assert.ok(error.message === "failed to send transaction: Transaction simulation failed: Error processing Instruction 0: custom program error: 0x0" )

  });

  it("makes a withdrawal", async () => {
    const amount = 2

    const signature = await program.provider.connection.requestAirdrop(withdrawer.publicKey, LAMPORTS_PER_SOL * 4)
    const latestBlockhash = await program.provider.connection.getLatestBlockhash();
    await program.provider.connection.confirmTransaction(
      {
        signature,
        ...latestBlockhash,
      },
      "confirmed"
    );

    const withdrawalNonce = 123457;
    const ethAddress = "0xc6992F09dfC7a752c15824dE698436cDFcfe40FC"
    const [withdrawalReceiptPda, withdrawalReceiptPdaBump ] = PublicKey.findProgramAddressSync(
      [
        Buffer.from("withdrawal"),
        new anchor.BN(withdrawalNonce).toArrayLike(Buffer, "le", 8),
      ],
      program.programId
    );

    try {
    const _withdrawal_txn = await program.methods.withdraw(
      ethAddress,
      new anchor.BN(withdrawalNonce), 
      new anchor.BN(amount),
      withdrawalReceiptPdaBump,
    ).accounts({
      withdrawer: withdrawer.publicKey,
      withdrawalReceipt: withdrawalReceiptPda,
      relayer: relayer.publicKey,
    })
    .signers([withdrawer])
    .rpc()

    } catch(err) {
      console.log(err)
    }
     
      
    const onchainPda = await program.account.withdrawalReceipt.fetch(withdrawalReceiptPda);
    interface ReadableWithdrawalReceipt {
      destinationAddress: String;
      withdrawalNonce: Number
      bump: Number;
      amount: Number;
    };
    const readable: ReadableWithdrawalReceipt = {
      bump: onchainPda.bump,
      destinationAddress: onchainPda.destinationAddress.toString(),
      withdrawalNonce: onchainPda.withdrawalNonce.toNumber(),
      amount: onchainPda.amount.toNumber(),
    };

    assert.ok(readable.withdrawalNonce === withdrawalNonce);
    assert.ok(readable.destinationAddress === ethAddress);
    assert.ok(readable.amount === amount);



  })
});
