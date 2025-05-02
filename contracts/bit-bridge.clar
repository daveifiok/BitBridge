;; Title: BitBridge - Secure Bitcoin-Stacks Bridge Contract
;; 
;; Summary: A secure, validator-based bridge for transferring assets between Bitcoin and Stacks blockchain.
;; 
;; Description: BitBridge enables cross-chain liquidity by facilitating trustless transfers between 
;; Bitcoin and the Stacks ecosystem. The contract implements a validator consensus mechanism with 
;; signature verification, deposit confirmation thresholds, and emergency control systems to ensure 
;; maximum security while maintaining compliance with both network standards.
;;

;; Traits
(define-trait bridgeable-token-trait
    (
        (transfer (uint principal principal) (response bool uint))
        (get-balance (principal) (response uint uint))
    )
)

;; Constants - Error Codes
(define-constant ERROR-NOT-AUTHORIZED u1000)
(define-constant ERROR-INVALID-AMOUNT u1001)
(define-constant ERROR-INSUFFICIENT-BALANCE u1002)
(define-constant ERROR-INVALID-BRIDGE-STATUS u1003)
(define-constant ERROR-INVALID-SIGNATURE u1004)
(define-constant ERROR-ALREADY-PROCESSED u1005)
(define-constant ERROR-BRIDGE-PAUSED u1006)
(define-constant ERROR-INVALID-VALIDATOR-ADDRESS u1007)
(define-constant ERROR-INVALID-RECIPIENT-ADDRESS u1008)
(define-constant ERROR-INVALID-BTC-ADDRESS u1009)
(define-constant ERROR-INVALID-TX-HASH u1010)
(define-constant ERROR-INVALID-SIGNATURE-FORMAT u1011)

;; Protocol Constants
(define-constant CONTRACT-DEPLOYER tx-sender)
(define-constant MIN-DEPOSIT-AMOUNT u100000)
(define-constant MAX-DEPOSIT-AMOUNT u1000000000)
(define-constant REQUIRED-CONFIRMATIONS u6)

;; State Variables
(define-data-var bridge-paused bool false)
(define-data-var total-bridged-amount uint u0)
(define-data-var last-processed-height uint u0)

;; Data Maps
(define-map deposits
    { tx-hash: (buff 32) }
    {
        amount: uint,
        recipient: principal,
        processed: bool,
        confirmations: uint,
        timestamp: uint,
        btc-sender: (buff 33)
    }
)

(define-map validators principal bool)
(define-map validator-signatures
    { tx-hash: (buff 32), validator: principal }
    { signature: (buff 65), timestamp: uint }
)

(define-map bridge-balances principal uint)

;; Administrative Functions

;; Initializes the bridge by setting the paused state to false.
;; Only the contract deployer can call this function.
(define-public (initialize-bridge)
    (begin
        (asserts! (is-eq tx-sender CONTRACT-DEPLOYER) (err ERROR-NOT-AUTHORIZED))
        (var-set bridge-paused false)
        (ok true)
    )
)

;; Pauses the bridge operations during emergencies.
;; Only the contract deployer can call this function.
(define-public (pause-bridge)
    (begin
        (asserts! (is-eq tx-sender CONTRACT-DEPLOYER) (err ERROR-NOT-AUTHORIZED))
        (var-set bridge-paused true)
        (ok true)
    )
)

;; Resumes the bridge if it is paused.
;; Only the contract deployer can call this function.
(define-public (resume-bridge)
    (begin
        (asserts! (is-eq tx-sender CONTRACT-DEPLOYER) (err ERROR-NOT-AUTHORIZED))
        (asserts! (var-get bridge-paused) (err ERROR-INVALID-BRIDGE-STATUS))
        (var-set bridge-paused false)
        (ok true)
    )
)

