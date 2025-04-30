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
(define-constant PERMISSION-NONE u0)            ;; 0000
(define-constant PERMISSION-READ u1)            ;; 0001
(define-constant PERMISSION-WRITE u2)           ;; 0010
(define-constant PERMISSION-ADMIN u4)           ;; 0100
(define-constant PERMISSION-SPECIAL u8)         ;; 1000
(define-constant PERMISSION-ALL u15)            ;; 1111

;; Data storage

;; Contract owner
(define-data-var contract-owner principal tx-sender)

;; Store registered contracts with their permission levels
(define-map registered-contracts 
  principal  ;; Contract principal
  {
    active: bool,              ;; Whether the contract is currently active
    permissions: uint,         ;; Bitwise permissions
    registration-time: uint,   ;; When the contract was registered
    updated-by: principal      ;; Who last updated this entry
  }
)

;; Store registered users with their permission levels
(define-map registered-users
  principal  ;; User principal
  {
    active: bool,              ;; Whether the user is currently active
    permissions: uint,         ;; Bitwise permissions
    registration-time: uint,   ;; When the user was registered
    updated-by: principal      ;; Who last updated this entry
  }
)

;; Store special role assignments
(define-map role-assignments
  { principal: principal, role: (string-ascii 32) }
  bool
)

;; Private functions

;; Helper function to check if the sender has admin permission
(define-private (is-admin (caller principal))
  (let (
    (admin-entry (unwrap-panic (get-user-info caller)))
  )
    (and 
      (get active admin-entry)
      (is-eq (bit-and (get permissions admin-entry) PERMISSION-ADMIN) PERMISSION-ADMIN)
    )
  )
)

;; Helper function to check if the sender is the contract owner
(define-private (is-owner (caller principal))
  (is-eq caller (var-get contract-owner))
)

;; Helper function to check if a permission flag is valid
(define-private (is-valid-permission (permission uint))
  (<= permission PERMISSION-ALL)
)

;; Read-only functions

;; Check if a contract is registered and has the specified permission
(define-read-only (contract-has-permission (contract-principal principal) (permission uint))
  (let (
    (contract-entry (map-get? registered-contracts contract-principal))
  )
    (match contract-entry
      entry (and 
              (get active entry)
              (is-eq (bit-and (get permissions entry) permission) permission)
            )
      false
    )
  )
)

;; Check if a user is registered and has the specified permission
(define-read-only (user-has-permission (user-principal principal) (permission uint))
  (let (
    (user-entry (map-get? registered-users user-principal))
  )
    (match user-entry
      entry (and 
              (get active entry)
              (is-eq (bit-and (get permissions entry) permission) permission)
            )
      false
    )
  )
)

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
(define-read-only (has-role (principal-to-check principal) (role (string-ascii 32)))
  (match (map-get? role-assignments { principal: principal-to-check, role: role })
    is-assigned is-assigned
    false
  )
)

;; Public functions

;; Register a new contract with the specified permissions
;; Only contract owner or admins can register contracts
(define-public (register-contract (contract-principal principal) (permissions uint))
  (begin
    ;; Check authorization
    (asserts! (or (is-owner tx-sender) (is-admin tx-sender)) ERR-NOT-AUTHORIZED)
    
    ;; Validate permissions
    (asserts! (is-valid-permission permissions) ERR-INVALID-PERMISSION)
    
    ;; Check if already registered
    (asserts! (is-none (map-get? registered-contracts contract-principal)) ERR-ALREADY-REGISTERED)
    
    ;; Register the contract
    (map-set registered-contracts contract-principal 
      {
        active: true,
        permissions: permissions,
        registration-time: block-height,
        updated-by: tx-sender
      }
    )
    
    (ok true)
  )
)

;; Register a new user with the specified permissions
;; Only contract owner or admins can register users
(define-public (register-user (user-principal principal) (permissions uint))
  (begin
    ;; Check authorization
    (asserts! (or (is-owner tx-sender) (is-admin tx-sender)) ERR-NOT-AUTHORIZED)
    
    ;; Validate permissions
    (asserts! (is-valid-permission permissions) ERR-INVALID-PERMISSION)
    
    ;; Check if already registered
    (asserts! (is-none (map-get? registered-users user-principal)) ERR-ALREADY-REGISTERED)
    
    ;; Register the user
    (map-set registered-users user-principal 
      {
        active: true,
        permissions: permissions,
        registration-time: block-height,
        updated-by: tx-sender
      }
    )
    
    (ok true)
  )
)

;; Update contract permissions
(define-public (update-contract-permissions (contract-principal principal) (permissions uint))
  (begin
    ;; Check authorization
    (asserts! (or (is-owner tx-sender) (is-admin tx-sender)) ERR-NOT-AUTHORIZED)
    
    ;; Validate permissions
    (asserts! (is-valid-permission permissions) ERR-INVALID-PERMISSION)
    
    ;; Check if registered
    (asserts! (is-some (map-get? registered-contracts contract-principal)) ERR-NOT-REGISTERED)
    
    ;; Update the contract permissions
    (let (
      (contract-entry (unwrap-panic (map-get? registered-contracts contract-principal)))
    )
      (map-set registered-contracts contract-principal 
        (merge contract-entry {
          permissions: permissions,
          updated-by: tx-sender
        })
      )
    )
    
    (ok true)
  )
)

