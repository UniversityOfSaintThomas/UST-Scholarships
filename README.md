# UST Scholarships — Salesforce DX Project

A Salesforce DX project managed with [CumulusCI](https://cumulusci.readthedocs.io/) that powers the scholarship application and management system for the University of St. Thomas. It provides a student-facing Visualforce portal (via Lightning Out), internal Salesforce record pages for staff/DR use, and the underlying Apex + LWC components that connect them.

---

## Table of Contents

- [Features](#features)
- [Project Structure](#project-structure)
- [Prerequisites](#prerequisites)
- [Development Setup](#development-setup)
- [Common Commands](#common-commands)
- [Testing](#testing)
- [Deployment](#deployment)
- [Docs](#docs)

---

## Features

| Area | Description |
|---|---|
| **Scholarship Browsing** | Students browse eligible scholarships on the portal via `ScholarshipHome` page |
| **Multi-Page Application** | Students complete 2-page applications (`ScholarshipApplicationPage1/2`) with essays, recommenders, GPA/ACT, and supporting questions |
| **Recommender Requests** | Auto-send recommender emails; resend support via `scholarshipRecommenderResendLwc` |
| **Communication Templates** | Staff manage email templates for each scholarship lifecycle stage via `scholarshipCommunicationTemplatesLwc` |
| **Eligible Scholarship List** | `scholarshipEligibleListView` dynamically shows applicable scholarships based on application criteria (program, citizenship, degree type) |
| **Thank-You Letters** | Students write, save drafts, preview, and submit thank-you letters per scholarship; staff view status on the `Scholarship_Applicant__c` record page |

---

## Project Structure

```
force-app/main/default/
├── classes/               # Apex controllers & utilities
├── lwc/                   # Lightning Web Components
├── pages/                 # Visualforce portal pages
├── aura/                  # Lightning Out bridge (easyAuraApp)
├── objects/               # Custom object & field definitions
│   ├── Scholarship__c/
│   ├── Scholarship_Applicant__c/
│   ├── Award__c/
│   └── EASY_Widget__c/
├── permissionsets/        # UST_Scholarship_Admin, UST_Scholarship_Applicant
├── components/            # Legacy Visualforce components
├── globalValueSets/       # Shared picklist value sets
└── layouts/               # Page layouts
```

Key component / class mapping:

| VF Page | Apex Controller | LWC Component |
|---|---|---|
| `ScholarshipHome` | `ScholarshipHomeController` | `scholarshipEligibleListView` |
| `ScholarshipApplicationPage1` | `ScholarshipApplicationPage1Controller` | — |
| `ScholarshipApplicationPage2` | `ScholarshipApplicationPage2Controller` | — |
| `ScholarshipApplicationComplete` | `ScholarshipApplicationCompleteController` | — |
| `ScholarshipClosed` | `ScholarshipClosedController` | — |
| `ScholarshipRecommender` | `ScholarshipRecommenderController` | — |
| `ScholarshipThankYou` | *(Lightning Out — no VF controller)* | `scholarshipThankYousLwc` |
| *(Record page)* | `ScholarshipCommunicationTemplates` | `scholarshipCommunicationTemplatesLwc` |
| *(Record page)* | `ScholarshipThankYouController` | `scholarshipThankYousLwc` |

---

## Prerequisites

- [Node.js](https://nodejs.org/) v18+
- [Python](https://www.python.org/) 3.10+
- [CumulusCI](https://cumulusci.readthedocs.io/) — `pip install cumulusci`
- [Salesforce CLI](https://developer.salesforce.com/tools/sfdxcli) — `sf`
- A Salesforce Dev Hub org authorized via `sf org login web --set-default-dev-hub`

---

## Development Setup

```powershell
# 1. Install JS dependencies
npm install

# 2. Create a scratch org (full initial setup only)
cci flow run dev_org --org dev

# 3. Confirm org is alive
cci org info --org dev
```

> ⚠️ `cci flow run dev_org` creates a **new** scratch org. Use it for initial setup only — never for incremental changes.

---

## Common Commands

```powershell
# Deploy a single component (fast, incremental)
cci task run deploy --path force-app/main/default/lwc/componentName --org dev

# Deploy all LWCs
cci task run deploy --path force-app/main/default/lwc --org dev

# Deploy Apex classes
cci task run deploy --path force-app/main/default/classes --org dev

# Open scratch org in browser
cci org browser --org dev

# List all orgs
cci org list
```

---

## Testing

### LWC (Jest)

```powershell
npm test                    # All Jest tests
npm test -- --coverage      # With coverage report
```

### Apex

```powershell
# Run a specific test class (preferred)
sf apex run test `
  --class-names ScholarshipThankYouController_TEST `
  --target-org UST-Scholarships__dev `
  --result-format human `
  --code-coverage `
  --wait 20

# Run all tests via CumulusCI
cci task run run_tests --org dev
```

> **Org alias note:** CumulusCI always uses `--org dev`. Salesforce CLI uses the `sfdx_alias` shown in `cci org info --org dev` — typically `UST-Scholarships__dev`.

Required org code coverage: **75%** (configured in `cumulusci.yml`).

---

## Deployment

Prefer targeted deploys over full rebuilds:

```powershell
# Single LWC
cci task run deploy --path force-app/main/default/lwc/scholarshipThankYousLwc --org dev

# Object fields
cci task run deploy --path force-app/main/default/objects/Scholarship_Applicant__c --org dev

# Permission sets (deploy VF pages FIRST if new page access was added)
cci task run deploy --path force-app/main/default/pages --org dev
cci task run deploy --path force-app/main/default/permissionsets --org dev
```

See [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) for deployment ordering and known gotchas.

---

## Docs

| File | Description |
|---|---|
| [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) | Technical architecture, data model, Lightning Out pattern, component map |
| [`docs/AI-TOOLS-CONFIG.md`](docs/AI-TOOLS-CONFIG.md) | AI assistant project config (org aliases, object names, test data notes) |
| [`docs/Student-Scholarship-Thank-You-Feature.md`](docs/Student-Scholarship-Thank-You-Feature.md) | Requirements for the Thank-You Letter feature |
| [`docs/Thank-You-Feature-Implementation-Plan.md`](docs/Thank-You-Feature-Implementation-Plan.md) | Implementation plan and delivery notes for the Thank-You feature |
