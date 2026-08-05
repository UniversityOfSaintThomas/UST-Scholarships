# UST Scholarships — Technical Architecture

This document covers the full technical picture: data model, portal architecture, Lightning Out integration, Apex design, LWC component map, permission model, and deployment notes.

---

## Table of Contents

1. [System Overview](#system-overview)
2. [Data Model](#data-model)
3. [Portal Architecture (Lightning Out)](#portal-architecture-lightning-out)
4. [Apex Controllers](#apex-controllers)
5. [LWC Components](#lwc-components)
6. [Permission Model](#permission-model)
7. [Deployment Reference](#deployment-reference)
8. [Known Gotchas](#known-gotchas)

---

## System Overview

The scholarship system has two distinct user-facing surfaces:

| Surface | Technology | Who Uses It |
|---|---|---|
| **Student Portal** | Visualforce pages + Lightning Out LWCs | Applicants (external community users) |
| **Internal Record Pages** | Salesforce Lightning App (SLDS) | Staff, Development Relations (DR), Admins |

The VF portal pages live under the **EASY Applicant Portal** Salesforce Site. They use a shared `ScholarshipTemplate2024` VF component for consistent navigation/layout and inject LWCs via **Lightning Out** (`$Lightning.use` / `$Lightning.createComponent`).

The internal app surfaces LWCs directly on record pages and uses the full Lightning experience.

---

## Data Model

### Core Custom Objects

```
Scholarship__c
  └── Scholarship_Applicant__c  (many per Scholarship, one per Contact/Scholarship pair)
        └── Award__c            (optional; used for formal award tracking)

EASY_Widget__c                  (integration object for EASY application system)
```

### `Scholarship__c` — Key Fields

| Field | Type | Purpose |
|---|---|---|
| `Name` | Text | Scholarship display name |
| `Scholarship_ID__c` | Text | External/URL identifier |
| `Open_Date__c` / `Close_Date__c` | Date | Application window |
| `Thank_You_Required__c` | Picklist | `Yes` / `Optional` / *(blank)* — drives TY workflow |
| `Degree_Type__c` | Picklist | Eligibility filter (UG, Grad, etc.) |
| `Citizenship_s__c` | Multi-select | Eligibility filter |
| `Recommender_Option__c` | Picklist | None / Optional / Required |
| `Recommender2_Option__c` | Picklist | Second recommender config |
| `Essay_1_Text__c` / `Essay_2_Text__c` | Long Text | Essay prompts |
| `Question_1_Text__c` … `Question_4_Text__c` | Text | Short-answer prompts |
| `Org_Wide_Email_Id__c` | Text | Email sender identity |
| `Submit_Scholarship_Email_Template_Id__c` | Text | Email template on submit |
| `Application_Controls__c` | Lookup → `Application_Control__c` | EASY integration link |

### `Scholarship_Applicant__c` — Key Fields

| Field | Type | Purpose |
|---|---|---|
| `Scholarship__c` | Lookup → `Scholarship__c` | Parent scholarship |
| `Contact__c` | Lookup → `Contact` | Applicant |
| `Scholarship_Status__c` | Picklist | Application lifecycle: `Started App` → `Submitted` → `Finalist` → `Accepted` / `Awarded` / `Declined` / etc. |
| `Scholarship_Complete__c` | Checkbox | Application fully complete |
| `Essay_1_Answer__c` / `Essay_2_Answer__c` | Long Text | Student essay responses |
| `Question_1_Answer__c` … `Question_4_Answer__c` | Text | Short-answer responses |
| `Recommendation__c` / `Recommendation2__c` | Text | Recommender email addresses |
| `Recommendation_Received__c` / `Recommendation2_Received__c` | Checkbox | Receipt flags |
| `Thank_You_Status__c` | Picklist | `Not Started` / `In Progress` / `Submitted` / `Complete` |
| `Thank_You_Letter__c` | Rich Text Area (131,072) | Student's written letter, stored as HTML |
| `Thank_You_Submitted_Date__c` | DateTime | Stamp when student submits |
| `Thank_You_Photo_Rights_Accepted__c` | Checkbox | Photo/quote rights consent |

> ⚠️ `Thank_You_Letter__c` is a Rich Text Area (Long Text Area subtype) — it **cannot** be used in a SOQL `WHERE` clause. Always query without it and filter in Apex. Its value is HTML, rendered via `lightning-input-rich-text` (edit) and `lightning-formatted-rich-text` (preview/read-only) in `scholarshipThankYousLwc` — never bind it into raw markup manually.

---

## Portal Architecture (Lightning Out)

### How It Works

```
Student Browser
    │
    ▼
Visualforce Page (ScholarshipHome, ScholarshipThankYou, etc.)
    │  apex:includeLightning + $Lightning.use("c:easyAuraApp", ...)
    │
    ▼
easyAuraApp  (Aura app, extends ltng:outApp)
    │  <aura:dependency resource="c:scholarshipEligibleListView"/>
    │  <aura:dependency resource="c:scholarshipThankYousLwc"/>
    │  ... (all LWCs used via Lightning Out must be declared here)
    │
    ▼
LWC Component  (rendered into <div id="lightningvf">)
```

### Key Rules for Lightning Out LWCs

1. **No `ShowToastEvent`** — toast events are silently swallowed in VF Lightning Out context. Use inline feedback banners with `setTimeout` auto-dismiss instead.
2. **Every LWC** used via Lightning Out must be declared as `<aura:dependency>` in `easyAuraApp.app`.
3. **Props are passed** as the second argument to `$Lightning.createComponent(componentName, { prop: value }, divId, callback)`.
4. **The VF page exposes** the Apex controller's properties (e.g., `{!contactId}`) as merge fields for the Lightning Out component call.

### Portal Pages

| VF Page | Controller | Purpose |
|---|---|---|
| `ScholarshipHome` | `ScholarshipHomeController` | Student scholarship list (eligible scholarships LWC) |
| `ScholarshipApplicationPage1` | `ScholarshipApplicationPage1Controller` | Application criteria / start |
| `ScholarshipApplicationPage2` | `ScholarshipApplicationPage2Controller` | Application essays, questions, recommenders |
| `ScholarshipApplicationComplete` | `ScholarshipApplicationCompleteController` | Confirmation page post-submit |
| `ScholarshipClosed` | `ScholarshipClosedController` | Closed/ineligible scholarship landing |
| `ScholarshipRecommender` | `ScholarshipRecommenderController` | External recommender submission |
| `ScholarshipThankYou` | *(none — Lightning Out only)* | Student thank-you letter portal |

### Template

All portal pages use `<apex:composition template="ScholarshipTemplate2024">` which provides:
- Consistent header/nav (`<apex:define name="metaPageTitle">`)
- Shared SLDS CSS
- Script injection hook (`<apex:define name="scriptsHead">`) for the Lightning Out `$Lightning.use` call

---

## Apex Controllers

### Shared Utilities

**`ScholarshipSharedUtilities`** — `without sharing` (system-level portal operations)

Core helpers used across all VF controllers:
- `getActiveContactId()` — resolves current portal user → Contact
- `getScholarshipInfo()` — reads `sid` cookie/param, returns full `Scholarship__c` record
- `getApplicantInfo(scholarshipId, contactId)` — fetches or initializes `Scholarship_Applicant__c`
- `checkScholarshipAccess()` — redirect guard (closed, wrong window, etc.)
- Email utility inner class for automated email sends

### VF Page Controllers

All follow the same pattern: a constructor that calls `ScholarshipSharedUtilities`, page action methods that perform DML, and `PageReference` returns for navigation.

| Class | Sharing | Key Actions |
|---|---|---|
| `ScholarshipHomeController` | — | Resolves contactId for LWC prop injection |
| `ScholarshipApplicationPage1Controller` | `with sharing` | Saves criteria / starts application |
| `ScholarshipApplicationPage2Controller` | `with sharing` | Saves full application, sends submit email |
| `ScholarshipApplicationCompleteController` | `with sharing` | Reads submitted app for confirmation |
| `ScholarshipClosedController` | — | Provides closed-state messaging |
| `ScholarshipRecommenderController` | `with sharing` | Accepts external recommender input |
| `ScholarshipRecommenderResendController` | `with sharing` | Resends recommender request email |

### LWC AuraEnabled Controllers

| Class | Sharing | Key `@AuraEnabled` Methods |
|---|---|---|
| `scholarshipEligibleListViewController` | `with sharing` | `eligibleScholarships(contactId, appId, currentPage)` |
| `ScholarshipCommunicationTemplates` | `with sharing` | Template CRUD methods |
| `ScholarshipThankYouController` | `with sharing` | See below |

#### `ScholarshipThankYouController` Methods

| Method | Cacheable | Purpose |
|---|---|---|
| `getThankYouItems(contactId)` | No | Portal list: all TY items for a student |
| `getThankYouItem(applicantId)` | No | Record page: single TY item detail |
| `saveThankYouDraft(applicantId, letterText)` | No | Saves draft, advances status to `In Progress` |
| `submitThankYouLetter(applicantId, letterText, photoRightsAccepted)` | No | Final submit; enforces 100-char minimum |
| `getPreviousLetters(contactId, excludeApplicantId)` | Yes | Load prior submitted letters for re-use |

**Auth guard:** All write methods verify the `Contact__c` on the applicant record matches the current user's Contact. System Administrators bypass this check.

**Status lock:** Records with `Thank_You_Status__c = 'Complete'` (DR-set) are read-only — `saveThankYouDraft` and `submitThankYouLetter` both reject attempts to modify them.

---

## LWC Components

### `scholarshipEligibleListView`

- **Mode**: Portal only (injected via Lightning Out from `ScholarshipHome`)
- **Props**: `contactId`, `appId`, `currentPage`, `widgetSize`
- **Function**: Queries eligible open scholarships filtered against the student's application profile; renders a card list with links

### `scholarshipApplicationControlsLwc`

- **Mode**: Internal record page
- **Function**: Manages application control linking on `Scholarship__c` records

### `scholarshipCommunicationTemplatesLwc`

- **Mode**: Internal record page (`Scholarship__c`)
- **Function**: Staff UI to browse and assign email templates for each scholarship lifecycle event

### `scholarshipRecommenderResendLwc`

- **Mode**: Internal record page (`Scholarship_Applicant__c`)
- **Function**: Allows staff to resend recommender request emails

### `scholarshipThankYousLwc`

- **Mode**: **Dual** — portal list + record page
- **Props**: `contactId` (portal), `recordId` (record page)
- **Mode detection**: `connectedCallback` — if `contactId` is set → portal list mode; if `recordId` only → record page mode

#### Portal Mode (contactId)
- Lists all thank-you requirements for the student
- Expandable editor per card: textarea, character count, preview toggle, photo rights checkbox
- Save Draft and Submit buttons
- "Re-use Previous Letter" dropdown (loads past submissions)
- Inline feedback banner (replaces `ShowToastEvent`)

#### Record Page Mode (recordId)
- Displays TY detail for the single `Scholarship_Applicant__c` record
- Shows status badge, letter text, submission date, photo rights
- Editable when status is not `Complete`

### `selectApplicationControlsLwc`

- **Mode**: Internal
- **Function**: Selection UI for application control records

---

## Permission Model

### `UST_Scholarship_Admin`

Grants staff/DR full access:
- Read/Edit: `Award__c`, `Scholarship__c`, `Scholarship_Applicant__c` (all fields)
- App visibility: `Scholarships`, `Scholarships_Lightning`
- VF page access: all scholarship pages

### `UST_Scholarship_Applicant`

Grants portal applicants restricted access:
- Read/Edit: application fields on `Scholarship_Applicant__c` (essays, questions, recommenders, **TY fields**)
- Read-only: scholarship metadata fields
- VF page access: all portal pages including `ScholarshipThankYou`

### Thank-You Fields — Both Permission Sets

| Field | Admin | Applicant |
|---|---|---|
| `Thank_You_Status__c` | Read/Edit | Read/Edit |
| `Thank_You_Letter__c` | Read/Edit | Read/Edit |
| `Thank_You_Submitted_Date__c` | Read/Edit | Read/Edit |
| `Thank_You_Photo_Rights_Accepted__c` | Read/Edit | Read/Edit |

---

## Deployment Reference

### Deployment Order (avoid errors)

When deploying a batch that includes **new VF pages + permission set page access**, always deploy VF pages first:

```powershell
# 1. Objects / fields first
cci task run deploy --path force-app/main/default/objects --org dev

# 2. Apex classes
cci task run deploy --path force-app/main/default/classes --org dev

# 3. LWCs
cci task run deploy --path force-app/main/default/lwc --org dev

# 4. Aura (Lightning Out bridge)
cci task run deploy --path force-app/main/default/aura --org dev

# 5. VF pages BEFORE permission sets
cci task run deploy --path force-app/main/default/pages --org dev

# 6. Permission sets last
cci task run deploy --path force-app/main/default/permissionsets --org dev
```

### Source Tracking Cache

SF CLI source tracking can falsely report new fields as "Unchanged." Verify actual org state with a Tooling API query:

```powershell
sf data query `
  --query "SELECT QualifiedApiName FROM FieldDefinition WHERE EntityDefinitionId = 'Scholarship_Applicant__c' AND QualifiedApiName LIKE 'Thank_You%'" `
  --target-org UST-Scholarships__dev `
  --use-tooling-api `
  --result-format json
```

If fields are missing, deploy the full object folder:
```powershell
cci task run deploy --path force-app/main/default/objects/Scholarship_Applicant__c --org dev
```

### SOQL Security Enforcement

This codebase uses `with sharing` class declarations only. **Do not add** `WITH USER_MODE` or `WITH SECURITY_ENFORCED` to queries — in scratch orgs without explicit FLS grants, these will silently fail with "No such column" errors. This matches the pattern used across the entire existing codebase.

---

## Known Gotchas

| Gotcha | Symptom | Fix |
|---|---|---|
| `ShowToastEvent` in Lightning Out | Toast fires but student never sees it | Use inline feedback banner + `setTimeout` dismiss |
| `Long Text Area` in SOQL WHERE | `field 'X' can not be filtered` runtime error | Query without the field; filter in Apex with `String.isBlank()` |
| VF page ref in permission set before page exists | `no ApexPage named X found` during deploy | Deploy VF pages before permission sets |
| `WITH USER_MODE` on scratch org | `No such column 'X'` at runtime | Remove; use `with sharing` only |
| `<property>` in LWC community targetConfig | Deploy error on `lightningCommunity__Page` | Only use `<property>` in `lightning__RecordPage` targetConfig |
| Source tracking says field "Unchanged" | Field missing from org at runtime | Use Tooling API to confirm; deploy full object folder |
| `$Lightning.createComponent` LWC not found | Runtime error, component never mounts | Add `<aura:dependency>` for the LWC in `easyAuraApp.app` |

