;; EventPass NFT Access Management Smart Contract
;; SPDX-License-Identifier: MIT

(define-non-fungible-token eventpass-access (string-ascii 100))

;; Constants
(define-constant ADMIN-PRINCIPAL tx-sender)
(define-constant ERR-UNAUTHORIZED (err u100))
(define-constant ERR-PASS-EXISTS (err u101))
(define-constant ERR-PASS-NOT-FOUND (err u102))
(define-constant ERR-FORBIDDEN-TRANSFER (err u103))
(define-constant ERR-INVALID-PARAMETERS (err u104))
(define-constant ERR-LIMIT-REACHED (err u105))
(define-constant ERR-PASS-REVOKED (err u106))
(define-constant ERR-REFUND-ERROR (err u107))
(define-constant ERR-PASSES-DISTRIBUTED (err u108))
(define-constant ERR-INVALID-RECIPIENT (err u109))

;; Input Validation Functions
(define-private (is-valid-pass-title (title (string-ascii 100)))
  (and 
    (> (len title) u0) 
    (<= (len title) u100)
  )
)

(define-private (is-valid-access-date (date (string-ascii 50)))
  (and 
    (> (len date) u0) 
    (<= (len date) u50)
  )
)

(define-private (is-valid-access-fee (fee uint))
  (> fee u0)
)

(define-private (is-valid-member-limit (limit uint))
  (> limit u0)
)

;; Principal Validation Function
(define-private (is-valid-recipient (addr principal))
  (not (is-eq addr ADMIN-PRINCIPAL))
)

;; Storage
(define-map access-pass-data 
  {pass-id: (string-ascii 100)} 
  {
    pass-title: (string-ascii 100),
    access-date: (string-ascii 50),
    access-fee: uint,
    member-limit: uint,
    current-members: uint,
    is-revoked: bool
  }
)

;; Tracks pass holders for each access level
(define-map access-members 
  {pass-id: (string-ascii 100), member-principal: principal} 
  bool
)

;; Read-only functions
(define-read-only (get-pass-holder (pass-id (string-ascii 100)))
  (nft-get-owner? eventpass-access pass-id)
)

(define-read-only (get-access-pass-data (pass-id (string-ascii 100)))
  (map-get? access-pass-data {pass-id: pass-id})
)

;; Create new access pass
(define-public (create-access-pass 
  (pass-id (string-ascii 100))
  (pass-title (string-ascii 100))
  (access-date (string-ascii 50))
  (access-fee uint)
  (member-limit uint)
)
  (begin
    ;; Validate inputs
    (asserts! (is-valid-pass-title pass-title) ERR-INVALID-PARAMETERS)
    (asserts! (is-valid-access-date access-date) ERR-INVALID-PARAMETERS)
    (asserts! (is-valid-access-fee access-fee) ERR-INVALID-PARAMETERS)
    (asserts! (is-valid-member-limit member-limit) ERR-INVALID-PARAMETERS)
    
    ;; Ensure pass hasn't been created before
    (asserts! (is-none (get-access-pass-data pass-id)) ERR-PASS-EXISTS)
    
    ;; Create pass metadata
    (map-set access-pass-data 
      {pass-id: pass-id}
      {
        pass-title: pass-title,
        access-date: access-date,
        access-fee: access-fee,
        member-limit: member-limit,
        current-members: u0,
        is-revoked: false
      }
    )
    
    ;; Mint NFT to admin
    (nft-mint? eventpass-access pass-id ADMIN-PRINCIPAL)
  )
)

;; Update Access Pass Details
(define-public (update-pass-details
  (pass-id (string-ascii 100))
  (new-pass-title (string-ascii 100))
  (new-access-date (string-ascii 50))
  (new-access-fee uint)
)
  (let ((pass-info (unwrap! (get-access-pass-data pass-id) ERR-PASS-NOT-FOUND)))
    (begin
      ;; Ensure only admin can update
      (asserts! (is-eq tx-sender ADMIN-PRINCIPAL) ERR-UNAUTHORIZED)
      
      ;; Prevent updates after passes have been distributed
      (asserts! (is-eq (get current-members pass-info) u0) ERR-PASSES-DISTRIBUTED)
      
      ;; Validate new inputs
      (asserts! (is-valid-pass-title new-pass-title) ERR-INVALID-PARAMETERS)
      (asserts! (is-valid-access-date new-access-date) ERR-INVALID-PARAMETERS)
      (asserts! (is-valid-access-fee new-access-fee) ERR-INVALID-PARAMETERS)
      
      ;; Update pass metadata
      (map-set access-pass-data 
        {pass-id: pass-id}
        (merge pass-info {
          pass-title: new-pass-title,
          access-date: new-access-date,
          access-fee: new-access-fee
        })
      )
      
      (ok true)
    )
  )
)

