# AGENTS.md — UST Scholarships

Instructions for AI coding agents working in this repository. Read this file before making changes.

---

## 🚧 Actively Being Worked On: `thank_you_lwc` branch

The current branch (`thank_you_lwc`) is **active, in-progress work**. Two features are being developed together on it:

1. **Donor Thank-You LWC** — a student-facing thank-you letter workflow (`scholarshipThankYousLwc`, `ScholarshipThankYouController`). Requirements and delivery notes live in `docs/Student-Scholarship-Thank-You-Feature.md` and `docs/Thank-You-Feature-Implementation-Plan.md`.
2. **Generalizing `EASY_Widget__c` to embed arbitrary LWCs** — `EasyWidget.component` (legacy Visualforce) is being made more universal so any LWC can be embedded via a new `c:EasyLwc` Visualforce component + `Lightning_Web_Component__c` field on `EASY_Widget__c`, instead of hardcoding one `<c:ComponentName>` reference per `Widget_Type__c` value. Recent related work:
   - `force-app/main/default/components/EasyLwc.component` — new generic Lightning Out bridge component; renders whatever LWC name is stored in `widget.Lightning_Web_Component__c`
   - `EASY_Widget__c` fields: `Lightning_Web_Component__c`, `Widget_Type__c`, new `Student_Types__c` (backed by the new `Student_Types` global value set)
   - `EASY_Widget__c-EASY Widget Layout.layout-meta.xml` updated to surface these fields

**Implication for agents:** don't assume `EasyWidget.component` / `EASY_Widget__c` are stable — the widget-type-to-component mapping is being actively refactored. Check recent commit history on this branch before changing that area, and prefer extending the new generic `c:EasyLwc` pattern over adding another hardcoded `<c:ComponentName>` branch in `EasyWidget.component`.

Any LWC referenced dynamically through `EasyLwc.component` (via `$Lightning.createComponent("{!widget.Lightning_Web_Component__c}", ...)`) **must still be declared** as an `<aura:dependency>` in `easyAuraApp.app` — the dynamic lookup does not bypass that Lightning Out requirement.

---

## Project Overview

Salesforce DX project (CumulusCI-managed) for the University of St. Thomas scholarship application and management system: a student-facing Visualforce portal (via Lightning Out LWCs), internal Lightning record pages for staff/DR, and the Apex + LWC layer connecting them.

Full details: see [`README.md`](README.md) for setup/commands, [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) for the data model and component map, and [`docs/AI-TOOLS-CONFIG.md`](docs/AI-TOOLS-CONFIG.md) for object/field names, org aliases, and AI-assistant-specific gotchas.

---

## Ground Rules for Agents

- **Org alias**: CumulusCI tasks always use `--org dev`. For raw `sf` CLI commands, get the actual alias via `cci org info --org dev` → `sfdx_alias` (typically `UST-Scholarships__dev`). Never guess it.
- **Deploy order matters**: objects/fields → Apex classes → LWCs → Aura (`easyAuraApp`) → VF pages → permission sets. New VF pages must deploy before permission sets that reference their page access, or the deploy fails with `no ApexPage named X found`.
- **No `WITH USER_MODE` / `WITH SECURITY_ENFORCED`** in SOQL — this codebase relies on `with sharing` class-level enforcement only; scratch org profiles lack the FLS grants these clauses require and queries will fail at runtime.
- **No `ShowToastEvent`** in components rendered through Lightning Out (VF portal pages) — it's silently swallowed. Use inline feedback banners instead.
- **`Thank_You_Letter__c`** is a Rich Text Area (stores HTML) and, like other Long Text Area-family fields, cannot appear in a SOQL `WHERE` clause — filter in Apex. Render it with `lightning-formatted-rich-text` (never raw-bind it into a template) and edit it with `lightning-input-rich-text`.
- Every LWC invoked via Lightning Out (`$Lightning.createComponent`) — including dynamically by name, as `EasyLwc.component` now does — must have a matching `<aura:dependency resource="c:componentName"/>` in `easyAuraApp.app`.
- Prefer targeted `cci task run deploy --path <specific-folder> --org dev` over full org rebuilds for incremental changes.
- Run `npm test` (Jest) for LWC changes and `sf apex run test --class-names <Class>_TEST --target-org <alias> --wait 20` for Apex changes before considering work done. Required code coverage is 75%.
- Test data: never use `SeeAllData=true`; insert all test data in the test class itself.

