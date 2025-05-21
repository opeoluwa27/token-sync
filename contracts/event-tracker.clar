;; event-tracker
;;
;; This contract records and manages events related to token synchronization in the token-sync system.
;; It provides a transparent and immutable audit trail of significant actions such as token registrations,
;; synchronization operations, and permission changes. The historical record enables auditability, 
;; helps with troubleshooting, and allows applications to react to token state changes.
;; Error constants
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-INVALID-EVENT-TYPE (err u101))
(define-constant ERR-EVENT-NOT-FOUND (err u102))
(define-constant ERR-INVALID-PARAMS (err u103))
;; Event types
(define-constant EVENT-TYPE-TOKEN-REGISTRATION u1)
(define-constant EVENT-TYPE-TOKEN-SYNC u2)
(define-constant EVENT-TYPE-PERMISSION-CHANGE u3)
(define-constant EVENT-TYPE-CONFIG-UPDATE u4)
;; Data space definitions
;; Main events data map to store all events
(define-map events
  { event-id: uint }
  {
    event-type: uint,
    timestamp: uint,
    initiator: principal,
    token-id: (optional uint),
    target-contract: (optional principal),
    details: (optional (string-ascii 256)),
  }
)
;; Track events per token ID for efficient querying
(define-map token-events
  { token-id: uint }
  { event-ids: (list 100 uint) }
)
;; Track events per principal for efficient querying
(define-map principal-events
  { principal-id: principal }
  { event-ids: (list 100 uint) }
)
;; Counter to generate unique event IDs
(define-data-var next-event-id uint u1)
;; Authorized contracts/principals that can record events
(define-map authorized-recorders
  { recorder: principal }
  { authorized: bool }
)
;; Initial contract deployer/admin
(define-data-var contract-owner principal tx-sender)
(define-private (is-valid-event-type (event-type uint))
  (or
    (is-eq event-type EVENT-TYPE-TOKEN-REGISTRATION)
    (is-eq event-type EVENT-TYPE-TOKEN-SYNC)
    (is-eq event-type EVENT-TYPE-PERMISSION-CHANGE)
    (is-eq event-type EVENT-TYPE-CONFIG-UPDATE)
  )
)

(define-private (add-event-to-token
    (token-id uint)
    (event-id uint)
  )
  (let (
      (current-events (default-to { event-ids: (list) }
        (map-get? token-events { token-id: token-id })
      ))
      (updated-events (unwrap-panic (as-max-len? (append (get event-ids current-events) event-id) u100)))
    )
    (map-set token-events { token-id: token-id } { event-ids: updated-events })
  )
)

(define-private (add-event-to-principal
    (principal-id principal)
    (event-id uint)
  )
  (let (
      (current-events (default-to { event-ids: (list) }
        (map-get? principal-events { principal-id: principal-id })
      ))
      (updated-events (unwrap-panic (as-max-len? (append (get event-ids current-events) event-id) u100)))
    )
    (map-set principal-events { principal-id: principal-id } { event-ids: updated-events })
  )
)

;; Read-only functions
(define-read-only (get-event (event-id uint))
  (let ((event (map-get? events { event-id: event-id })))
    (if (is-none event)
      ERR-EVENT-NOT-FOUND
      (ok (unwrap-panic event))
    )
  )
)

(define-read-only (get-events-by-token (token-id uint))
  (let ((token-event-list (map-get? token-events { token-id: token-id })))
    (if (is-none token-event-list)
      (ok (list))
      (ok (get event-ids (unwrap-panic token-event-list)))
    )
  )
)

(define-read-only (get-events-by-principal (principal-id principal))
  (let ((principal-event-list (map-get? principal-events { principal-id: principal-id })))
    (if (is-none principal-event-list)
      (ok (list))
      (ok (get event-ids (unwrap-panic principal-event-list)))
    )
  )
)

(define-read-only (get-events-by-type (event-type uint))
  (if (not (is-valid-event-type event-type))
    ERR-INVALID-EVENT-TYPE
    (ok event-type) ;; Placeholder - in Clarity we can't efficiently filter all events by type
    ;; This would be implemented in off-chain indexing
  )
)

(define-read-only (get-latest-event-id)
  (ok (- (var-get next-event-id) u1))
)

;; Public functions
(define-public (record-event
    (event-type uint)
    (token-id (optional uint))
    (target-contract (optional principal))
    (details (optional (string-ascii 256)))
  )
  (let (
      (caller tx-sender)
      (event-id (var-get next-event-id))
      (current-time block-height) ;; Using block height as timestamp
    )
    ;; Check authorization
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
    ;; Validate event type
    (asserts! (is-valid-event-type event-type) ERR-INVALID-EVENT-TYPE)
    ;; Store the event
    (map-set events { event-id: event-id } {
      event-type: event-type,
      timestamp: current-time,
      initiator: caller,
      token-id: token-id,
      target-contract: target-contract,
      details: details,
    })
    ;; Update the indexes if token-id is provided
    (if (is-some token-id)
      (add-event-to-token (unwrap-panic token-id) event-id)
      true
    )
    ;; Add event to principal's history
    (add-event-to-principal caller event-id)
    ;; Increment event ID counter
    (var-set next-event-id (+ event-id u1))
    (ok event-id)
  )
)

(define-public (add-authorized-recorder (recorder principal))
  (begin
    ;; Only contract owner can add authorized recorders
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
    ;; Add the recorder to the authorized list
    (map-set authorized-recorders { recorder: recorder } { authorized: true })
    ;; Record this permission change as an event
    (record-event EVENT-TYPE-PERMISSION-CHANGE none (some recorder)
      (some "Recorder authorized")
    )
  )
)

(define-public (remove-authorized-recorder (recorder principal))
  (begin
    ;; Only contract owner can remove authorized recorders
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
    ;; Remove the recorder from the authorized list
    (map-set authorized-recorders { recorder: recorder } { authorized: false })
    ;; Record this permission change as an event
    (record-event EVENT-TYPE-PERMISSION-CHANGE none (some recorder)
      (some "Recorder authorization revoked")
    )
  )
)

;; Initialize contract by authorizing the deployer
(map-set authorized-recorders { recorder: tx-sender } { authorized: true })
