;; token-adapter.clar
;; This contract provides a standardized interface for different token implementations
;; to interact with the token-sync system. It serves as an abstraction layer that translates
;; between specific token mechanics and the standardized protocols used by the synchronization framework.
;; Error codes
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-INVALID-TOKEN (err u101))
(define-constant ERR-INVALID-AMOUNT (err u102))
(define-constant ERR-TRANSFER-FAILED (err u103))
(define-constant ERR-ALREADY-REGISTERED (err u104))
(define-constant ERR-NOT-REGISTERED (err u105))
(define-constant ERR-OPERATION-FAILED (err u106))
;; Data maps and variables
;; Tracks registered token contracts with their interfaces
;; Maps token-id -> token-contract-address
(define-map registered-tokens
  { token-id: (string-ascii 32) }
  {
    contract-address: principal,
    token-type: (string-ascii 10),
  }
)
;; Tracks which principals are authorized to register new tokens
(define-map token-registrars
  { registrar: principal }
  { is-approved: bool }
)
;; Contract admin - has rights to add registrars
(define-data-var contract-owner principal tx-sender)
;; Total number of registered tokens
(define-data-var token-count uint u0)
;; Private functions
;; Checks if a principal is authorized to register tokens
(define-private (is-authorized (account principal))
  (default-to false
    (get is-approved (map-get? token-registrars { registrar: account }))
  )
)

;; Checks if the principal is the contract owner
(define-private (is-contract-owner)
  (is-eq tx-sender (var-get contract-owner))
)

;; Checks if a token is registered
(define-private (is-token-registered (token-id (string-ascii 32)))
  (is-some (map-get? registered-tokens { token-id: token-id }))
)

;; Validates a token transfer operation based on token type
;; Returns (ok true) if validation passes, (err ...) otherwise
(define-private (validate-token-operation
    (token-id (string-ascii 32))
    (amount uint)
  )
  (let ((token-info (map-get? registered-tokens { token-id: token-id })))
    (if (is-none token-info)
      ERR-INVALID-TOKEN
      (if (< amount u0)
        ERR-INVALID-AMOUNT
        (ok true)
      )
    )
  )
)

;; Read-only functions
;; Returns information about a registered token
(define-read-only (get-token-info (token-id (string-ascii 32)))
  (map-get? registered-tokens { token-id: token-id })
)

;; Checks if a token is supported by the adapter
(define-read-only (is-token-supported (token-id (string-ascii 32)))
  (is-some (map-get? registered-tokens { token-id: token-id }))
)

;; Returns the total number of registered tokens
(define-read-only (get-token-count)
  (var-get token-count)
)

;; Checks if an account is authorized to register tokens
(define-read-only (check-authorization (account principal))
  (is-authorized account)
)

;; Public functions
;; Register a new token to be managed by the adapter
;; Only authorized registrars can register tokens
(define-public (register-token
    (token-id (string-ascii 32))
    (contract-address principal)
    (token-type (string-ascii 10))
  )
  (begin
    ;; Check that the caller is authorized
    (asserts! (is-authorized tx-sender) ERR-NOT-AUTHORIZED)
    ;; Check that the token isn't already registered
    (asserts! (not (is-token-registered token-id)) ERR-ALREADY-REGISTERED)
    ;; Check that token type is valid (sip-009, sip-010, or custom)
    (asserts!
      (or
        (is-eq token-type "sip-009")
        (is-eq token-type "sip-010")
        (is-eq token-type "custom")
      )
      ERR-INVALID-TOKEN
    )
    ;; Register the token
    (map-set registered-tokens { token-id: token-id } {
      contract-address: contract-address,
      token-type: token-type,
    })
    ;; Increment token count
    (var-set token-count (+ (var-get token-count) u1))
    (ok true)
  )
)

;; Deregister a token from the adapter
;; Only authorized registrars can deregister tokens
(define-public (deregister-token (token-id (string-ascii 32)))
  (begin
    ;; Check that the caller is authorized
    (asserts! (is-authorized tx-sender) ERR-NOT-AUTHORIZED)
    ;; Check that the token is registered
    (asserts! (is-token-registered token-id) ERR-NOT-REGISTERED)
    ;; Deregister the token
    (map-delete registered-tokens { token-id: token-id })
    ;; Decrement token count
    (var-set token-count (- (var-get token-count) u1))
    (ok true)
  )
)

;; Add a new token registrar
;; Only the contract owner can add registrars
(define-public (add-registrar (registrar principal))
  (begin
    (asserts! (is-contract-owner) ERR-NOT-AUTHORIZED)
    (map-set token-registrars { registrar: registrar } { is-approved: true })
    (ok true)
  )
)

;; Remove a token registrar
;; Only the contract owner can remove registrars
(define-public (remove-registrar (registrar principal))
  (begin
    (asserts! (is-contract-owner) ERR-NOT-AUTHORIZED)
    (map-set token-registrars { registrar: registrar } { is-approved: false })
    (ok true)
  )
)

;; Transfer contract ownership
;; Only the current owner can transfer ownership
(define-public (transfer-ownership (new-owner principal))
  (begin
    (asserts! (is-contract-owner) ERR-NOT-AUTHORIZED)
    (var-set contract-owner new-owner)
    (ok true)
  )
)