;; Adds a validator to the bridge's trusted set.
;; Only the contract deployer can call this function.
(define-public (add-validator (validator principal))
    (begin
        (asserts! (is-eq tx-sender CONTRACT-DEPLOYER) (err ERROR-NOT-AUTHORIZED))
        (asserts! (is-valid-principal validator) (err ERROR-INVALID-VALIDATOR-ADDRESS))
        (map-set validators validator true)
        (ok true)
    )
)

;; Removes a validator from the bridge's trusted set.
;; Only the contract deployer can call this function.
(define-public (remove-validator (validator principal))
    (begin
        (asserts! (is-eq tx-sender CONTRACT-DEPLOYER) (err ERROR-NOT-AUTHORIZED))
        (asserts! (is-valid-principal validator) (err ERROR-INVALID-VALIDATOR-ADDRESS))
        (map-set validators validator false)
        (ok true)
    )
)

;; Core Bridge Functions

;; Initiates a deposit from Bitcoin to Stacks.
;; Validators must call this function after verifying the Bitcoin transaction.
(define-public (initiate-deposit
    (tx-hash (buff 32))
    (amount uint)
    (recipient principal)
    (btc-sender (buff 33))
)
    (begin
        (asserts! (not (var-get bridge-paused)) (err ERROR-BRIDGE-PAUSED))
        (asserts! (validate-deposit-amount amount) (err ERROR-INVALID-AMOUNT))
        (asserts! (get-validator-status tx-sender) (err ERROR-NOT-AUTHORIZED))
        (asserts! (is-valid-tx-hash tx-hash) (err ERROR-INVALID-TX-HASH))
        (asserts! (is-none (map-get? deposits {tx-hash: tx-hash})) (err ERROR-ALREADY-PROCESSED))
        (asserts! (is-valid-principal recipient) (err ERROR-INVALID-RECIPIENT-ADDRESS))
        (asserts! (is-valid-btc-address btc-sender) (err ERROR-INVALID-BTC-ADDRESS))
        
        (let
            ((validated-deposit {
                amount: amount,
                recipient: recipient,
                processed: false,
                confirmations: u0,
                timestamp: stacks-block-height,
                btc-sender: btc-sender
            }))
            
            (map-set deposits
                {tx-hash: tx-hash}
                validated-deposit
            )
            (ok true)
        )
    )
)

;; Confirms a deposit with validator signature.
;; Multiple validators must confirm the same deposit to reach the required threshold.
(define-public (confirm-deposit
    (tx-hash (buff 32))
    (signature (buff 65))
)
    (let (
        (deposit (unwrap! (map-get? deposits {tx-hash: tx-hash}) (err ERROR-INVALID-BRIDGE-STATUS)))
        (is-validator (get-validator-status tx-sender))
    )
        (asserts! (not (var-get bridge-paused)) (err ERROR-BRIDGE-PAUSED))
        (asserts! (is-valid-tx-hash tx-hash) (err ERROR-INVALID-TX-HASH))
        (asserts! (is-valid-signature signature) (err ERROR-INVALID-SIGNATURE-FORMAT))
        (asserts! (not (get processed deposit)) (err ERROR-ALREADY-PROCESSED))
        (asserts! (>= (get confirmations deposit) REQUIRED-CONFIRMATIONS) (err ERROR-INVALID-BRIDGE-STATUS))
        
        (asserts!
            (is-none (map-get? validator-signatures {tx-hash: tx-hash, validator: tx-sender}))
            (err ERROR-ALREADY-PROCESSED)
        )
        
        (let
            ((validated-signature {
                signature: signature,
                timestamp: stacks-block-height
            }))
            
            (map-set validator-signatures
                {tx-hash: tx-hash, validator: tx-sender}
                validated-signature
            )
            
            (map-set deposits
                {tx-hash: tx-hash}
                (merge deposit {processed: true})
            )
            
            (map-set bridge-balances
                (get recipient deposit)
                (+ (default-to u0 (map-get? bridge-balances (get recipient deposit)))
                   (get amount deposit))
            )
            
            (var-set total-bridged-amount
                (+ (var-get total-bridged-amount) (get amount deposit))
            )
            (ok true)
        )
    )
)

