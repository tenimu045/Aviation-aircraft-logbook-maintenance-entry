;; Aviation Aircraft Logbook Maintenance Entry
;; A smart contract for documenting maintenance actions, recording discrepancies, and maintaining airworthiness records

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-found (err u101))
(define-constant err-already-exists (err u102))
(define-constant err-invalid-input (err u103))
(define-constant err-unauthorized (err u104))
(define-constant err-aircraft-not-airworthy (err u105))
(define-constant err-discrepancy-open (err u106))

;; Data Variables
(define-data-var aircraft-counter uint u0)
(define-data-var entry-counter uint u0)
(define-data-var discrepancy-counter uint u0)
(define-data-var technician-counter uint u0)

;; Data Maps
(define-map aircraft
    { aircraft-id: uint }
    {
        registration: (string-ascii 20),
        make-model: (string-ascii 50),
        total-hours: uint,
        airworthy: bool,
        last-inspection: uint,
        next-inspection-due: uint
    }
)

(define-map maintenance-entries
    { entry-id: uint }
    {
        aircraft-id: uint,
        technician: principal,
        entry-block: uint,
        work-description: (string-ascii 200),
        hours-logged: uint,
        certified: bool
    }
)

(define-map discrepancies
    { discrepancy-id: uint }
    {
        aircraft-id: uint,
        reporter: principal,
        reported-block: uint,
        description: (string-ascii 200),
        severity: (string-ascii 20),
        resolved: bool,
        resolved-by: (optional principal),
        resolved-block: (optional uint)
    }
)

(define-map authorized-technicians
    { technician: principal }
    {
        name: (string-ascii 100),
        license-number: (string-ascii 50),
        ratings: (string-ascii 100),
        authorized-block: uint,
        active: bool
    }
)

(define-map inspection-records
    { aircraft-id: uint, inspection-block: uint }
    {
        inspection-type: (string-ascii 50),
        inspector: principal,
        findings: (string-ascii 200),
        compliant: bool
    }
)

;; Read-only Functions
(define-read-only (get-aircraft (aircraft-id uint))
    (ok (map-get? aircraft { aircraft-id: aircraft-id }))
)

(define-read-only (get-maintenance-entry (entry-id uint))
    (ok (map-get? maintenance-entries { entry-id: entry-id }))
)

(define-read-only (get-discrepancy (discrepancy-id uint))
    (ok (map-get? discrepancies { discrepancy-id: discrepancy-id }))
)

(define-read-only (get-technician-info (technician principal))
    (ok (map-get? authorized-technicians { technician: technician }))
)

(define-read-only (get-inspection-record (aircraft-id uint) (inspection-block uint))
    (ok (map-get? inspection-records { aircraft-id: aircraft-id, inspection-block: inspection-block }))
)

(define-read-only (get-aircraft-counter)
    (ok (var-get aircraft-counter))
)

(define-read-only (get-entry-counter)
    (ok (var-get entry-counter))
)

(define-read-only (get-discrepancy-counter)
    (ok (var-get discrepancy-counter))
)

(define-read-only (check-airworthiness (aircraft-id uint))
    (let
        (
            (aircraft-data (unwrap! (map-get? aircraft { aircraft-id: aircraft-id }) err-not-found))
        )
        (ok (get airworthy aircraft-data))
    )
)

;; Public Functions

;; Register a new aircraft
(define-public (register-aircraft (registration (string-ascii 20)) (make-model (string-ascii 50)) (total-hours uint))
    (let
        (
            (new-aircraft-id (+ (var-get aircraft-counter) u1))
        )
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (> total-hours u0) err-invalid-input)
        
        (map-set aircraft
            { aircraft-id: new-aircraft-id }
            {
                registration: registration,
                make-model: make-model,
                total-hours: total-hours,
                airworthy: true,
                last-inspection: block-height,
                next-inspection-due: (+ block-height u10000)
            }
        )
        (var-set aircraft-counter new-aircraft-id)
        (ok new-aircraft-id)
    )
)

;; Authorize a technician
(define-public (authorize-technician (technician principal) (name (string-ascii 100)) (license (string-ascii 50)) (ratings (string-ascii 100)))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (is-none (map-get? authorized-technicians { technician: technician })) err-already-exists)
        
        (map-set authorized-technicians
            { technician: technician }
            {
                name: name,
                license-number: license,
                ratings: ratings,
                authorized-block: block-height,
                active: true
            }
        )
        (ok true)
    )
)

