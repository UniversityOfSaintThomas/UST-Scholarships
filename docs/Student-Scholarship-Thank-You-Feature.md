## Goals & Requirements

### Introduction

The current process for managing student scholarship thank you notes is very time consuming, manual, and does not
have a lot of guard rails in place to monitor whether or not students follow through with writing thank you letters to
scholarship sponsors. The goal of this effort is to alleviate the manual processes and create a workflow based on
Salesforce to automate the necessary steps and provide timely dashboards or reporting to validate that the necessary
steps are completed in a timely fashion. The team desires more efficiency, consistency, and fluidity. The financial aid
team is a key stakeholder in this process - and new considerations to the process needed especially with the transition
to the new ERP.

### Product Goals & Requirements

A quick primer on product / solution goals & requirements:

**Product goals** are intermediate goals that advance us toward a comprehensive solution to meet our needs. They
describe a specific benefit or outcome a product should create. They are often written in the form of “Do something for
the user and/or business with this purpose.”.

**User requirements** describe more specifically what users will be able to do when the envisioned solution is in place.
User requirements are often written as” As a <user type>, I want to <do something> so <reason or purpose> OR more
simply <User type> will be able to <do something>.

**Functional requirements** describe what functionality the system will have to enable users to do these things. Functional
requirements often take the form of: The system or solution will <do something>.

Finally, we also want to consider some **non-functional requirements**. These describe how well the system should
behave (things like performance, security, usability, maintainability, cost, interoperability and so on). They

### Customers and Users

Before we get into goals & requirements, it is helpful to have a shared understanding of who our customers and users
will be. The customer is the person who pays for the product or service vs. someone who uses it. List these below.

- <Customer name>
- <User name>

### Product Goals

Again, product goals describe a specific benefit or outcome a product should create. A template like the one below can
help draft these goals. Most of your product goals will likely be directed at your customers.

```
Action verb
Do this...
```
```
Capability, For who
What and for...
```
```
Why and timeframe (optional)
So that...
Launch, grow, develop... specific feature for user... so that this benefit is realized.
```

## Goals & Requirements

### Functional Requirements

User & functional requirements will be categorized by key features needed to realize the goals above. Non-functional
requirements will follow. Prior to including these in an RFP, you will want to work with a larger group of stakeholders to
determine which of these are must have vs. should, could or won’t have requirements. You can write these in user story
form: As a <user role>, I want/need to <do something> so that <benefit> OR verb / object form: <User> will <do
something>. It sometime can help to organize by Product Goal or identified Themes.

##### Theme or Goal Name

- _<Username> will <do something> OR_
- _As a <username>, I want to <do something> so that <goal or result>._

##### T he m e 1 - V i si bi l i ty, C l a r i ty & T r i g g e r i ng of T Y R e qui r e m e nts

- **Unified Requirement Display**
  The TY requirement must appear prominently and unambiguously in the student portal with plain language
  instructions, avoiding financial aid jargon.
- **RealTime Requirement Status Sync**
  Requirement statuses (Not Started, In Progress, Submitted, Complete) must update across systems within 5– 10
  minutes, reflecting the Desired Outcomes’ emphasis on “timely information.”
- **Clear Ownership Messaging**
  Students must see _who_ is asking for the TY letter (e.g., “Donor Relations Requirement” rather than generic
  “Financial Aid Requirement”) to reduce confusion.
- **Integrated Explanation of WHY This Is Required**
  Students must see a short explanation:
  _“Your thank-you letter lets us steward your scholarship donors and maintain funding.”_
  This directly supports outcomes around “understanding expectations.”
- **Error Detection for Missing/Mismatched Data**
  If FA code, scholarship name, or student eligibility is missing/ambiguous, the system must flag it to staff before
  presenting the requirement to the student. This aligns with the Desired Outcome: “accurate information
  reduces frustration.”

##### Theme 2 - Student Guidance, Simplicity & Self-Service

- **Simplified, Plain-Language Instructions**
  All content must follow plain-language guidelines and display on one page - no scrolling between multiple
  sources.
- **Embedded Examples & AutoFormatting**
  To help students craft quality letters independently, the system must provide inline examples and apply
  formatting automatically (date, salutation, spacing).
- **Mobile-Friendly Submission**
  Students must be able to complete the entire process on a smartphone, consistent with Outcomes about
  convenience and accessibility.
- **Inline Error-Checking for Narrative Quality**
  Require minimum length (e.g., 3–5 sentences) and prevent accidental blank submissions or incomplete text -
  supporting “reduce rework” and “consistent outputs.”


