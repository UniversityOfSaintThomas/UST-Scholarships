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
- **`Thank_You_Letter__c`** (and other Long Text Area fields) cannot appear in a SOQL `WHERE` clause — filter in Apex.
- Every LWC invoked via Lightning Out (`$Lightning.createComponent`) — including dynamically by name, as `EasyLwc.component` now does — must have a matching `<aura:dependency resource="c:componentName"/>` in `easyAuraApp.app`.
- Prefer targeted `cci task run deploy --path <specific-folder> --org dev` over full org rebuilds for incremental changes.
- Run `npm test` (Jest) for LWC changes and `sf apex run test --class-names <Class>_TEST --target-org <alias> --wait 20` for Apex changes before considering work done. Required code coverage is 75%.
- Test data: never use `SeeAllData=true`; insert all test data in the test class itself.

For the full known-gotchas table (deploy errors, source-tracking cache issues, etc.) see the bottom of [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).