;; Acquire access pass
(define-public (acquire-access-pass (pass-id (string-ascii 100)))
  (let ((pass-info (unwrap! (get-access-pass-data pass-id) ERR-PASS-NOT-FOUND)))
    (begin
      ;; Check if pass has not been revoked
      (asserts! (not (get is-revoked pass-info)) (err u108))
      
      ;; Check if member limit hasn't been reached
      (asserts! 
        (< (get current-members pass-info) (get member-limit pass-info)) 
        ERR-LIMIT-REACHED
      )
      
      ;; Transfer access fee (simplified - would integrate with STX transfer)
      (try! (stx-transfer? (get access-fee pass-info) tx-sender ADMIN-PRINCIPAL))
      
      ;; Update member count
      (map-set access-pass-data 
        {pass-id: pass-id}
        (merge pass-info {current-members: (+ (get current-members pass-info) u1)})
      )
      
      ;; Record access member
      (map-set access-members 
        {pass-id: pass-id, member-principal: tx-sender} 
        true
      )
      
      ;; Mint access pass NFT to member
      (nft-mint? eventpass-access pass-id tx-sender)
    )
  )
)

;; Transfer access pass
(define-public (transfer-access-pass 
  (pass-id (string-ascii 100)) 
  (new-holder principal)
)
  (begin
    ;; Validate transfer recipient
    (asserts! (is-valid-recipient new-holder) ERR-INVALID-RECIPIENT)
    
    ;; Ensure only current pass holder can transfer
    (asserts! 
      (is-eq tx-sender (unwrap! (nft-get-owner? eventpass-access pass-id) ERR-PASS-NOT-FOUND)) 
      ERR-FORBIDDEN-TRANSFER
    )
    
    ;; Transfer membership record
    (map-delete access-members {pass-id: pass-id, member-principal: tx-sender})
    (map-set access-members 
      {pass-id: pass-id, member-principal: new-holder} 
      true
    )
    
    ;; Transfer NFT
    (nft-transfer? eventpass-access pass-id tx-sender new-holder)
  )
)

;; Revoke Access Pass
(define-public (revoke-access-pass (pass-id (string-ascii 100)))
  (let ((pass-info (unwrap! (get-access-pass-data pass-id) ERR-PASS-NOT-FOUND)))
    (begin
      ;; Ensure only admin can revoke
      (asserts! (is-eq tx-sender ADMIN-PRINCIPAL) ERR-UNAUTHORIZED)
      
      ;; Ensure pass hasn't already been revoked
      (asserts! (not (get is-revoked pass-info)) ERR-PASS-REVOKED)
      
      ;; Mark pass as revoked
      (map-set access-pass-data 
        {pass-id: pass-id}
        (merge pass-info {is-revoked: true})
      )
      
      (ok true)
    )
  )
)

;; Request Refund for Access Pass
(define-public (request-refund (pass-id (string-ascii 100)))
  (let (
    (pass-info (unwrap! (get-access-pass-data pass-id) ERR-PASS-NOT-FOUND))
    (pass-holder (unwrap! (nft-get-owner? eventpass-access pass-id) ERR-PASS-NOT-FOUND))
  )
    (begin
      ;; Ensure access pass is revoked
      (asserts! (get is-revoked pass-info) (err u109))
      
      ;; Ensure caller is pass holder
      (asserts! (is-eq tx-sender pass-holder) ERR-FORBIDDEN-TRANSFER)
      
      ;; Burn the access pass NFT
      (try! (nft-burn? eventpass-access pass-id tx-sender))
      
      ;; Refund access fee
      (try! (stx-transfer? (get access-fee pass-info) ADMIN-PRINCIPAL tx-sender))
      
      ;; Remove access member
      (map-delete access-members 
        {pass-id: pass-id, member-principal: tx-sender}
      )
      
      (ok true)
    )
  )
)