## Goals & Requirements

- **Student View of Sent/Completed Letters**
  Students must be able to _see a copy_ of what they submitted, aligned with outcomes around transparency and
  empowerment.
- Students must be able to see an editable preview of their essay before submitting their final response.
- When a student submits their response to an individual TY letter, the status indicator will automatically change
  for that one letter.
- The system will allow students to use their responses for multiple scholarship essays if they choose.
- The system should include the ability for students to upload a photo of themselves and validate acceptance of
  rights for usage, quotations, etc.

##### T he m e 3 - Str e a m l i ne d D R I nta ke , V a l i da ti on & D onor C onta c t M a tc hi ng

- **Automated Donor Contact Matching with Confidence Score**
  The system should automatically match donor contacts based on designation number and FA code, with manual
  fallback options. Reduces manual tracking.
- **Single Unified Review Dashboard**
  Instead of spreadsheets, DR must have a dashboard where all submissions, edits, donor contacts, and statuses
  are visible and sortable.
- **Standardized DR Editing Rules**
  Provide a lightweight editing interface with predefined rules (e.g., spelling/grammar only; no changing
  meaning). This aligns with “consistency across staff.”
- **Multi Contact Stewardship Handling**
  System must support multiple donor recipients per scholarship with logic-driven grouping - reflecting Desired
  Outcomes around accuracy and completeness.
- **Automated Logging of Review Actions**
  Every DR edit, donor match, or override must be logged with reason and timestamp to maintain consistency and
  transparency.

##### Theme 4 - Efficient Letter Production, Approval & Mailing

- **Automated Vendor-Ready Exports**
  Eliminate manual spreadsheet building by generating clean, formatted exports directly from the system.
- **Consolidated Donor Deliverables**
  Apply automated grouping rules (e.g., 5 TYs → 1 envelope) and show DR a preview before vendor submission.
- **Template Governance & Version Tracking**
  Ensure all letters use consistent branding and structure. Changes require approval, supporting the “consistency”
  Desired Outcome.
- **Batch-Level QA Checklist**
  Before sending to vendor, system must automatically validate required fields, missing addresses, and unmapped
  contacts.
- **Automatic Status Update After Mailing**
  Once mailing is confirmed, system marks requirement **Complete** and logs mailing details for Donor record -
  aligned with Desired Outcomes around “timely and accurate updates.”


## Goals & Requirements

##### Theme 5 - Proactive Reminders, Reporting, and Long-Term Stewardship

- **Behavior-Based Reminder Scheduling**
  Instead of periodic blasts, reminders must be triggered based on student behavior (e.g., viewed requirement but
  not started). Aligns with “give the right info at the right time.”
- **Student-Friendly Reminder Messages**
  Reminders must be concise, consistent, and personalized, using a standard template aligned with Desired
  Outcome: “plain, clear communication.”
- **Completion Analytics for Donor Relations and Leadership**
  Provide real-time status dashboards for scholarship information, donor/GO assigned, open/closed TYs, aging,
  peak timelines, and funnel drop-off to support process improvement.
- **Donor Impact Reporting Integration**
  Letters uploaded to Optix must map to designation or program folder automatically, supporting long-term
  stewardship accuracy.
- **Continuous Improvement Feedback Loop**
  DR and FA staff can flag process issues directly in the system (e.g., mismatched DNames, confusing instructions),
  feeding a small governance workflow to update templates or rules.

We may rewrite these as questions in the RFP with the prefix “Does/how does the solution”....” rewording slightly as
needed.

### Non-Functional & Technical Requirements

Non-functional requirements describe HOW WELL the system should behave within a particular context. Include only
those critical to success. They can take the form of “The solution will <describe performance and context>.” It can be
helpful to categorize these into categories such as Security, Performance, Availability, Usability, Accessibility,
Interoperability (Integration), Maintenance, Reliability, etc.

#### <Non-functional category>

- The solution will...
-

#### <Non-functional category>

- The solution will...

### AI Support

It can be helpful to kick-start project goals and requirements using AI. The AI_For_RFPs.docx document provides tips and
examples for using AI models to support project goal and requirements development (and other project-related work
too).

Next steps: data, what the scholarship sources look like. Take that and look at scholarship objects and see how it would
be mapped, staging environment. Thad has meeting next week with Patrick and team. Could create test records in prep
for next week meeting (week of March 23rd).


## Goals & Requirements

Our team tracks everything in Jira, so I started a Jira story for us to add notes and start scoping our work:
https://stthomas.atlassian.net/browse/ECRMSF- 5238


