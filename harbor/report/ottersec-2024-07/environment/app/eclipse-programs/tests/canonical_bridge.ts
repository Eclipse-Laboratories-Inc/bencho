import * as anchor from "@coral-xyz/anchor";
import { Program } from "@coral-xyz/anchor";
import { LAMPORTS_PER_SOL, PublicKey, Keypair } from "@solana/web3.js";
import { assert } from "chai";
import { CanonicalBridge } from "../target/types/canonical_bridge";
import * as fs from 'fs';

const readKeypairFromFile = (path: fs.PathOrFileDescriptor): Keypair => {
  try {
      const fileContents = fs.readFileSync(path, { encoding: 'utf8' });
      const secretKey = JSON.parse(fileContents);
      return Keypair.fromSecretKey(new Uint8Array(secretKey));
  } catch (error) {
      console.error('Failed to read keypair from file:', error);
      process.exit(1);
  }
};

const deriveConfigPda = (program): [anchor.web3.PublicKey, number] => {
  const [configPda, bump] = PublicKey.findProgramAddressSync(
    [
      Buffer.from('configure'),
    ],
    program.programId
  )
  return [configPda, bump]
}

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

const testkeypairPath = "./tests/T3STfZppYxqPCYS9fLoitN7RiADdRBsJ1c7rN3gNKTc.json"
const bossTestkeypairPath = "./tests/bobYFf6sXFHBk5ZUM3muhka4855fnc5tMg7pa3tFpVK.json"

