# BitBridge

**Secure Bitcoin ↔ Stacks Bridge Smart Contract**

## Overview

**BitBridge** is a secure, validator-based cross-chain bridge enabling decentralized, verifiable asset transfers between the **Bitcoin** and **Stacks** blockchains. By leveraging a multi-signature consensus mechanism, deposit verification, and carefully scoped administrative control, BitBridge maintains high levels of trust, transparency, and resilience.

## Key Features

* 🔒 **Validator-Based Consensus**: Validators must cooperatively verify and sign Bitcoin transactions before initiating bridging.
* 🔁 **Two-Way Transfers**: Supports Bitcoin-to-Stacks deposits and Stacks-to-Bitcoin withdrawals.
* 🧾 **Deposit Verification**: Requires minimum confirmations and multi-signature validation for security.
* ⚠️ **Emergency Controls**: Pausable bridge logic and admin rescue paths for protocol safety.
* 📜 **Standards Compliant**: Implements a `bridgeable-token-trait` interface for token transfers on Stacks.

## Smart Contract Architecture

### Traits

```clojure
bridgeable-token-trait
```

Defines a minimal interface for tokens used within the bridge:

* `transfer`
* `get-balance`

### Constants

* `ERROR-*`: Error codes for structured failure handling.
* `MIN/MAX-DEPOSIT-AMOUNT`: Range validation for Bitcoin deposits.
* `REQUIRED-CONFIRMATIONS`: Minimum validator confirmations required.


### State Variables

* `bridge-paused`: Emergency control toggle.
* `total-bridged-amount`: Cumulative amount processed through the bridge.
* `last-processed-height`: Last block height for tracking operations.

### Data Maps

* `deposits`: Records deposit metadata (`tx-hash`, `recipient`, `amount`, etc.).
* `validators`: Maintains a registry of authorized validator accounts.
* `validator-signatures`: Tracks unique validator signatures per deposit.
* `bridge-balances`: Internal balances for users on the Stacks chain.

## Public Functions

### Administrative

* `initialize-bridge`: Enables bridge functionality post-deployment.
* `pause-bridge` / `resume-bridge`: Emergency pause/resume mechanisms.
* `add-validator` / `remove-validator`: Manage validator set.

### Core Logic

* `initiate-deposit(tx-hash, amount, recipient, btc-sender)`

  * Called by validators after detecting valid BTC transactions.
* `confirm-deposit(tx-hash, signature)`

  * Validators confirm BTC deposits through signatures.
* `withdraw(amount, btc-recipient)`

  * Users burn their Stacks balance to initiate BTC redemption.
* `emergency-withdraw(amount, recipient)`

  * Contract deployer can rescue funds if a critical issue arises.

## Read-Only Functions

* `get-deposit(tx-hash)`: Retrieves a specific deposit record.
* `get-bridge-status()`: Returns paused state.
* `get-validator-status(validator)`: Checks validator permissions.
* `get-bridge-balance(user)`: Retrieves user’s bridge balance.

## Validation Helpers

* `is-valid-principal(address)`: Ensures recipient addresses are not the deployer or contract.
* `is-valid-btc-address(btc-addr)`: Checks for valid BTC address format.
* `is-valid-tx-hash(tx-hash)`: Validates Bitcoin transaction hashes.
* `is-valid-signature(signature)`: Ensures signature length/format is valid.
* `validate-deposit-amount(amount)`: Range checks for deposits.

## Security Design

* **Multi-Signature Assurance**: Prevents single-point validator compromise.
* **Zero-Trust Assumptions**: Validators are independent and accountable via on-chain records.
* **Emergency Controls**: Deployer can pause bridge and rescue funds in emergencies.
* **Immutable Recordkeeping**: All events and signatures logged on-chain.

## Events (via `print` statements)

* `withdraw`: Logs details of withdrawals to Bitcoin, including sender, amount, and recipient BTC address.

## Usage Workflow

1. **Deposit Initiation** (Validator):

   * Calls `initiate-deposit` with BTC transaction metadata.

2. **Deposit Confirmation** (Multiple Validators):

   * Calls `confirm-deposit` to contribute signature-based confirmation.

3. **Token Bridging** (Stacks User):

   * Receives tokens upon confirmation threshold.

4. **Withdrawal** (Stacks User):

   * Burns balance to initiate BTC-side release (off-chain process).

5. **Emergency Recovery** (Admin):

   * Deployer may invoke `emergency-withdraw` to prevent permanent loss.

## Deployment and Permissions

* **Only the deployer** can:

  * Pause/resume the bridge
  * Add/remove validators
  * Perform emergency withdrawals

## Requirements

* Clarity-enabled smart contract deployment (Stacks blockchain)
* Active set of validator nodes capable of detecting BTC transactions and interacting with the contract
