;; Title: CurateTrustChain - Integrated Decentralized Curation and Reputation Protocol
;; Summary: A Bitcoin-native content curation and reputation system for Stacks ecosystem
;; Description: Combines CurateChain and Bitcoin Trust Score into a unified protocol
;; allowing decentralized content submission, appraisal, rewards, and reputation tracking.


;; Core Constants
(define-constant PROTOCOL_ADMINISTRATOR tx-sender)
(define-constant ERR_UNAUTHORIZED_ACCESS (err u100))
(define-constant ERR_INVALID_SUBMISSION (err u101))
(define-constant ERR_DUPLICATE_ENTRY (err u102))
(define-constant ERR_NONEXISTENT_ITEM (err u103))
(define-constant ERR_INADEQUATE_BALANCE (err u104))
(define-constant ERR_INVALID_TOPIC (err u105))
(define-constant ERR_INVALID_FLAG (err u106))
(define-constant ERR_OVERFLOW (err u107))
(define-constant ERR_INVALID_APPRAISAL (err u108))
(define-constant ERR_INVALID_ITEM_ID (err u109))
(define-constant ERR_NOT_ACTIVE (err u110))

(define-constant MIN_HYPERLINK_LENGTH u10)
(define-constant MAX_UINT u340282366920938463463374607431768211455)
(define-constant MAX_REPUTATION_SCORE u1000)
(define-constant MIN_REPUTATION_SCORE u0)
(define-constant DEFAULT_STARTING_REPUTATION u50)
(define-constant DEFAULT_DECAY_RATE u10)
(define-constant MINIMUM_DID_LENGTH u5)


;; State Variables
(define-data-var submission-charge uint u10)
(define-data-var aggregate-submissions uint u0)
(define-data-var content-topics (list 10 (string-ascii 20)) (list "Technology" "Science" "Art" "Politics" "Sports"))
(define-data-var contract-owner principal tx-sender)
(define-data-var contract-active bool true)
(define-data-var decay-rate uint DEFAULT_DECAY_RATE)
(define-data-var decay-period uint u10000)
(define-data-var starting-reputation uint DEFAULT_STARTING_REPUTATION)


;; Data Storage Maps

;; Content Curation
(define-map curated-items 
  { item-identifier: uint } 
  { originator: principal
    headline: (string-ascii 100)
    hyperlink: (string-ascii 200)
    topic: (string-ascii 20)
    publication-epoch: uint
    appraisals: int
    gratuities: uint
    flags: uint
  }
)

(define-map participant-appraisals 
  { participant: principal, item-identifier: uint } 
  { appraisal: int }
)

(define-map participant-credibility
  { participant: principal }
  { metric: int }
)

;; Reputation System
(define-map identities
  { owner: principal }
  { did: (string-ascii 50)
    reputation-score: uint
    created-at: uint
    last-updated: uint
    last-decay: uint
    total-actions: uint
    active: bool
  }
)

(define-map reputation-actions
  { action-type: (string-ascii 50) }
  { multiplier: uint
    description: (string-ascii 100)
    active: bool
  }
)

(define-map reputation-history
  { owner: principal, tx-id: uint }
  { action-type: (string-ascii 50)
    previous-score: uint
    new-score: uint
    timestamp: uint
    block-height: uint
  }
)


;; Private Helper Functions

(define-private (item-exists (item-identifier uint))
  (is-some (map-get? curated-items { item-identifier: item-identifier }))
)

(define-private (not-none (item (optional {
    originator: principal
    headline: (string-ascii 100)
    hyperlink: (string-ascii 200)
    topic: (string-ascii 20)
    publication-epoch: uint
    appraisals: int
    gratuities: uint
    flags: uint
  })))
  (is-some item)
)

(define-private (retrieve-item-if-valid (id uint))
  (match (map-get? curated-items { item-identifier: id })
    item (if (>= (get appraisals item) 0) (some item) none)
    none
  )
)

(define-private (enumerate (n uint))
  (let ((limit (if (> n u10) u10 n)))
    (list
      (if (>= limit u1) u1 u0)
      (if (>= limit u2) u2 u0)
      (if (>= limit u3) u3 u0)
      (if (>= limit u4) u4 u0)
      (if (>= limit u5) u5 u0)
      (if (>= limit u6) u6 u0)
      (if (>= limit u7) u7 u0)
      (if (>= limit u8) u8 u0)
      (if (>= limit u9) u9 u0)
      (if (>= limit u10) u10 u0)
    )
  )
)

(define-private (is-non-zero (n uint))
  (not (is-eq n u0))
)

(define-private (get-identity-field (owner principal))
  (map-get? identities { owner: owner })
)

(define-private (should-decay (last-decay uint))
  (>= (- stacks-block-height last-decay) (var-get decay-period))
)