;; Update user permissions
(define-public (update-user-permissions (user-principal principal) (permissions uint))
  (begin
    ;; Check authorization
    (asserts! (or (is-owner tx-sender) (is-admin tx-sender)) ERR-NOT-AUTHORIZED)
    
    ;; Validate permissions
    (asserts! (is-valid-permission permissions) ERR-INVALID-PERMISSION)
    
    ;; Check if registered
    (asserts! (is-some (map-get? registered-users user-principal)) ERR-NOT-REGISTERED)
    
    ;; Update the user permissions
    (let (
      (user-entry (unwrap-panic (map-get? registered-users user-principal)))
    )
      (map-set registered-users user-principal 
        (merge user-entry {
          permissions: permissions,
          updated-by: tx-sender
        })
      )
    )
    
    (ok true)
  )
)

;; Disable a contract
(define-public (disable-contract (contract-principal principal))
  (begin
    ;; Check authorization
    (asserts! (or (is-owner tx-sender) (is-admin tx-sender)) ERR-NOT-AUTHORIZED)
    
    ;; Check if registered
    (asserts! (is-some (map-get? registered-contracts contract-principal)) ERR-NOT-REGISTERED)
    
    ;; Disable the contract
    (let (
      (contract-entry (unwrap-panic (map-get? registered-contracts contract-principal)))
    )
      (map-set registered-contracts contract-principal 
        (merge contract-entry {
          active: false,
          updated-by: tx-sender
        })
      )
    )
    
    (ok true)
  )
)

;; Disable a user
(define-public (disable-user (user-principal principal))
  (begin
    ;; Check authorization
    (asserts! (or (is-owner tx-sender) (is-admin tx-sender)) ERR-NOT-AUTHORIZED)
    
    ;; Check if registered
    (asserts! (is-some (map-get? registered-users user-principal)) ERR-NOT-REGISTERED)
    
    ;; Disable the user
    (let (
      (user-entry (unwrap-panic (map-get? registered-users user-principal)))
    )
      (map-set registered-users user-principal 
        (merge user-entry {
          active: false,
          updated-by: tx-sender
        })
      )
    )
    
    (ok true)
  )
)

;; Enable a previously disabled contract
(define-public (enable-contract (contract-principal principal))
  (begin
    ;; Check authorization
    (asserts! (or (is-owner tx-sender) (is-admin tx-sender)) ERR-NOT-AUTHORIZED)
    
    ;; Check if registered
    (asserts! (is-some (map-get? registered-contracts contract-principal)) ERR-NOT-REGISTERED)
    
    ;; Enable the contract
    (let (
      (contract-entry (unwrap-panic (map-get? registered-contracts contract-principal)))
    )
      (map-set registered-contracts contract-principal 
        (merge contract-entry {
          active: true,
          updated-by: tx-sender
        })
      )
    )
    
    (ok true)
  )
)

;; Enable a previously disabled user
(define-public (enable-user (user-principal principal))
  (begin
    ;; Check authorization
    (asserts! (or (is-owner tx-sender) (is-admin tx-sender)) ERR-NOT-AUTHORIZED)
    
    ;; Check if registered
    (asserts! (is-some (map-get? registered-users user-principal)) ERR-NOT-REGISTERED)
    
    ;; Enable the user
    (let (
      (user-entry (unwrap-panic (map-get? registered-users user-principal)))
    )
      (map-set registered-users user-principal 
        (merge user-entry {
          active: true,
          updated-by: tx-sender
        })
      )
    )
    
    (ok true)
  )
)

;; Assign a role to a principal
(define-public (assign-role (principal-to-assign principal) (role (string-ascii 32)))
  (begin
    ;; Check authorization
    (asserts! (or (is-owner tx-sender) (is-admin tx-sender)) ERR-NOT-AUTHORIZED)
    
    ;; Assign the role
    (map-set role-assignments { principal: principal-to-assign, role: role } true)
    
    (ok true)
  )
)

;; Remove a role from a principal
(define-public (remove-role (principal-to-unassign principal) (role (string-ascii 32)))
  (begin
    ;; Check authorization
    (asserts! (or (is-owner tx-sender) (is-admin tx-sender)) ERR-NOT-AUTHORIZED)
    
    ;; Remove the role
    (map-set role-assignments { principal: principal-to-unassign, role: role } false)
    
    (ok true)
  )
)

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

;; Check authentication - callable by other contracts to validate permissions
(define-public (check-auth (caller principal) (permission uint))
  (begin
    (asserts! (or 
               (is-owner caller)
               (is-admin caller)
               (user-has-permission caller permission)
               (contract-has-permission caller permission)
              ) ERR-PERMISSION-DENIED)
    (ok true)
  )
)