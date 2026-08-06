# Scholarship Thank You Feature — Implementation Plan

**Date:** March 26, 2026  
**Feature:** Student Scholarship Thank You Letter Workflow  
**Reference:** `Student-Scholarship-Thank-You-Feature.md`

---

## Status Checklist (as of 2026-08-06)

### Phase 1 — Data Foundation
- [x] `Thank_You_Status__c` (Picklist: Not Started/In Progress/Submitted/Complete) on `Scholarship_Applicant__c`
- [x] `Thank_You_Letter__c` on `Scholarship_Applicant__c` — **upgraded beyond plan**: built as Long Text Area, later converted to **Rich Text Area** so the LWC could use `lightning-input-rich-text`/`lightning-formatted-rich-text`
- [x] `Thank_You_Submitted_Date__c` (DateTime)
- [x] `Thank_You_Photo_Rights_Accepted__c` (Checkbox)
- [ ] `Thank_You_Status__c` (DR campaign-level status) on **`Scholarship__c`** — never created; picklist values were never confirmed with the DR team (Open Question #1, still open)
- [x] `UST_Scholarship_Applicant` permission set — read/edit on all 4 new `Scholarship_Applicant__c` fields, read-only on the `Scholarship__c` support fields
- [x] `UST_Scholarship_Admin` permission set — read/edit on all of the above

### Phase 2 — Apex Controller
- [x] `ScholarshipThankYouController.cls` — all 5 planned methods present (`getThankYouItems`, `getThankYouItem`, `saveThankYouDraft`, `submitThankYouLetter`, `getPreviousLetters`)
- [x] `ScholarshipThankYouController_TEST.cls` — 15 tests, 89% coverage (target was ≥75%)
- [x] Auth guard (`assertContactOwnership`, admin bypass)
- [x] Data-completeness check (`hasDataWarning`/`dataWarningMessage` when FA code or donor Account is missing)
- [x] Status-transition guard (edits blocked once `Complete`)
- [x] Minimum letter length (100 chars) enforced server-side and client-side — ⚠️ known gap: the server check now measures raw HTML length (rich text), so it's more lenient than the client's stripped-plain-text check; not yet tightened

### Phase 3 — LWC (Portal List Mode)
- [x] `scholarshipThankYousLwc` built out — portal list, status badges, inline editor
- [x] `<aura:dependency resource="c:scholarshipThankYousLwc"/>` added to `easyAuraApp`
- [x] `ScholarshipThankYou.page` built
- [x] Deployed and verified live in the portal as a student user (Thomas Magnum test account)
- [ ] Nav link from `ScholarshipHome.page` to `ScholarshipThankYou.page` (marked optional in the original plan) — not added

### Phase 4 — LWC (Record Page Mode)
- [x] Record-page support (`@api recordId`, single-item fetch)
- [x] `js-meta.xml` targets include `lightning__RecordPage`
- [ ] **Not actually placed on the `Scholarship_Applicant__c` record page** — no FlexiPage in the repo references `scholarshipThankYousLwc`; the component is ready but nobody has dragged it into App Builder yet
- [ ] Not tested live as a DR/admin user this session (only the portal/student flow was verified in-browser)

### Phase 5 — Photo Upload
- [x] `lightning-file-upload` added to the letter panel
- [x] `Thank_You_Photo_Rights_Accepted__c` checkbox wired up
- [~] File-to-record linking uses the standard `record-id={applicantId}` pattern but was never exercised end-to-end (no actual file was uploaded during testing)

### Phase 6 — DR Staff Dashboard (Future / Scope TBD in the original plan)
- [ ] List view / report of submitted TY letters per scholarship
- [ ] DR review/edit interface with logging
- [ ] Batch export for vendor mailing
- [ ] Automated status → Complete after mailing confirmation

### Open Questions (§10) — resolution status
1. `Thank_You_Status__c` picklist values on `Scholarship__c` — **still open**, field was never built
2. Should `Optional` TY scholarships show by default? — **resolved: yes** (`TY_REQUIRED_VALUES` includes `Yes` and `Optional`)
3. Can students re-submit/edit after submitting? — **resolved by implementation**: no, only `Not Started`/`In Progress` are student-editable; DR can still edit via the record page unless status is `Complete`
4. Which award statuses trigger TY? — **resolved: both** `Accepted` and `Awarded`
5. Is photo upload required, or scholarship-flag controlled? — **resolved by implementation**: always optional for every scholarship; no `Require_Photo__c` flag was built
6. Standalone VF page or a tab on an existing page? — **resolved: standalone** `ScholarshipThankYou.page`
7. Will DR need a native Salesforce review/edit UI? — **still open**, this is Phase 6

### Built beyond the original plan this session
- [x] `Thank_You_Letter__c` converted to Rich Text Area (not in original scope — plan called for plain Long Text Area)
- [x] New `scholarshipThankYouListLwc` — compact nav list with per-scholarship progress bar, deep-linking via `?applicantId=`, and cross-widget same-page navigation with `scholarshipThankYousLwc`
- [x] Brand-purple styling, active-card outline, and several layout/CSS bug fixes (badge overflow, rich-text toolbar padding/bullet, button-triggers-page-reload bug)
- [x] Documented a significant Lightning Out component-caching gotcha (in `AGENTS.md` and the shared agent onboarding skill)
- [x] `AGENTS.md` / `CLAUDE.md` added to the repo (didn't exist before this branch)

---

## 1. Overview

This plan describes how to build the scholarship thank you (TY) letter feature inside the existing UST Scholarships portal. The solution centers on a single LWC (`scholarshipThankYousLwc`) that operates in two distinct modes:

| Mode | Context | Key Input | Purpose |
|---|---|---|---|
| **Portal / List** | Visualforce Lightning Out | `contactId` (passed from VF) | Student sees all their outstanding and completed TY letters; writes and submits them |
| **Record Page** | Lightning App Builder | `recordId` (Scholarship_Applicant__c) | Staff/DR view of a single applicant's TY state |

Both modes share the same Apex controller and component — the `mode` is inferred from which `@api` prop is populated at runtime.

---

## 2. Current State Inventory

### What Already Exists

| Asset | Location | Notes |
|---|---|---|
| `scholarshipThankYousLwc` | `force-app/.../lwc/scholarshipThankYousLwc/` | Skeleton only (Hello World) |
| `easyAuraApp` | `force-app/.../aura/easyAuraApp/` | Aura Lightning Out bridge; wraps all portal LWCs |
| `ScholarshipHome.page` | `force-app/.../pages/` | Portal home; embeds `scholarshipEligibleListView` via Lightning Out |
| `ScholarshipHomeController.cls` | `force-app/.../classes/` | Resolves `contactId` from logged-in user for VF |
| `ScholarshipSharedUtilities.cls` | `force-app/.../classes/` | Shared helpers: contact lookup, email, open/close dates |
| `scholarshipEligibleListView` | `force-app/.../lwc/` | Example of the dual-mode LWC + portal embed pattern |
| `UST_Scholarship_Applicant` permission set | `force-app/.../permissionsets/` | Portal user permissions — must be updated for new fields |
| `UST_Scholarship_Admin` permission set | `force-app/.../permissionsets/` | Staff/DR permissions — must be updated for new fields |

### Fields Already Added to `Scholarship__c`

| Field | Type | Purpose |
|---|---|---|
| `Thank_You_Required__c` | Picklist (Yes / No / Optional) | Flags whether this scholarship requires a TY letter |
| `Designation_Code__c` | Text(10) | Financial Aid designation code (links to ERP) |
| `Financial_Aid_Code__c` | Text(10) | FA code used for donor matching and mailing exports |
| `Scholarship_Account__c` | Lookup → Account | The donor/sponsor Account record |
| `Thank_You_Status__c` | _(see note below)_ | Global DR processing status for this scholarship's letters |

> **Note on `Thank_You_Status__c` on `Scholarship__c`:** This likely tracks the overall campaign-level DR status (e.g., "Ready to Mail", "Mailed") for all letters belonging to a scholarship — distinct from the per-student status. Confirm picklist values with DR staff before deploying.

---

## 3. New Metadata Required

### 3.1 New Fields — `Scholarship_Applicant__c`

These fields track the per-student, per-scholarship TY state and must be created before the LWC or Apex controller can be built.

| Field API Name | Type | Values / Notes |
|---|---|---|
| `Thank_You_Status__c` | Picklist (restricted) | **Not Started** · **In Progress** · **Submitted** · **Complete** |
| `Thank_You_Letter__c` | Long Text Area (32,768) | The student's written letter body |
| `Thank_You_Submitted_Date__c` | DateTime | Set automatically when student submits |
| `Thank_You_Photo_Rights_Accepted__c` | Checkbox | Student acceptance of photo usage/quotation rights |

> **Photo upload:** Student photos will be stored as Salesforce Files (ContentDocument/ContentVersion linked to the Scholarship_Applicant__c record) rather than a custom field. The LWC will use the standard `lightning-file-upload` component.

### 3.2 New Apex Class

| Class | Notes |
|---|---|
| `ScholarshipThankYouController.cls` | `@AuraEnabled` methods for the LWC; see §5 |
| `ScholarshipThankYouController_TEST.cls` | Required test class; target ≥75% coverage per `cumulusci.yml` |

### 3.3 New Visualforce Page

| Page | Notes |
|---|---|
| `ScholarshipThankYou.page` | Dedicated portal page embedding `scholarshipThankYousLwc` in portal-list mode via Lightning Out |

### 3.4 Modifications to Existing Metadata

| Asset | Change |
|---|---|
| `easyAuraApp` (Aura app) | Add `<aura:dependency resource="c:scholarshipThankYousLwc"/>` |
| `UST_Scholarship_Applicant.permissionset` | Add read/edit permissions for all 4 new `Scholarship_Applicant__c` fields |
| `UST_Scholarship_Admin.permissionset` | Add read/edit permissions for all 4 new `Scholarship_Applicant__c` fields, plus `Thank_You_Status__c` on `Scholarship__c` |
| `ScholarshipHome.page` (optional) | Add a navigation link to the new `ScholarshipThankYou.page` so students can access their TY list from the portal home |

---

## 4. Data Architecture

```
Scholarship__c
  ├── Thank_You_Required__c          (Yes / No / Optional)
  ├── Thank_You_Status__c            (DR campaign-level status)
  ├── Designation_Code__c            (FA designation code)
  ├── Financial_Aid_Code__c          (FA code)
  └── Scholarship_Account__c ──────► Account (donor/sponsor)

Scholarship_Applicant__c  (child of Scholarship__c + Contact)
  ├── Thank_You_Status__c            (Not Started / In Progress / Submitted / Complete)
  ├── Thank_You_Letter__c            (student's letter text)
  ├── Thank_You_Submitted_Date__c    (auto-set on submission)
  ├── Thank_You_Photo_Rights_Accepted__c  (checkbox)
  └── ContentDocumentLink ─────────► ContentDocument (photo file)
```

**Query logic for "TY required" items:**  
A Scholarship_Applicant__c record should appear in the student's TY list when:
- `Scholarship__r.Thank_You_Required__c = 'Yes'` (or `'Optional'` if you want to surface those too)
- `Scholarship_Status__c = 'Accepted'` OR `'Awarded'` (student was awarded the scholarship)

---

## 5. Apex Controller — `ScholarshipThankYouController`

```
with sharing  (portal users should only see their own data)
```

### Method Signatures

```apex
// Portal mode: returns all TY items for the logged-in or passed contactId
@AuraEnabled
public static List<ThankYouItem> getThankYouItems(String contactId)

// Record page mode: returns a single TY item by Scholarship_Applicant__c Id
@AuraEnabled
public static ThankYouItem getThankYouItem(String applicantId)

// Saves a draft (status → In Progress if Not Started)
@AuraEnabled
public static void saveThankYouDraft(String applicantId, String letterText)

// Submits the final letter (status → Submitted, sets submitted date)
@AuraEnabled
public static void submitThankYouLetter(String applicantId, String letterText, Boolean photoRightsAccepted)

// Copies text from another of the student's submitted/complete TY letters
@AuraEnabled(cacheable=true)
public static List<PreviousLetterOption> getPreviousLetters(String contactId, String excludeApplicantId)
```

### Inner / Wrapper Class: `ThankYouItem`

```apex
public class ThankYouItem {
    @AuraEnabled public String applicantId;
    @AuraEnabled public String scholarshipName;
    @AuraEnabled public String scholarshipAccountName;   // donor name
    @AuraEnabled public String designationCode;
    @AuraEnabled public String financialAidCode;
    @AuraEnabled public String thankYouRequired;         // Yes / Optional
    @AuraEnabled public String thankYouStatus;           // Not Started … Complete
    @AuraEnabled public String thankYouLetter;
    @AuraEnabled public Boolean photoRightsAccepted;
    @AuraEnabled public Datetime submittedDate;
    @AuraEnabled public Boolean hasDataWarning;          // true if FA code / scholarship name is missing
    @AuraEnabled public String dataWarningMessage;
}
```

### Key Business Rules Enforced in Apex

1. **Auth guard:** Verify the calling user owns the `Contact__c` on the record (or is an admin) before any DML.
2. **Data completeness check:** If `Financial_Aid_Code__c` or `Scholarship_Account__c` is blank on the Scholarship when building the TY list, populate `hasDataWarning = true` and surface the message to the student (per Theme 1 requirement).
3. **Status transitions:** Only allow `saveThankYouDraft` / `submitThankYouLetter` when `Thank_You_Status__c` is not `'Complete'` (DR has final say once marked Complete).
4. **Minimum letter length:** Enforce ≥ 100 characters server-side as well as client-side.

---

## 6. LWC — `scholarshipThankYousLwc`

### 6.1 Public API Props

```javascript
@api recordId;    // Scholarship_Applicant__c Id — record page mode
@api contactId;   // Contact Id — portal mode (passed from VF controller)
```

Mode is determined at `connectedCallback`:
- If `recordId` is populated → **record page mode** (load single item)
- If `contactId` is populated → **portal list mode** (load all items for this contact)

### 6.2 Portal List Mode — Student UX Flow

```
┌──────────────────────────────────────────────────────────────┐
│  Your Thank-You Letters                                      │
│  "Your thank-you letter lets us steward your scholarship     │
│   donors and maintain funding."                              │
├────────────────┬──────────────────────────────────────────── │
│ [Scholarship A]│ Status: ● Not Started         [Start →]    │
│ [Scholarship B]│ Status: ● In Progress         [Continue →] │
│ [Scholarship C]│ Status: ✔ Submitted           [View →]     │
│ [Scholarship D]│ Status: ✔ Complete            [View →]     │
└────────────────┴───────────────────────────────────────────── │
```

Clicking **Start / Continue / View** expands an inline panel (or opens a modal) with:
1. **Header:** Scholarship name, donor name ("Required by: Donor Relations")
2. **Context message** (plain language, per Theme 1 & 2 requirements)
3. **"Use a previous letter"** dropdown (if student has prior submissions — `getPreviousLetters`)
4. **Letter textarea** with:
   - Character/sentence count hint (min 3–5 sentences)
   - Inline example text shown on first open
5. **Preview panel** (toggled by "Preview" button — shows formatted letter before submit)
6. **Photo upload** (`lightning-file-upload` — optional, only shown if scholarship supports it)
7. **Photo rights checkbox** (shown when photo is uploaded)
8. **Save Draft** / **Submit** buttons
9. Status badge updates immediately after submission (no page reload)

### 6.3 Record Page Mode — Staff / DR UX

- Displays the same TY form fields in read-only mode for `Complete` status
- Editable by admin for `Submitted` records (lightweight DR edit)
- Shows data-completeness warning banner if FA code / designation / account is missing

### 6.4 Reactivity Pattern

Follow the project's proven reactivity rules:
- Store loaded items as an immutable copy; spread to update individual items
- Use `refreshApex` after any `updateRecord` / Apex DML call
- Status badge color driven by getter:
  ```javascript
  get statusClass() {
      const map = {
          'Not Started': 'slds-badge slds-theme_error',
          'In Progress': 'slds-badge slds-theme_warning',
          'Submitted':   'slds-badge slds-theme_success',
          'Complete':    'slds-badge slds-theme_alt-inverse'
      };
      return map[this.item.thankYouStatus] ?? 'slds-badge';
  }
  ```

### 6.5 Lightning Out Constraints

Because the LWC will be hosted inside VF via Lightning Out (`easyAuraApp`), the following rules apply:
- **No `NavigationMixin`** — navigation in VF context must use plain `window.location` or VF `apex:outputLink`
- **`ShowToastEvent` does NOT fire in Lightning Out** — use an inline message/banner component instead for portal feedback
- **`@salesforce/label`** imports work normally
- The component must be listed as an `<aura:dependency>` in `easyAuraApp.app` before it can be used in VF

---

## 7. Visualforce Page — `ScholarshipThankYou.page`

Follows the same pattern as `ScholarshipHome.page`:
- Controller: `ScholarshipHomeController` (already resolves `contactId`)
- Template: `ScholarshipTemplate2024` composition
- `apex:includeLightning` + `$Lightning.use("c:easyAuraApp", ...)`
- `$Lightning.createComponent("c:scholarshipThankYousLwc", { contactId: "{!varContactId}" }, "lightningvf", ...)`

```xml
<apex:page controller="ScholarshipHomeController" ...>
    <apex:variable value="{!contactId}" var="varContactId"/>
    <apex:includeLightning />
    <apex:composition template="ScholarshipTemplate2024">
        <apex:define name="body">
            <div id="lightningvf" class="slds-m-top_medium"></div>
        </apex:define>
        <apex:define name="scriptsHead">
            <script>
                $Lightning.use("c:easyAuraApp", function () {
                    $Lightning.createComponent("c:scholarshipThankYousLwc",
                        { contactId: "{!varContactId}" },
                        "lightningvf",
                        function(cmp) { console.log("TY LWC loaded"); }
                    );
                });
            </script>
        </apex:define>
    </apex:composition>
</apex:page>
```

---

## 8. Build Order / Phased Delivery

### Phase 1 — Data Foundation
1. Create `Thank_You_Status__c` (Picklist) on `Scholarship_Applicant__c`
2. Create `Thank_You_Letter__c` (Long Text Area) on `Scholarship_Applicant__c`
3. Create `Thank_You_Submitted_Date__c` (DateTime) on `Scholarship_Applicant__c`
4. Create `Thank_You_Photo_Rights_Accepted__c` (Checkbox) on `Scholarship_Applicant__c`
5. Confirm picklist values for `Thank_You_Status__c` on `Scholarship__c` with DR team
6. Update both permission sets for new fields
7. Deploy: `cci task run deploy --path force-app/main/default/objects/Scholarship_Applicant__c --org dev`

### Phase 2 — Apex Controller
1. Create `ScholarshipThankYouController.cls` with all methods
2. Create `ScholarshipThankYouController_TEST.cls` (≥75% coverage)
3. Deploy: `cci task run deploy --path force-app/main/default/classes --org dev`
4. Run tests: `sf apex run test --class-names ScholarshipThankYouController_TEST --target-org UST-Scholarships__dev --result-format human --code-coverage --wait 20`

### Phase 3 — LWC (Portal List Mode)
1. Build `scholarshipThankYousLwc` — portal list view with status badges and inline editor
2. Add `c:scholarshipThankYousLwc` dependency to `easyAuraApp`
3. Build `ScholarshipThankYou.page` (VF portal page)
4. Deploy LWC + Aura + VF page
5. Test in portal as student user

### Phase 4 — LWC (Record Page Mode)
1. Add record page support (`@api recordId`, single-item fetch)
2. Update `js-meta.xml` targets to include `lightning__RecordPage`
3. Add to Scholarship_Applicant__c record page via App Builder
4. Deploy and test as DR/admin user

### Phase 5 — Photo Upload
1. Add `lightning-file-upload` to the letter composition panel
2. Wire up `Thank_You_Photo_Rights_Accepted__c` checkbox
3. Test file attachment linking to Scholarship_Applicant__c record

### Phase 6 — DR Staff Dashboard (Future / Scope TBD)
- List view / report on all submitted TY letters per scholarship
- Editing interface for DR review with logging
- Batch export for vendor mailing
- Automated status → Complete after mailing confirmation

---

## 9. Toast / Feedback Strategy in Lightning Out

`ShowToastEvent` does **not** work inside Lightning Out (VF context). Use this pattern instead:

```javascript
// In the LWC JS
@track feedbackMessage = { visible: false, type: '', text: '' };

showFeedback(type, text) {
    this.feedbackMessage = { visible: true, type, text };
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    setTimeout(() => { this.feedbackMessage = { ...this.feedbackMessage, visible: false }; }, 4000);
}
```

```html
<!-- In the template -->
<template lwc:if={feedbackMessage.visible}>
    <div class={feedbackClass} role="alert">{feedbackMessage.text}</div>
</template>
```

When the LWC is used **on a record page** (Lightning context, not VF), `ShowToastEvent` works normally — detect context and use the appropriate path.

---

## 10. Open Questions / Decisions Needed

| # | Question | Who Decides | Impact |
|---|---|---|---|
| 1 | What are the exact picklist values for `Thank_You_Status__c` on `Scholarship__c` (the DR campaign-level status)? | DR Team | Phase 1 field creation |
| 2 | Should "Optional" TY scholarships appear in the student's list by default, or only if opted in? | Product Owner | Apex query filter logic |
| 3 | Should students be allowed to re-submit after submitting (edit before DR reviews)? | DR Team | Status transition rules in Apex |
| 4 | Which scholarship award statuses trigger the TY requirement — just `Accepted` or also `Awarded`? | DR Team | Apex query filter |
| 5 | Is photo upload required for all scholarships or controlled by a scholarship-level flag? | Product Owner | Whether to add `Require_Photo__c` to `Scholarship__c` |
| 6 | Should the portal page be a new standalone VF page or a tab/section added to an existing portal page? | UX / Product | VF page structure |
| 7 | Will DR need a Salesforce-native review/edit UI or will they work through reports/list views initially? | DR Team | Scope of Phase 6 |

---

## 11. File Manifest (All Deliverables)

```
force-app/main/default/
├── objects/
│   └── Scholarship_Applicant__c/
│       └── fields/
│           ├── Thank_You_Status__c.field-meta.xml          [NEW]
│           ├── Thank_You_Letter__c.field-meta.xml           [NEW]
│           ├── Thank_You_Submitted_Date__c.field-meta.xml   [NEW]
│           └── Thank_You_Photo_Rights_Accepted__c.field-meta.xml  [NEW]
├── classes/
│   ├── ScholarshipThankYouController.cls                    [NEW]
│   ├── ScholarshipThankYouController.cls-meta.xml           [NEW]
│   ├── ScholarshipThankYouController_TEST.cls               [NEW]
│   └── ScholarshipThankYouController_TEST.cls-meta.xml      [NEW]
├── lwc/
│   └── scholarshipThankYousLwc/
│       ├── scholarshipThankYousLwc.html                     [BUILD OUT]
│       ├── scholarshipThankYousLwc.js                       [BUILD OUT]
│       ├── scholarshipThankYousLwc.css                      [BUILD OUT]
│       └── scholarshipThankYousLwc.js-meta.xml              [UPDATE targets]
├── aura/
│   └── easyAuraApp/
│       └── easyAuraApp.app                                  [UPDATE - add dependency]
├── pages/
│   ├── ScholarshipThankYou.page                             [NEW]
│   └── ScholarshipThankYou.page-meta.xml                    [NEW]
└── permissionsets/
    ├── UST_Scholarship_Applicant.permissionset-meta.xml     [UPDATE - add field perms]
    └── UST_Scholarship_Admin.permissionset-meta.xml         [UPDATE - add field perms]
```

---

## 12. Deployment Commands Reference

```powershell
# Phase 1 — Fields + Permission Sets
cci task run deploy --path force-app/main/default/objects/Scholarship_Applicant__c --org dev 2>&1 | Out-File ai-logs/deploy.txt
cci task run deploy --path force-app/main/default/permissionsets --org dev 2>&1 | Out-File ai-logs/deploy.txt

# Phase 2 — Apex
cci task run deploy --path force-app/main/default/classes --org dev 2>&1 | Out-File ai-logs/deploy.txt
sf apex run test --class-names ScholarshipThankYouController_TEST --target-org UST-Scholarships__dev --result-format human --code-coverage --wait 20 2>&1 | Out-File ai-logs/test.txt

# Phase 3 — LWC + Aura + VF
cci task run deploy --path force-app/main/default/lwc/scholarshipThankYousLwc --org dev 2>&1 | Out-File ai-logs/deploy.txt
cci task run deploy --path force-app/main/default/aura/easyAuraApp --org dev 2>&1 | Out-File ai-logs/deploy.txt
cci task run deploy --path force-app/main/default/pages --org dev 2>&1 | Out-File ai-logs/deploy.txt
```