(define-private (get-action-multiplier (action-type (string-ascii 50)))
  (default-to u0
    (get multiplier (map-get? reputation-actions { action-type: action-type }))
  )
)

(define-private (is-action-active (action-type (string-ascii 50)))
  (default-to false
    (get active (map-get? reputation-actions { action-type: action-type }))
  )
)

(define-private (log-reputation-change
    (owner principal)
    (action-type (string-ascii 50))
    (previous-score uint)
    (new-score uint)
  )
  (map-set reputation-history {
    owner: owner
    tx-id: stacks-block-height
  } {
    action-type: action-type
    previous-score: previous-score
    new-score: new-score
    timestamp: burn-block-height
    block-height: stacks-block-height
  })
)

(define-private (decay-reputation-internal (owner principal))
  (let ((current-identity (default-to {
          did: ""
          reputation-score: u0
          created-at: u0
          last-updated: u0
          last-decay: u0
          total-actions: u0
          active: false
        }
        (map-get? identities { owner: owner })
      ))
      (current-score (get reputation-score current-identity))
      (decay-amount (/ (* current-score (var-get decay-rate)) u100))
      (updated-score (if (> current-score decay-amount)
        (- current-score decay-amount)
        MIN_REPUTATION_SCORE
      ))
  )
    (map-set identities { owner: owner }
      (merge current-identity {
        reputation-score: updated-score
        last-updated: stacks-block-height
        last-decay: stacks-block-height
      })
    )
    (log-reputation-change owner "decay" current-score updated-score)
    true
  )
)


;; Public Content Curation Functions

(define-public (contribute-item (headline (string-ascii 100)) (hyperlink (string-ascii 200)) (topic (string-ascii 20)))
  (let ((item-identifier (+ (var-get aggregate-submissions) u1)))
    (asserts! (and (>= (len headline) u1) (>= (len hyperlink) MIN_HYPERLINK_LENGTH) (>= (len topic) u1)) ERR_INVALID_SUBMISSION)
    (asserts! (> item-identifier (var-get aggregate-submissions)) ERR_OVERFLOW)
    (asserts! (is-some (index-of (var-get content-topics) topic)) ERR_INVALID_TOPIC)
    (asserts! (>= (stx-get-balance tx-sender) (var-get submission-charge)) ERR_INADEQUATE_BALANCE)
    (try! (stx-transfer? (var-get submission-charge) tx-sender PROTOCOL_ADMINISTRATOR))
    (map-set curated-items
      { item-identifier: item-identifier }
      { originator: tx-sender
        headline: headline
        hyperlink: hyperlink
        topic: topic
        publication-epoch: stacks-block-height
        appraisals: 0
        gratuities: u0
        flags: u0
      }
    )
    (var-set aggregate-submissions item-identifier)
    (print { type: "new-item", item-identifier: item-identifier, originator: tx-sender })
    (ok item-identifier)
  )
)

(define-public (appraise-item (item-identifier uint) (appraisal int))
  (let ((previous-appraisal (default-to 0 (get appraisal (map-get? participant-appraisals { participant: tx-sender, item-identifier: item-identifier }))))
        (target-item (unwrap! (map-get? curated-items { item-identifier: item-identifier }) ERR_NONEXISTENT_ITEM))
        (appraiser-standing (default-to { metric: 0 } (map-get? participant-credibility { participant: tx-sender })))
  )
    (asserts! (item-exists item-identifier) ERR_NONEXISTENT_ITEM)
    (asserts! (or (is-eq appraisal 1) (is-eq appraisal -1)) ERR_INVALID_APPRAISAL)
    (map-set participant-appraisals
      { participant: tx-sender, item-identifier: item-identifier }
      { appraisal: appraisal }
    )
    (map-set curated-items
      { item-identifier: item-identifier }
      (merge target-item { appraisals: (+ (get appraisals target-item) (- appraisal previous-appraisal)) })
    )
    (map-set participant-credibility
      { participant: tx-sender }
      { metric: (+ (get metric appraiser-standing) appraisal) }
    )
    (print { type: "appraisal", item-identifier: item-identifier, appraiser: tx-sender, appraisal: appraisal })
    (ok true)
  )
)

(define-public (reward-originator (item-identifier uint) (gratuity-amount uint))
  (let ((target-item (unwrap! (map-get? curated-items { item-identifier: item-identifier }) ERR_NONEXISTENT_ITEM)))
    (asserts! (>= (stx-get-balance tx-sender) gratuity-amount) ERR_INADEQUATE_BALANCE)
    (map-set curated-items
      { item-identifier: item-identifier }
      (merge target-item { gratuities: (+ (get gratuities target-item) gratuity-amount) })
    )
    (try! (stx-transfer? gratuity-amount tx-sender (get originator target-item)))
    (print { type: "reward", item-identifier: item-identifier, from: tx-sender, to: (get originator target-item), amount: gratuity-amount })
    (ok true)
  )
)

