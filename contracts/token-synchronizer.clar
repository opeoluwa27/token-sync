;; token-synchronizer
;; 
;; This contract manages synchronization between different token representations across
;; the Stacks blockchain, ensuring consistent state and preventing double-spending.
;; It provides a secure framework for maintaining parity between related tokenized assets
;; by tracking relationships and executing controlled synchronization operations.

;; Error codes
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-TOKEN-NOT-REGISTERED (err u101))
(define-constant ERR-INVALID-TOKEN-PAIR (err u102))
(define-constant ERR-SYNC-FAILED (err u103))
(define-constant ERR-INVALID-AMOUNT (err u104))
(define-constant ERR-SYNC-IN-PROGRESS (err u105))
(define-constant ERR-TOKEN-ALREADY-REGISTERED (err u106))

;; Data space definitions

;; Stores the contract owner address
(define-data-var contract-owner principal tx-sender)

;; Records authorized operators who can manage synchronization
(define-map authorized-operators principal bool)

;; Tracks registered token contracts that can participate in synchronization
(define-map token-contracts 
  { token-id: (string-ascii 32) } 
  { contract-address: principal, active: bool, last-sync-height: uint })

;; Maps token pairs that can be synchronized with each other
(define-map token-sync-pairs
  { primary-token: (string-ascii 32), secondary-token: (string-ascii 32) }
  { enabled: bool, conversion-rate: uint, last-sync-block: uint })

;; Tracks ongoing synchronization operations
(define-map sync-operations
  { sync-id: (string-ascii 64) }
  { initiator: principal, primary-token: (string-ascii 32), secondary-token: (string-ascii 32), 
    amount: uint, status: (string-ascii 10), initiated-at: uint })

;; Records sync history for auditing and reference
(define-map sync-history
  { sync-id: (string-ascii 64) }
  { initiator: principal, primary-token: (string-ascii 32), secondary-token: (string-ascii 32), 
    amount: uint, status: (string-ascii 10), completed-at: uint })

;; Private functions

;; Check if caller is the contract owner
(define-private (is-contract-owner)
  (is-eq tx-sender (var-get contract-owner)))

;; Check if caller is an authorized operator
(define-private (is-authorized-operator)
  (default-to false (map-get? authorized-operators tx-sender)))

;; Check if caller has permission to perform admin operations
(define-private (check-is-authorized)
  (if (or (is-contract-owner) (is-authorized-operator))
    true
    false))

;; Check if token is registered in the system
(define-private (is-token-registered (token-id (string-ascii 32)))
  (is-some (map-get? token-contracts { token-id: token-id })))

;; Check if token pair is valid for synchronization
(define-private (is-valid-token-pair (primary-token (string-ascii 32)) (secondary-token (string-ascii 32)))
  (is-some (map-get? token-sync-pairs { primary-token: primary-token, secondary-token: secondary-token })))

;; Read-only functions

;; Get token contract details
(define-read-only (get-token-contract (token-id (string-ascii 32)))
  (map-get? token-contracts { token-id: token-id }))

;; Get token pair synchronization details
(define-read-only (get-token-pair-details (primary-token (string-ascii 32)) (secondary-token (string-ascii 32)))
  (map-get? token-sync-pairs { primary-token: primary-token, secondary-token: secondary-token }))

;; Get synchronization operation status
(define-read-only (get-sync-operation (sync-id (string-ascii 64)))
  (map-get? sync-operations { sync-id: sync-id }))

;; Get synchronization history details
(define-read-only (get-sync-history (sync-id (string-ascii 64)))
  (map-get? sync-history { sync-id: sync-id }))

;; Check if a principal is an authorized operator
(define-read-only (check-operator-status (operator principal))
  (default-to false (map-get? authorized-operators operator)))

;; Public functions

;; Register a new token contract for synchronization
(define-public (register-token-contract (token-id (string-ascii 32)) (contract-address principal))
  (begin
    (asserts! (check-is-authorized) ERR-NOT-AUTHORIZED)
    (asserts! (not (is-token-registered token-id)) ERR-TOKEN-ALREADY-REGISTERED)
    
    (map-set token-contracts
      { token-id: token-id }
      { contract-address: contract-address, active: true, last-sync-height: u0 })
    
    (ok true)))

;; Update token contract status
(define-public (update-token-contract-status (token-id (string-ascii 32)) (active bool))
  (begin
    (asserts! (check-is-authorized) ERR-NOT-AUTHORIZED)
    (asserts! (is-token-registered token-id) ERR-TOKEN-NOT-REGISTERED)
    
    (let ((current-contract (unwrap-panic (map-get? token-contracts { token-id: token-id }))))
      (map-set token-contracts
        { token-id: token-id }
        (merge current-contract { active: active }))
      
      (ok true))))

