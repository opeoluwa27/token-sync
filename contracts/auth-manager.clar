;; auth-manager
;;
;; This contract implements the authentication and permission management system
;; for the token-sync ecosystem. It maintains a registry of authorized contracts
;; and users with their respective permissions, providing a centralized security
;; layer to protect sensitive operations across the token synchronization platform.
;; Error codes
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-ALREADY-REGISTERED (err u101))
(define-constant ERR-NOT-REGISTERED (err u102))
(define-constant ERR-PERMISSION-DENIED (err u103))
(define-constant ERR-CONTRACT-OWNER-ONLY (err u104))
(define-constant ERR-INVALID-PERMISSION (err u105))
;; Permission bit flags
;; Permissions are managed through bit flags to allow compact storage and easy checking
(define-constant PERMISSION-NONE u0) ;; 0000
(define-constant PERMISSION-READ u1) ;; 0001
(define-constant PERMISSION-WRITE u2) ;; 0010
(define-constant PERMISSION-ADMIN u4) ;; 0100
(define-constant PERMISSION-SPECIAL u8) ;; 1000
(define-constant PERMISSION-ALL u15) ;; 1111
;; Data storage
;; Contract owner
(define-data-var contract-owner principal tx-sender)
;; Store registered contracts with their permission levels
(define-map registered-contracts
  principal ;; Contract principal
  {
    active: bool, ;; Whether the contract is currently active
    permissions: uint, ;; Bitwise permissions
    registration-time: uint, ;; When the contract was registered
    updated-by: principal, ;; Who last updated this entry
  }
)
;; Store registered users with their permission levels
(define-map registered-users
  principal ;; User principal
  {
    active: bool, ;; Whether the user is currently active
    permissions: uint, ;; Bitwise permissions
    registration-time: uint, ;; When the user was registered
    updated-by: principal, ;; Who last updated this entry
  }
)
;; Store special role assignments
(define-map role-assignments
  {
    principal: principal,
    role: (string-ascii 32),
  }
  bool
)
;; Private functions
;; Helper function to check if the sender has admin permission
;; Helper function to check if the sender is the contract owner
(define-private (is-owner (caller principal))
  (is-eq caller (var-get contract-owner))
)

;; Helper function to check if a permission flag is valid
(define-private (is-valid-permission (permission uint))
  (<= permission PERMISSION-ALL)
)

;; Read-only functions
;; Get contract information
(define-read-only (get-contract-info (contract-principal principal))
  (match (map-get? registered-contracts contract-principal)
    entry (ok entry)
    (err ERR-NOT-REGISTERED)
  )
)

;; Get user information
(define-read-only (get-user-info (user-principal principal))
  (match (map-get? registered-users user-principal)
    entry (ok entry)
    (err ERR-NOT-REGISTERED)
  )
)

;; Check if a principal has a specific role
(define-read-only (has-role
    (principal-to-check principal)
    (role (string-ascii 32))
  )
  (match (map-get? role-assignments {
    principal: principal-to-check,
    role: role,
  })
    is-assigned
    is-assigned
    false
  )
)

;; Public functions
;; Register a new contract with the specified permissions
;; Register a new user with the specified permissions
;; Only contract owner or admins can register users
;; Transfer contract ownership - only current owner can do this
(define-public (transfer-ownership (new-owner principal))
  (begin
    ;; Check authorization
    (asserts! (is-owner tx-sender) ERR-CONTRACT-OWNER-ONLY)
    ;; Transfer ownership
    (var-set contract-owner new-owner)
    (ok true)
  )
)