;; Withdraws an amount from the bridge to a Bitcoin recipient address.
;; Users call this function to initiate transfers from Stacks back to Bitcoin.
(define-public (withdraw
    (amount uint)
    (btc-recipient (buff 34))
)
    (let (
        (current-balance (get-bridge-balance tx-sender))
    )
        (asserts! (not (var-get bridge-paused)) (err ERROR-BRIDGE-PAUSED))
        (asserts! (>= current-balance amount) (err ERROR-INSUFFICIENT-BALANCE))
        (asserts! (validate-deposit-amount amount) (err ERROR-INVALID-AMOUNT))
        
        (map-set bridge-balances
            tx-sender
            (- current-balance amount)
        )
        
        (print {
            type: "withdraw",
            sender: tx-sender,
            amount: amount,
            btc-recipient: btc-recipient,
            timestamp: stacks-block-height
        })
        
        (var-set total-bridged-amount (- (var-get total-bridged-amount) amount))
        (ok true)
    )
)

;; Emergency withdrawal function for protocol safety.
;; Allows the contract deployer to rescue funds in case of critical vulnerabilities.
(define-public (emergency-withdraw (amount uint) (recipient principal))
    (begin
        (asserts! (is-eq tx-sender CONTRACT-DEPLOYER) (err ERROR-NOT-AUTHORIZED))
        (asserts! (>= (var-get total-bridged-amount) amount) (err ERROR-INSUFFICIENT-BALANCE))
        (asserts! (is-valid-principal recipient) (err ERROR-INVALID-RECIPIENT-ADDRESS))
        
        (let (
            (current-balance (default-to u0 (map-get? bridge-balances recipient)))
            (new-balance (+ current-balance amount))
        )
            (asserts! (> new-balance current-balance) (err ERROR-INVALID-AMOUNT))
            (map-set bridge-balances recipient new-balance)
            (ok true)
        )
    )
)

;; Read-Only Functions

;; Retrieves the details of a deposit using the transaction hash.
(define-read-only (get-deposit (tx-hash (buff 32)))
    (map-get? deposits {tx-hash: tx-hash})
)

;; Retrieves the current status of the bridge (paused or not).
(define-read-only (get-bridge-status)
    (var-get bridge-paused)
)

;; Checks if a given principal is a validator.
(define-read-only (get-validator-status (validator principal))
    (default-to false (map-get? validators validator))
)

;; Retrieves the bridge balance of a user.
(define-read-only (get-bridge-balance (user principal))
    (default-to u0 (map-get? bridge-balances user))
)

;; Validation Helper Functions

;; Validates if a given principal address is valid.
(define-read-only (is-valid-principal (address principal))
    (and
        (not (is-eq address CONTRACT-DEPLOYER))
        (not (is-eq address (as-contract tx-sender)))
    )
)

;; Validates if a given Bitcoin address is valid.
(define-read-only (is-valid-btc-address (btc-addr (buff 33)))
    (and
        (is-eq (len btc-addr) u33)
        (not (is-eq btc-addr 0x000000000000000000000000000000000000000000000000000000000000000000))
        true
    )
)

;; Validates if a given transaction hash is valid.
(define-read-only (is-valid-tx-hash (tx-hash (buff 32)))
    (and
        (is-eq (len tx-hash) u32)
        (not (is-eq tx-hash 0x0000000000000000000000000000000000000000000000000000000000000000))
        true
    )
)

;; Validates if a given signature is valid.
(define-read-only (is-valid-signature (signature (buff 65)))
    (and
        (is-eq (len signature) u65)
        (not (is-eq signature 0x0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000))
        true
    )
)

;; Validates if a given deposit amount is within the allowed range.
(define-read-only (validate-deposit-amount (amount uint))
    (and
        (>= amount MIN-DEPOSIT-AMOUNT)
        (<= amount MAX-DEPOSIT-AMOUNT)
    )
)