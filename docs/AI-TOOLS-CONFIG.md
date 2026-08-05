# AI-TOOLS-CONFIG — UST Scholarships

This file provides project-specific context for AI assistants working in this repository. It is referenced by the global Copilot instructions. Keep it up to date as the project evolves.

---

## Project Identity

| Property | Value |
|---|---|
| **CumulusCI project name** | `UST-Scholarships` |
| **CCI dev org alias** | `dev` |
| **SF CLI org alias** | `UST-Scholarships__dev` |
| **API version** | `66.0` |
| **Scratch org life** | 14 days |
| **Required code coverage** | 75% |

> Always confirm the SF CLI alias via `cci org info --org dev` → `sfdx_alias` column before running `sf` commands.

---

## Key Custom Objects

| Object API Name | Label | Notes |
|---|---|---|
| `Scholarship__c` | Scholarship | Main scholarship record |
| `Scholarship_Applicant__c` | Scholarship Applicant | One per student+scholarship pair |
| `Award__c` | Award | Formal award tracking (linked to applicant) |
| `EASY_Widget__c` | EASY Widget | Integration object (EASY application system) |

---

## Key Fields to Know

### `Scholarship__c`
- `Thank_You_Required__c` — Picklist: `Yes`, `Optional`, *(blank)* — determines which applicants enter the TY workflow
- `Scholarship_ID__c` — External URL identifier, used as cookie/param for VF page navigation

### `Scholarship_Applicant__c`
- `Scholarship_Status__c` — Application lifecycle picklist; `Accepted` and `Awarded` are the "awarded" statuses that gate TY eligibility
- `Thank_You_Status__c` — Picklist: `Not Started`, `In Progress`, `Submitted`, `Complete`
- `Thank_You_Letter__c` — Rich Text Area (131,072), stores HTML. **Cannot be used in SOQL WHERE clauses.** Filter in Apex instead. The 100-character minimum enforced in `ScholarshipThankYouController` and `scholarshipThankYousLwc` is measured on plain text stripped of HTML tags client-side — the Apex check still measures raw HTML length, so it's more lenient.
- `Thank_You_Photo_Rights_Accepted__c` — Checkbox for photo/quote usage consent
- `Thank_You_Submitted_Date__c` — DateTime, set on submit

---

## Portal Setup

- **Site name**: `EASY_Applicant_Portal`
- **Profile**: `EASY Applicant Portal Profile`
- **Permission Set**: `Application_Community` (EASY integration), `UST_Scholarship_Applicant` (scholarship access)
- **Portal base URL**: stored in `Application_Setting__c.Community_URL__c` (set by `adjust_custom_settings` task)
- **Template**: `ScholarshipTemplate2024` VF component — used by all portal pages

---

## Permission Sets in This Project

| Permission Set API Name | Audience |
|---|---|
| `UST_Scholarship_Admin` | Staff, Development Relations, Admins |
| `UST_Scholarship_Applicant` | Student portal users |

---

## Lightning Out Bridge

- **Aura app**: `easyAuraApp` (`force-app/main/default/aura/easyAuraApp/easyAuraApp.app`)
- Extends `ltng:outApp`
- **Every LWC used via Lightning Out must be declared** as `<aura:dependency resource="c:componentName"/>` in this app
- Current LWC dependencies: `scholarshipEligibleListView`, `scholarshipThankYousLwc`, `scholarshipApplicationControlsLwc`, `scholarshipRecommenderResendLwc`, `selectApplicationControlsLwc`

---

## Test Data Notes

- Scratch orgs are provisioned with **no sample data** by default unless a dataset is loaded
- `datasets/mapping.yml` exists but may or may not load TY-specific records
- For Apex tests: all test data must be inserted in the test class — `SeeAllData=true` is **never** used
- For `@AuraEnabled(cacheable=true)` methods: use `@TestSetup` with a unique sentinel field value to avoid cross-test cache collisions (see global instructions)

---

## SOQL Security Pattern

This codebase uses `with sharing` on class declarations only. **Do not add** `WITH USER_MODE` or `WITH SECURITY_ENFORCED` to SOQL queries — scratch org profiles without explicit FLS grants will fail at runtime. This is consistent across the entire codebase.

---

## Common Deploy Targets

```powershell
# LWCs
cci task run deploy --path force-app/main/default/lwc --org dev

# Single LWC
cci task run deploy --path force-app/main/default/lwc/scholarshipThankYousLwc --org dev

# Apex
cci task run deploy --path force-app/main/default/classes --org dev

# Objects / fields
cci task run deploy --path force-app/main/default/objects/Scholarship_Applicant__c --org dev

# Pages THEN permissions (order matters!)
cci task run deploy --path force-app/main/default/pages --org dev
cci task run deploy --path force-app/main/default/permissionsets --org dev
```

---

## Apex Test Classes

| Test Class | Covers |
|---|---|
| `ScholarshipThankYouController_TEST` | `ScholarshipThankYouController` — 15 tests, ~89% coverage |

> More test classes should be added as new controllers are built. Run with `--wait 20` to avoid "test already enqueued" errors.