;; Configure a synchronization pair between two tokens
(define-public (configure-token-sync-pair 
                (primary-token (string-ascii 32)) 
                (secondary-token (string-ascii 32)) 
                (enabled bool) 
                (conversion-rate uint))
  (begin
    (asserts! (check-is-authorized) ERR-NOT-AUTHORIZED)
    (asserts! (is-token-registered primary-token) ERR-TOKEN-NOT-REGISTERED)
    (asserts! (is-token-registered secondary-token) ERR-TOKEN-NOT-REGISTERED)
    (asserts! (not (is-eq primary-token secondary-token)) ERR-INVALID-TOKEN-PAIR)
    (asserts! (> conversion-rate u0) ERR-INVALID-AMOUNT)
    
    (map-set token-sync-pairs
      { primary-token: primary-token, secondary-token: secondary-token }
      { enabled: enabled, conversion-rate: conversion-rate, last-sync-block: block-height })
    
    (ok true)))

;; Add a new authorized operator
(define-public (add-operator (operator principal))
  (begin
    (asserts! (is-contract-owner) ERR-NOT-AUTHORIZED)
    (map-set authorized-operators operator true)
    (ok true)))

;; Remove an authorized operator
(define-public (remove-operator (operator principal))
  (begin
    (asserts! (is-contract-owner) ERR-NOT-AUTHORIZED)
    (map-delete authorized-operators operator)
    (ok true)))

;; Execute a synchronization operation
(define-public (execute-sync (sync-id (string-ascii 64)))
  (let
    ((sync-op (map-get? sync-operations { sync-id: sync-id })))
    
    ;; Validate the operation exists
    (asserts! (is-some sync-op) ERR-SYNC-FAILED)
    (asserts! (is-eq (get status (unwrap-panic sync-op)) "PENDING") ERR-SYNC-FAILED)
    
    (let 
      ((unwrapped-op (unwrap-panic sync-op))
       (primary-token (get primary-token (unwrap-panic sync-op)))
       (secondary-token (get secondary-token (unwrap-panic sync-op)))
       (pair-details (unwrap-panic (map-get? token-sync-pairs 
         { primary-token: primary-token, secondary-token: secondary-token }))))
      
      ;; Update the operation status to in progress
      (map-set sync-operations
        { sync-id: sync-id }
        (merge unwrapped-op { status: "PROCESSING" }))
      
      ;; Process the sync (in a real implementation, this would include token transfers)
      
      ;; Update token pair last sync block
      (map-set token-sync-pairs
        { primary-token: primary-token, secondary-token: secondary-token }
        (merge pair-details { last-sync-block: block-height }))
      
      ;; Record completed operation in history
      (map-set sync-history
        { sync-id: sync-id }
        { initiator: (get initiator unwrapped-op), 
          primary-token: primary-token, 
          secondary-token: secondary-token, 
          amount: (get amount unwrapped-op), 
          status: "COMPLETED", 
          completed-at: block-height })
      
      ;; Remove from active operations
      (map-delete sync-operations { sync-id: sync-id })
      
      (ok true))))

;; Cancel a pending synchronization operation
(define-public (cancel-sync (sync-id (string-ascii 64)))
  (let
    ((sync-op (map-get? sync-operations { sync-id: sync-id })))
    
    ;; Validate the operation exists and is still pending
    (asserts! (is-some sync-op) ERR-SYNC-FAILED)
    (asserts! (is-eq (get status (unwrap-panic sync-op)) "PENDING") ERR-SYNC-FAILED)
    
    ;; Check authorization - only initiator or contract admins can cancel
    (asserts! (or 
               (is-eq tx-sender (get initiator (unwrap-panic sync-op)))
               (check-is-authorized)) 
              ERR-NOT-AUTHORIZED)
    
    ;; Record cancellation in history
    (map-set sync-history
      { sync-id: sync-id }
      { initiator: (get initiator (unwrap-panic sync-op)), 
        primary-token: (get primary-token (unwrap-panic sync-op)), 
        secondary-token: (get secondary-token (unwrap-panic sync-op)), 
        amount: (get amount (unwrap-panic sync-op)), 
        status: "CANCELLED", 
        completed-at: block-height })
    
    ;; Remove from active operations
    (map-delete sync-operations { sync-id: sync-id })
    
    (ok true)))

;; Transfer contract ownership
(define-public (transfer-ownership (new-owner principal))
  (begin
    (asserts! (is-contract-owner) ERR-NOT-AUTHORIZED)
    (var-set contract-owner new-owner)
    (ok true)))