;; Create maintenance entry
(define-public (create-maintenance-entry (aircraft-id uint) (work-desc (string-ascii 200)) (hours uint))
    (let
        (
            (new-entry-id (+ (var-get entry-counter) u1))
            (aircraft-data (unwrap! (map-get? aircraft { aircraft-id: aircraft-id }) err-not-found))
            (tech-data (unwrap! (map-get? authorized-technicians { technician: tx-sender }) err-unauthorized))
        )
        (asserts! (get active tech-data) err-unauthorized)
        (asserts! (get airworthy aircraft-data) err-aircraft-not-airworthy)
        
        (map-set maintenance-entries
            { entry-id: new-entry-id }
            {
                aircraft-id: aircraft-id,
                technician: tx-sender,
                entry-block: block-height,
                work-description: work-desc,
                hours-logged: hours,
                certified: false
            }
        )
        
        (map-set aircraft
            { aircraft-id: aircraft-id }
            (merge aircraft-data { total-hours: (+ (get total-hours aircraft-data) hours) })
        )
        
        (var-set entry-counter new-entry-id)
        (ok new-entry-id)
    )
)

;; Record discrepancy
(define-public (record-discrepancy (aircraft-id uint) (description (string-ascii 200)) (severity (string-ascii 20)))
    (let
        (
            (new-disc-id (+ (var-get discrepancy-counter) u1))
            (aircraft-data (unwrap! (map-get? aircraft { aircraft-id: aircraft-id }) err-not-found))
            (tech-data (unwrap! (map-get? authorized-technicians { technician: tx-sender }) err-unauthorized))
        )
        (asserts! (get active tech-data) err-unauthorized)
        
        (map-set discrepancies
            { discrepancy-id: new-disc-id }
            {
                aircraft-id: aircraft-id,
                reporter: tx-sender,
                reported-block: block-height,
                description: description,
                severity: severity,
                resolved: false,
                resolved-by: none,
                resolved-block: none
            }
        )
        
        (map-set aircraft
            { aircraft-id: aircraft-id }
            (merge aircraft-data { airworthy: false })
        )
        
        (var-set discrepancy-counter new-disc-id)
        (ok new-disc-id)
    )
)

;; Resolve discrepancy
(define-public (resolve-discrepancy (discrepancy-id uint))
    (let
        (
            (disc-data (unwrap! (map-get? discrepancies { discrepancy-id: discrepancy-id }) err-not-found))
            (tech-data (unwrap! (map-get? authorized-technicians { technician: tx-sender }) err-unauthorized))
            (aircraft-data (unwrap! (map-get? aircraft { aircraft-id: (get aircraft-id disc-data) }) err-not-found))
        )
        (asserts! (get active tech-data) err-unauthorized)
        (asserts! (not (get resolved disc-data)) err-invalid-input)
        
        (map-set discrepancies
            { discrepancy-id: discrepancy-id }
            (merge disc-data {
                resolved: true,
                resolved-by: (some tx-sender),
                resolved-block: (some block-height)
            })
        )
        
        (map-set aircraft
            { aircraft-id: (get aircraft-id disc-data) }
            (merge aircraft-data { airworthy: true })
        )
        
        (ok true)
    )
)

;; Certify work
(define-public (certify-work (entry-id uint))
    (let
        (
            (entry-data (unwrap! (map-get? maintenance-entries { entry-id: entry-id }) err-not-found))
            (tech-data (unwrap! (map-get? authorized-technicians { technician: tx-sender }) err-unauthorized))
        )
        (asserts! (get active tech-data) err-unauthorized)
        (asserts! (is-eq (get technician entry-data) tx-sender) err-unauthorized)
        (asserts! (not (get certified entry-data)) err-invalid-input)
        
        (map-set maintenance-entries
            { entry-id: entry-id }
            (merge entry-data { certified: true })
        )
        (ok true)
    )
)

;; Record inspection
(define-public (record-inspection (aircraft-id uint) (insp-type (string-ascii 50)) (findings (string-ascii 200)) (compliant bool))
    (let
        (
            (aircraft-data (unwrap! (map-get? aircraft { aircraft-id: aircraft-id }) err-not-found))
            (tech-data (unwrap! (map-get? authorized-technicians { technician: tx-sender }) err-unauthorized))
        )
        (asserts! (get active tech-data) err-unauthorized)
        
        (map-set inspection-records
            { aircraft-id: aircraft-id, inspection-block: block-height }
            {
                inspection-type: insp-type,
                inspector: tx-sender,
                findings: findings,
                compliant: compliant
            }
        )
        
        (map-set aircraft
            { aircraft-id: aircraft-id }
            (merge aircraft-data {
                last-inspection: block-height,
                next-inspection-due: (+ block-height u10000),
                airworthy: compliant
            })
        )
        
        (ok true)
    )
)

;; Update aircraft status
(define-public (update-aircraft-status (aircraft-id uint) (airworthy bool))
    (let
        (
            (aircraft-data (unwrap! (map-get? aircraft { aircraft-id: aircraft-id }) err-not-found))
        )
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        
        (map-set aircraft
            { aircraft-id: aircraft-id }
            (merge aircraft-data { airworthy: airworthy })
        )
        (ok true)
    )
)

;; Update technician status
(define-public (update-technician-status (technician principal) (active bool))
    (let
        (
            (tech-data (unwrap! (map-get? authorized-technicians { technician: technician }) err-not-found))
        )
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        
        (map-set authorized-technicians
            { technician: technician }
            (merge tech-data { active: active })
        )
        (ok true)
    )
)