describe("canonical_bridge",() => {
  // Configure the client to use the local cluster.
  anchor.setProvider(anchor.AnchorProvider.env());

  const program = anchor.workspace.CanonicalBridge as Program<CanonicalBridge>;
  const relayer = readKeypairFromFile(testkeypairPath);
  const depositor = anchor.web3.Keypair.generate();
  const withdrawer = anchor.web3.Keypair.generate();
  const hackerDepositor = anchor.web3.Keypair.generate();
  const [configPda, bump] = deriveConfigPda(program);
  const testAdminKeypair = readKeypairFromFile(bossTestkeypairPath);
  let ethDepositNonce = 123456;
  const amount = LAMPORTS_PER_SOL;
  const initConfig = async () => { 
    const signature = await program.provider.connection.requestAirdrop(testAdminKeypair.publicKey, LAMPORTS_PER_SOL * 5)
    const latestBlockhash = await program.provider.connection.getLatestBlockhash();
    await program.provider.connection.confirmTransaction(
      {
        signature,
        ...latestBlockhash,
      },
      "confirmed"
    );

    // see if the config exists, we get an error if it doesn't
    // create the config if we get that error.

    try {
      await program.account.configuration.fetch(configPda)
    } catch(err) {
      await program.methods.initConfig().accounts({
        configuration: configPda,
        authority: testAdminKeypair.publicKey,
      })
      .signers([testAdminKeypair])
      .rpc({ commitment: "confirmed"})
      .catch(err => console.log("init config error: ", err));
      // this can fail if the pda is already initialized
    }
  }
  beforeEach(async () => {
    await initConfig()
  })

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
        config: configPda,
        depositReceipt: depositReceiptPda,
        to: depositor.publicKey,
        relayer: relayer.publicKey,
      })
      .signers([relayer])
      .rpc();
    } catch(err) {
      const errorCode = err.error.errorCode.code
      assert.ok(errorCode === "ConstraintAddress")
    }
  })

  it("makes a deposit", async () => {

    ethDepositNonce = ethDepositNonce + 1
    const signature = await program.provider.connection.requestAirdrop(relayer.publicKey, LAMPORTS_PER_SOL * 3)
    const latestBlockhash = await program.provider.connection.getLatestBlockhash();
    await program.provider.connection.confirmTransaction(
      {
        signature,
        ...latestBlockhash,
      },
      "confirmed"
    );

    const [depositReceiptPda, depositReceiptPdaBump ] = deriveDepositPda(ethDepositNonce, program)
    const previousDepositorBalance = await program.provider.connection.getBalance(depositor.publicKey);
    try {

    const tx = await program.methods
      .deposit(
        new anchor.BN(ethDepositNonce), 
        new anchor.BN(amount),
        depositReceiptPdaBump
      )
      .accounts({
        config: configPda,
        depositReceipt: depositReceiptPda,
        to: depositor.publicKey,
        relayer: relayer.publicKey,
      })
      .signers([relayer])
      .rpc();
    } catch(err) {
      console.error(err)
    }

    // verify new balance for depositor
    const depositorBalance = await program.provider.connection.getBalance(depositor.publicKey);
    assert.ok(Number(depositorBalance) === (amount + Number(previousDepositorBalance)) );


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
    ethDepositNonce = ethDepositNonce + 2;

    const signature = await program.provider.connection.requestAirdrop(relayer.publicKey, LAMPORTS_PER_SOL * 4)
    const latestBlockhash = await program.provider.connection.getLatestBlockhash();
    await program.provider.connection.confirmTransaction(
      {
        signature,
        ...latestBlockhash,
      },
      "confirmed"
    );
    const sig = await program.provider.connection.requestAirdrop(testAdminKeypair.publicKey, LAMPORTS_PER_SOL * 4)
    await program.provider.connection.confirmTransaction(
      {
        signature: sig,
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
        config: configPda,
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
        config: configPda,
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

    const _withdrawal_txn = await program.methods.withdraw(
      ethAddress,
      new anchor.BN(withdrawalNonce), 
      new anchor.BN(amount),
      withdrawalReceiptPdaBump,
    ).accounts({
      withdrawer: withdrawer.publicKey,
      withdrawalReceipt: withdrawalReceiptPda,
      relayer: relayer.publicKey,
      config: configPda
    })
    .signers([withdrawer])
    .rpc()
    .catch(err => console.log(err));
     
      
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

  it("prevents withdrawals not being sent to the relayer", async () => {
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

    const withdrawalNonce = 123457 + 1;
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
      relayer: anchor.web3.Keypair.generate().publicKey,
      config: configPda,
    })
    .signers([withdrawer])
    .rpc()

    } catch(err) {
      assert(err.error.errorCode.code === 'ConstraintAddress')
    }

  })

  it("prevents deposits while paused", async () => {

      await program.methods
      .pauseDeposits()
      .accounts({ 
        configuration: configPda,
        authority: testAdminKeypair.publicKey,
        systemProgram: anchor.web3.SystemProgram.programId,
      })
      .signers([testAdminKeypair])
      .rpc()
      .catch(err => console.log(console.log("pause error: " , err)))

    const config = await program.account.configuration.fetch(configPda);
    assert(config.depositsPaused === true);

    ethDepositNonce = ethDepositNonce + 1
    const signature = await program.provider.connection.requestAirdrop(relayer.publicKey, LAMPORTS_PER_SOL * 3)
    const latestBlockhash = await program.provider.connection.getLatestBlockhash();
    await program.provider.connection.confirmTransaction(
      {
        signature,
        ...latestBlockhash,
      },
      "confirmed"
    );

    const [depositReceiptPda, depositReceiptPdaBump ] = deriveDepositPda(ethDepositNonce, program)
    let depositError = null;

    const tx = await program.methods
      .deposit(
        new anchor.BN(ethDepositNonce), 
        new anchor.BN(amount),
        depositReceiptPdaBump
      )
      .accounts({
        config: configPda,
        depositReceipt: depositReceiptPda,
        to: depositor.publicKey,
        relayer: relayer.publicKey,
      })
      .signers([relayer])
      .rpc()
      .catch((err) => {
        depositError = err;
      });
    assert(depositError.error.errorCode.code === "DepositPaused")

  })

  it("prevents withdrawals while paused", async () => {

      const amount = 1
  
      const signature = await program.provider.connection.requestAirdrop(withdrawer.publicKey, LAMPORTS_PER_SOL * 4)
      const latestBlockhash = await program.provider.connection.getLatestBlockhash();
      await program.provider.connection.confirmTransaction(
        {
          signature,
          ...latestBlockhash,
        },
        "confirmed"
      );
  
      const withdrawalNonce = 123457 + 98;
      const ethAddress = "0xc6992F09dfC7a752c15824dE698436cDFcfe40FC"
      const [withdrawalReceiptPda, withdrawalReceiptPdaBump ] = PublicKey.findProgramAddressSync(
        [
          Buffer.from("withdrawal"),
          new anchor.BN(withdrawalNonce).toArrayLike(Buffer, "le", 8),
        ],
        program.programId
      );


      await program.methods.pauseWithdrawals().accounts({
        configuration: configPda,
        authority: testAdminKeypair.publicKey,
        systemProgram: anchor.web3.SystemProgram.programId,
      })
      .signers([testAdminKeypair])
      .rpc()
      .catch(err => console.log("pause error: ", err));

      const config = await program.account.configuration.fetch(configPda);
      assert(config.withdrawalsPaused === true);
  
      let withdrawalError;
      await program.methods.withdraw(
        ethAddress,
        new anchor.BN(withdrawalNonce), 
        new anchor.BN(amount),
        withdrawalReceiptPdaBump,
      ).accounts({
        withdrawer: withdrawer.publicKey,
        withdrawalReceipt: withdrawalReceiptPda,
        relayer: relayer.publicKey,
        config: configPda
      })
      .signers([withdrawer])
      .rpc()
      .catch(err => withdrawalError = err);
  

      assert(withdrawalError.error.errorCode.code === "WithdrawalPaused")
    })
});