(define-public (flag-item (item-identifier uint))
  (let ((target-item (unwrap! (map-get? curated-items { item-identifier: item-identifier }) ERR_NONEXISTENT_ITEM)))
    (asserts! (not (is-eq (get originator target-item) tx-sender)) ERR_INVALID_FLAG)
    (map-set curated-items
      { item-identifier: item-identifier }
      (merge target-item { flags: (+ (get flags target-item) u1) })
    )
    (print { type: "flag", item-identifier: item-identifier, flagger: tx-sender })
    (ok true)
  )
)


;; Public Reputation Functions

(define-public (create-identity (did (string-ascii 50)))
  (let ((sender tx-sender)
        (current-block-height stacks-block-height))
    (asserts! (var-get contract-active) ERR_NOT_ACTIVE)
    (asserts! (is-none (map-get? identities { owner: sender })) ERR_DUPLICATE_ENTRY)
    (asserts! (> (len did) MINIMUM_DID_LENGTH) ERR_INVALID_PARAMETERS)
    (map-set identities { owner: sender } {
      did: did
      reputation-score: (var-get starting-reputation)
      created-at: current-block-height
      last-updated: current-block-height
      last-decay: current-block-height
      total-actions: u0
      active: true
    })
    (ok did)
  )
)

(define-public (update-reputation-score (action-type (string-ascii 50)))
  (let ((owner tx-sender)
        (current-identity (unwrap! (map-get? identities { owner: owner }) ERR_NONEXISTENT_ITEM))
        (current-score (get reputation-score current-identity))
        (action-multiplier (get-action-multiplier action-type))
        (total-actions (+ (get total-actions current-identity) u1))
  )
    (asserts! (var-get contract-active) ERR_NOT_ACTIVE)
    (asserts! (get active current-identity) ERR_UNAUTHORIZED_ACCESS)
    (asserts! (is-some (map-get? reputation-actions { action-type: action-type })) ERR_INVALID_PARAMETERS)
    (asserts! (is-action-active action-type) ERR_INVALID_PARAMETERS)
    (if (should-decay (get last-decay current-identity))
      (decay-reputation-internal owner)
      true
    )
    (let ((updated-identity (unwrap! (map-get? identities { owner: owner }) ERR_NONEXISTENT_ITEM))
          (updated-current-score (get reputation-score updated-identity))
          (new-score (if (< (+ updated-current-score action-multiplier) MAX_REPUTATION_SCORE)
                        (+ updated-current-score action-multiplier)
                        MAX_REPUTATION_SCORE)))
      (map-set identities { owner: owner }
        (merge updated-identity { reputation-score: new-score last-updated: stacks-block-height total-actions: total-actions })
      )
      (log-reputation-change owner action-type updated-current-score new-score)
      (ok new-score)
    )
  )
)

(define-public (decay-reputation)
  (let ((owner tx-sender)
        (current-identity (unwrap! (map-get? identities { owner: owner }) ERR_NONEXISTENT_ITEM)))
    (asserts! (var-get contract-active) ERR_NOT_ACTIVE)
    (asserts! (get active current-identity) ERR_UNAUTHORIZED_ACCESS)
    (asserts! (should-decay (get last-decay current-identity)) ERR_INVALID_PARAMETERS)
    (decay-reputation-internal owner)
    (let ((updated-identity (unwrap! (map-get? identities { owner: owner }) ERR_NONEXISTENT_ITEM)))
      (ok (get reputation-score updated-identity))
    )
  )
)

;; Admin Functions (Fee, Topics, Ownership, Contract State, Reputation Actions)

(define-public (adjust-submission-charge (new-charge uint))
  (asserts! (is-eq tx-sender PROTOCOL_ADMINISTRATOR) ERR_UNAUTHORIZED_ACCESS)
  (asserts! (<= new-charge MAX_UINT) ERR_OVERFLOW)
  (var-set submission-charge new-charge)
  (ok true)
)

(define-public (introduce-topic (new-topic (string-ascii 20)))
  (asserts! (is-eq tx-sender PROTOCOL_ADMINISTRATOR) ERR_UNAUTHORIZED_ACCESS)
  (asserts! (< (len (var-get content-topics)) u10) ERR_INVALID_TOPIC)
  (asserts! (>= (len new-topic) u1) ERR_INVALID_TOPIC)
  (var-set content-topics (unwrap-panic (as-max-len? (append (var-get content-topics) new-topic) u10)))
  (ok true)
)

