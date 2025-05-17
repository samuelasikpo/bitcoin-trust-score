;; Bitcoin Trust Score - Decentralized Reputation System for Stacks
;;
;; A trustless, decentralized reputation management system for Stacks ecosystem
;; that allows entities to build verifiable reputation based on on-chain actions.
;;
;; This contract implements:
;;  - Decentralized identity management
;;  - Action-based reputation scoring
;;  - Time-decay mechanisms for maintaining relevance
;;  - Verification capabilities for third-party applications

;; Error Constants
(define-constant ERR-UNAUTHORIZED (err u100))
(define-constant ERR-INVALID-PARAMETERS (err u101))
(define-constant ERR-IDENTITY-EXISTS (err u102))
(define-constant ERR-IDENTITY-NOT-FOUND (err u103))
(define-constant ERR-INSUFFICIENT-REPUTATION (err u104))
(define-constant ERR-MAX-REPUTATION-REACHED (err u105))
(define-constant ERR-ACTION-EXISTS (err u106))
(define-constant ERR-ACTION-NOT-FOUND (err u107))
(define-constant ERR-NOT-ADMIN (err u108))
(define-constant ERR-NOT-ACTIVE (err u109))

;; System Constants
(define-constant MAX-REPUTATION-SCORE u1000)
(define-constant MIN-REPUTATION-SCORE u0)
(define-constant DEFAULT-STARTING-REPUTATION u50)
(define-constant DEFAULT-DECAY-RATE u10) ;; 10% decay per period
(define-constant MINIMUM_DID_LENGTH u5)

;; State Variables
(define-data-var contract-owner principal tx-sender)
(define-data-var contract-active bool true)
(define-data-var decay-rate uint DEFAULT-DECAY-RATE)
(define-data-var decay-period uint u10000) ;; In blocks
(define-data-var starting-reputation uint DEFAULT-STARTING-REPUTATION)

;; Storage Maps
(define-map identities
  { owner: principal }
  {
    did: (string-ascii 50), ;; Decentralized Identity
    reputation-score: uint,
    created-at: uint,
    last-updated: uint,
    last-decay: uint,
    total-actions: uint,
    active: bool,
  }
)

(define-map reputation-actions
  { action-type: (string-ascii 50) }
  {
    multiplier: uint,
    description: (string-ascii 100),
    active: bool,
  }
)

(define-map reputation-history
  {
    owner: principal,
    tx-id: uint,
  }
  {
    action-type: (string-ascii 50),
    previous-score: uint,
    new-score: uint,
    timestamp: uint,
    block-height: uint,
  }
)

;; Administrative Functions

;; Set a new contract owner
(define-public (set-contract-owner (new-owner principal))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) (err ERR-NOT-ADMIN))
    (var-set contract-owner new-owner)
    (ok true)
  )
)

;; Set contract active state
(define-public (set-contract-active (active bool))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) (err ERR-NOT-ADMIN))
    (var-set contract-active active)
    (ok true)
  )
)

;; Set reputation decay parameters
(define-public (set-decay-parameters
    (new-rate uint)
    (new-period uint)
  )
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) (err ERR-NOT-ADMIN))
    (asserts! (<= new-rate u100) (err ERR-INVALID-PARAMETERS))
    (asserts! (> new-period u0) (err ERR-INVALID-PARAMETERS))
    (var-set decay-rate new-rate)
    (var-set decay-period new-period)
    (ok true)
  )
)

;; Set default starting reputation for new identities
(define-public (set-starting-reputation (new-value uint))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) (err ERR-NOT-ADMIN))
    (asserts! (<= new-value MAX-REPUTATION-SCORE) (err ERR-INVALID-PARAMETERS))
    (var-set starting-reputation new-value)
    (ok true)
  )
)

;; Reputation Action Management

;; Add a new reputation action type
(define-public (add-reputation-action
    (action-type (string-ascii 50))
    (multiplier uint)
    (description (string-ascii 100))
  )
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) (err ERR-NOT-ADMIN))
    (asserts!
      (is-none (map-get? reputation-actions { action-type: action-type }))
      (err ERR-ACTION-EXISTS)
    )
    (map-set reputation-actions { action-type: action-type } {
      multiplier: multiplier,
      description: description,
      active: true,
    })
    (ok true)
  )
)

;; Update an existing reputation action
(define-public (update-reputation-action
    (action-type (string-ascii 50))
    (multiplier uint)
    (description (string-ascii 100))
    (active bool)
  )
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) (err ERR-NOT-ADMIN))
    (asserts!
      (is-some (map-get? reputation-actions { action-type: action-type }))
      (err ERR-ACTION-NOT-FOUND)
    )
    (map-set reputation-actions { action-type: action-type } {
      multiplier: multiplier,
      description: description,
      active: active,
    })
    (ok true)
  )
)

;; Initialize default reputation actions
(define-public (initialize-reputation-actions)
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) (err ERR-NOT-ADMIN))
    (map-set reputation-actions { action-type: "governance-vote" } {
      multiplier: u5,
      description: "Participation in governance voting",
      active: true,
    })
    (map-set reputation-actions { action-type: "contract-fulfillment" } {
      multiplier: u10,
      description: "Successful completion of a smart contract agreement",
      active: true,
    })
    (map-set reputation-actions { action-type: "community-contribution" } {
      multiplier: u7,
      description: "Contribution to community projects or initiatives",
      active: true,
    })
    (map-set reputation-actions { action-type: "validation" } {
      multiplier: u3,
      description: "Validation of network transactions or data",
      active: true,
    })
    (map-set reputation-actions { action-type: "content-creation" } {
      multiplier: u6,
      description: "Creation of valuable content on the platform",
      active: true,
    })
    (ok true)
  )
)

;; Helper Functions

;; Validate that an owner exists and is the sender
(define-private (is-valid-owner (owner principal))
  (and
    (is-some (map-get? identities { owner: owner }))
    (is-eq owner tx-sender)
  )
)