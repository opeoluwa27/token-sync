;; token-registry
;; 
;; This contract serves as the central registry for maintaining relationships between original tokens
;; and their representations across different contracts in the token-sync ecosystem. It acts as the
;; source of truth for token mappings, enabling verification of token authenticity and state tracking.

;; Error codes
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-TOKEN-ALREADY-REGISTERED (err u101))
(define-constant ERR-TOKEN-NOT-FOUND (err u102))
(define-constant ERR-INVALID-TOKEN-TYPE (err u103))
(define-constant ERR-REPRESENTATION-ALREADY-EXISTS (err u104))
(define-constant ERR-REPRESENTATION-NOT-FOUND (err u105))
(define-constant ERR-INVALID-PARAMETERS (err u106))

;; Token types
(define-constant TOKEN-TYPE-FUNGIBLE u1)
(define-constant TOKEN-TYPE-NON-FUNGIBLE u2)

;; Contract owner
(define-data-var contract-owner principal tx-sender)

;; Data structures

;; Stores the primary information about registered tokens
;; Maps token-id -> {name, token-type, creator, original-contract}
(define-map tokens
  { token-id: (string-ascii 64) }
  {
    name: (string-utf8 64),
    token-type: uint,
    creator: principal,
    original-contract: principal,
    metadata-uri: (optional (string-utf8 256)),
    created-at: uint
  }
)

;; Tracks token representations across different contracts
;; Maps token-id + contract -> {representation-id, is-active}
(define-map token-representations
  { 
    token-id: (string-ascii 64),
    contract-principal: principal
  }
  {
    representation-id: (string-ascii 64),
    is-active: bool,
    created-at: uint
  }
)

;; Reverse lookup to find original token from a representation
;; Maps contract + representation-id -> token-id
(define-map representation-to-token
  {
    contract-principal: principal,
    representation-id: (string-ascii 64)
  }
  { token-id: (string-ascii 64) }
)

;; Private functions

;; Check if caller is contract owner
(define-private (is-contract-owner)
  (is-eq tx-sender (var-get contract-owner))
)

;; Get current block height as timestamp
(define-private (get-current-time)
  block-height
)

;; Public functions

;; Register a new token in the registry
;; Only the contract owner can register tokens to maintain integrity
(define-public (register-token
                (token-id (string-ascii 64))
                (name (string-utf8 64))
                (token-type uint)
                (original-contract principal)
                (metadata-uri (optional (string-utf8 256))))
  (begin
    ;; Check authorization
    (asserts! (is-contract-owner) ERR-NOT-AUTHORIZED)
    
    ;; Validate token type
    (asserts! (or (is-eq token-type TOKEN-TYPE-FUNGIBLE) 
                 (is-eq token-type TOKEN-TYPE-NON-FUNGIBLE))
             ERR-INVALID-TOKEN-TYPE)
    
    ;; Check if token already exists
    
    ;; Register the token
    (map-set tokens
      { token-id: token-id }
      {
        name: name,
        token-type: token-type,
        creator: tx-sender,
        original-contract: original-contract,
        metadata-uri: metadata-uri,
        created-at: (get-current-time)
      }
    )
    
    (ok true)
  )
)

;; Update token representation status (activate/deactivate)
(define-public (update-representation-status
                (token-id (string-ascii 64))
                (contract-principal principal)
                (is-active bool))
  (let (
    (representation (unwrap! (map-get? token-representations 
                              { token-id: token-id, contract-principal: contract-principal })
                            ERR-REPRESENTATION-NOT-FOUND))
  )
    ;; Check authorization
    (asserts! (is-contract-owner) ERR-NOT-AUTHORIZED)
    
    ;; Update the status
    (map-set token-representations
      { token-id: token-id, contract-principal: contract-principal }
      (merge representation { is-active: is-active })
    )
    
    (ok true)
  )
)

;; Update token metadata
(define-public (update-token-metadata
                (token-id (string-ascii 64))
                (metadata-uri (string-utf8 256)))
  (let (
    (token (unwrap! (map-get? tokens { token-id: token-id }) ERR-TOKEN-NOT-FOUND))
  )
    ;; Check authorization
    (asserts! (is-contract-owner) ERR-NOT-AUTHORIZED)
    
    ;; Update the metadata
    (map-set tokens
      { token-id: token-id }
      (merge token { metadata-uri: (some metadata-uri) })
    )
    
    (ok true)
  )
)

;; Transfer ownership of the contract
(define-public (transfer-ownership (new-owner principal))
  (begin
    (asserts! (is-contract-owner) ERR-NOT-AUTHORIZED)
    (asserts! (not (is-eq new-owner tx-sender)) ERR-INVALID-PARAMETERS)
    
    (var-set contract-owner new-owner)
    (ok true)
  )
)

;; Read-only functions

;; Get token details
(define-read-only (get-token (token-id (string-ascii 64)))
  (map-get? tokens { token-id: token-id })
)

;; Get token representation in a specific contract
(define-read-only (get-token-representation
                    (token-id (string-ascii 64))
                    (contract-principal principal))
  (map-get? token-representations { token-id: token-id, contract-principal: contract-principal })
)

;; Get contract owner
(define-read-only (get-contract-owner)
  (var-get contract-owner)
)