(define-public (expunge-item (item-identifier uint))
  (asserts! (is-eq tx-sender PROTOCOL_ADMINISTRATOR) ERR_UNAUTHORIZED_ACCESS)
  (asserts! (item-exists item-identifier) ERR_NONEXISTENT_ITEM)
  (map-delete curated-items { item-identifier: item-identifier })
  (ok true)
)

(define-public (set-contract-owner (new-owner principal))
  (asserts! (is-eq tx-sender (var-get contract-owner)) ERR_UNAUTHORIZED_ACCESS)
  (var-set contract-owner new-owner)
  (ok true)
)

(define-public (set-contract-active (active bool))
  (asserts! (is-eq tx-sender (var-get contract-owner)) ERR_UNAUTHORIZED_ACCESS)
  (var-set contract-active active)
  (ok true)
)

(define-public (set-decay-parameters (new-rate uint) (new-period uint))
  (asserts! (is-eq tx-sender (var-get contract-owner)) ERR_UNAUTHORIZED_ACCESS)
  (asserts! (<= new-rate u100) ERR_INVALID_PARAMETERS)
  (asserts! (> new-period u0) ERR_INVALID_PARAMETERS)
  (var-set decay-rate new-rate)
  (var-set decay-period new-period)
  (ok true)
)

(define-public (set-starting-reputation (new-value uint))
  (asserts! (is-eq tx-sender (var-get contract-owner)) ERR_UNAUTHORIZED_ACCESS)
  (asserts! (<= new-value MAX_REPUTATION_SCORE) ERR_INVALID_PARAMETERS)
  (var-set starting-reputation new-value)
  (ok true)
)

(define-public (add-reputation-action (action-type (string-ascii 50)) (multiplier uint) (description (string-ascii 100)))
  (asserts! (is-eq tx-sender (var-get contract-owner)) ERR_UNAUTHORIZED_ACCESS)
  (asserts! (is-none (map-get? reputation-actions { action-type: action-type })) ERR_DUPLICATE_ENTRY)
  (map-set reputation-actions { action-type: action-type } { multiplier: multiplier description: description active: true })
  (ok true)
)

(define-public (update-reputation-action (action-type (string-ascii 50)) (multiplier uint) (description (string-ascii 100)) (active bool)
 (asserts! (is-eq tx-sender (var-get contract-owner)) ERR_UNAUTHORIZED_ACCESS)
  (asserts! (is-some (map-get? reputation-actions { action-type: action-type })) ERR_NONEXISTENT_ITEM)
  (map-set reputation-actions { action-type: action-type } { multiplier: multiplier description: description active: active })
  (ok true)
)

(define-public (initialize-reputation-actions)
  (asserts! (is-eq tx-sender (var-get contract-owner)) ERR_UNAUTHORIZED_ACCESS)
  (map-set reputation-actions { action-type: "governance-vote" } { multiplier: u5 description: "Participation in governance voting" active: true })
  (map-set reputation-actions { action-type: "contract-fulfillment" } { multiplier: u10 description: "Successful completion of smart contract agreement" active: true })
  (map-set reputation-actions { action-type: "community-contribution" } { multiplier: u7 description: "Contribution to community initiatives" active: true })
  (map-set reputation-actions { action-type: "validation" } { multiplier: u3 description: "Validation of network transactions or data" active: true })
  (map-set reputation-actions { action-type: "content-creation" } { multiplier: u6 description: "Creation of valuable content on the platform" active: true })
  (ok true)
)


;; Read-Only Functions

(define-read-only (get-reputation (owner principal))
  (let ((identity (get-identity-field owner)))
    (if (is-some identity)
        (some (get reputation-score (unwrap! identity none)))
        none
    )
  )
)

(define-read-only (get-full-identity (owner principal))
  (get-identity-field owner)
)

(define-read-only (verify-reputation (owner principal) (min-reputation-threshold uint))
  (match (map-get? identities { owner: owner })
    identity (if (and (get active identity) (>= (get reputation-score identity) min-reputation-threshold))
                (some true)
                none)
    none
  )
)

(define-read-only (get-reputation-action (action-type (string-ascii 50)))
  (map-get? reputation-actions { action-type: action-type })
)

(define-read-only (get-reputation-history (owner principal) (tx-id uint))
  (map-get? reputation-history { owner: owner tx-id: tx-id })
)

(define-read-only (get-contract-parameters)
  {
    max-reputation: MAX_REPUTATION_SCORE,
    min-reputation: MIN_REPUTATION_SCORE,
    starting-reputation: (var-get starting-reputation),
    decay-rate: (var-get decay-rate),
    decay-period: (var-get decay-period),
    owner: (var-get contract-owner),
    active: (var-get contract-active),
    submission-charge: (var-get submission-charge),
    aggregate-submissions: (var-get aggregate-submissions),
    content-topics: (var-get content-topics)
  }
)


;; Initialize Default Actions
(initialize-reputation-actions)