For the full known-gotchas table (deploy errors, source-tracking cache issues, etc.) see the bottom of [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

---

## Building Thank-You Test Data in a Scratch Org

Scratch orgs come with **no `Scholarship__c` records that have `Thank_You_Required__c` set** — every scholarship loaded by default has that field blank, so no portal user has any thank-you obligations out of the box. To manually test/iterate on the thank-you feature for a given portal user (a `Contact`), do this via `sf data` (not CumulusCI — this is one-off data setup, not a repeatable dataset):

1. **Find the Contact:**
   ```powershell
   sf data query --query "SELECT Id, Name, Email FROM Contact WHERE LastName = 'Magnum'" --target-org UST-Scholarships__dev --result-format human
   ```

2. **Pick 2-3 `Scholarship__c` records and turn on `Thank_You_Required__c`.** Also populate `Financial_Aid_Code__c` and `Scholarship_Account__c` (lookup to `Account` — the donor) on the same records. `ScholarshipThankYouController.buildItem()` (`force-app/main/default/classes/ScholarshipThankYouController.cls:279-290`) surfaces a "Staff Notice" data-completeness warning banner on the letter card whenever either is blank — harmless, but noisy when you just want to test the write/submit flow:
   ```powershell
   sf data create record --sobject Account --values "Name='Some Donor Fund'" --target-org UST-Scholarships__dev

   sf data update record --sobject Scholarship__c --record-id <scholarshipId> --values "Thank_You_Required__c=Yes Financial_Aid_Code__c='ABC001' Scholarship_Account__c=<donorAccountId>" --target-org UST-Scholarships__dev
   ```

3. **Create a `Scholarship_Applicant__c` per scholarship, linking the Contact.** `Scholarship_Status__c` must be `Awarded` or `Accepted` for the record to be TY-eligible (see `docs/AI-TOOLS-CONFIG.md`). Vary `Thank_You_Status__c` to exercise different UI states — `Not Started` for the fresh-write flow, `In Progress` (with a `Thank_You_Letter__c` draft) for the resume/edit flow:
   ```powershell
   sf data create record --sobject Scholarship_Applicant__c --values "Contact__c=<contactId> Scholarship__c=<scholarshipId> Scholarship_Status__c='Awarded' Thank_You_Status__c='Not Started' Scholarship_Complete__c=true" --target-org UST-Scholarships__dev

   sf data create record --sobject Scholarship_Applicant__c --values "Contact__c=<contactId> Scholarship__c=<scholarshipId2> Scholarship_Status__c='Awarded' Thank_You_Status__c='In Progress' Thank_You_Letter__c='Dear donor, thank you so much for' Scholarship_Complete__c=true" --target-org UST-Scholarships__dev
   ```

4. **Verify:**
   ```powershell
   sf data query --query "SELECT Id, Name, Scholarship__r.Name, Scholarship_Status__c, Thank_You_Status__c, Thank_You_Letter__c FROM Scholarship_Applicant__c WHERE Contact__c = '<contactId>'" --target-org UST-Scholarships__dev --result-format human
   ```

Don't set `Thank_You_Status__c = 'Complete'` on test data unless you specifically want to test the read-only/locked state — `Complete` records reject further edits from both `saveThankYouDraft` and `submitThankYouLetter` (see the "Status lock" note in `docs/ARCHITECTURE.md`).
