/**
 * Apex controller for the ScholarshipAppPage1Lwc component (Page 1 of the scholarship application).
 *
 * LWC counterpart of ScholarshipApplicationPage1Controller. It never reads ApexPages, cookies or
 * PageReference: the scholarship id (the "sid" URL parameter) is passed in explicitly, and the
 * applicant's Contact is always derived on the server from the running user.
 *
 * Instead of redirecting with a PageReference, every method returns the access status from
 * ScholarshipLwcService so the LWC can decide where to navigate.
 */
public with sharing class ScholarshipAppPage1LwcController {

    public static final String APPLICANT_STATUS_STARTED = 'Started App';

    // Same lower bounds the VF flow enforced client side in validateCriteria() (scripts.js).
    // Upper bounds come from the Scholarship_Applicant__c field definitions:
    // Declared_GPA__c is Number(3,2) and Declared_ACT_SAT__c is Number(4,0).
    @TestVisible private static final Decimal MIN_GPA = 1.0;
    @TestVisible private static final Decimal MAX_GPA = 9.99;
    @TestVisible private static final Decimal MIN_ACT_SAT = 10;
    @TestVisible private static final Decimal MAX_ACT_SAT = 9999;

    public class PageData {
        @AuraEnabled public String status;
        @AuraEnabled public String scholarshipName;
        @AuraEnabled public String description;
        @AuraEnabled public String criteriaStatement;
        @AuraEnabled public Boolean selfReportRequired = false;
        @AuraEnabled public Decimal declaredGpa;
        @AuraEnabled public Decimal declaredActSat;
        @AuraEnabled public Boolean confirmedCriteria = false;
        @AuraEnabled public List<String> configWarnings = new List<String>();
    }

    public class SaveResult {
        @AuraEnabled public Boolean success = false;
        @AuraEnabled public String status;
        @AuraEnabled public String message;
        @AuraEnabled public Boolean startedEmailFailed = false;
    }

    /**
     * Everything Page 1 needs to render, plus the access status. The LWC redirects when the status
     * is anything other than OPEN. Not cacheable: depends on the current time and the applicant's record.
     */
    @AuraEnabled(Cacheable=false)
    public static PageData getPageData(String sid) {
        return buildPageData(sid, ScholarshipSharedUtilities.getActiveContactId(), ScholarshipLwcService.getAccessStatus(sid));
    }

    /**
     * Mirrors SaveCriteria() in the VF controller: creates or updates the running user's
     * Scholarship_Applicant__c, stamps the start date once and sends the "started" email once.
     * Only the confirmation and self-reported values are accepted from the client.
     */
    @AuraEnabled(Cacheable=false)
    public static SaveResult saveCriteria(String sid, Decimal declaredGpa, Decimal declaredActSat, Boolean confirmed) {
        return saveCriteriaForContact(sid, declaredGpa, declaredActSat, confirmed,
                ScholarshipSharedUtilities.getActiveContactId(), ScholarshipLwcService.getAccessStatus(sid));
    }

    @TestVisible
    private static PageData buildPageData(String sid, Id contactId, ScholarshipLwcService.AccessResult access) {
        PageData data = new PageData();
        data.status = access.status;

        Scholarship__c scholarship = ScholarshipLwcService.getScholarshipInfo(sid);
        if (scholarship == null) {
            data.status = ScholarshipLwcService.STATUS_NOT_FOUND;
            return data;
        }

        data.scholarshipName = scholarship.Name;
        data.description = scholarship.Description__c;
        data.criteriaStatement = scholarship.Criteria_Statement__c;
        data.selfReportRequired = scholarship.Self_Report_ACT_GPA_Criteria__c == true;

        // Nothing else is needed when the LWC is going to redirect.
        if (access.status != ScholarshipLwcService.STATUS_OPEN) {
            return data;
        }

        if (contactId != null) {
            Scholarship_Applicant__c applicant = ScholarshipSharedUtilities.getApplicantInfo(scholarship.Id, contactId);
            data.declaredGpa = applicant.Declared_GPA__c;
            data.declaredActSat = applicant.Declared_ACT_SAT__c;
            data.confirmedCriteria = applicant.Confirmed_Criteria__c == true;
        }
        data.configWarnings = configWarnings(scholarship);
        return data;
    }

    @TestVisible
    private static SaveResult saveCriteriaForContact(String sid, Decimal declaredGpa, Decimal declaredActSat, Boolean confirmed,
            Id contactId, ScholarshipLwcService.AccessResult access) {
        SaveResult result = new SaveResult();

        Scholarship__c scholarship = ScholarshipLwcService.getScholarshipInfo(sid);
        if (scholarship == null) {
            result.status = ScholarshipLwcService.STATUS_NOT_FOUND;
            result.message = 'Scholarship not found.';
            return result;
        }

        // Same gate as the VF sanityCheck: only an open, not yet completed application can be saved.
        result.status = access.status;
        if (access.status != ScholarshipLwcService.STATUS_OPEN) {
            result.message = 'This scholarship is not currently available for editing.';
            return result;
        }

        if (contactId == null) {
            result.message = 'Your user is not linked to a contact record.';
            return result;
        }

        Boolean selfReportRequired = scholarship.Self_Report_ACT_GPA_Criteria__c == true;
        List<String> errors = validate(selfReportRequired, declaredGpa, declaredActSat, confirmed);
        if (!errors.isEmpty()) {
            result.message = String.join(errors, ' ');
            return result;
        }

        Scholarship_Applicant__c applicant = ScholarshipSharedUtilities.getApplicantInfo(scholarship.Id, contactId);
        Boolean sendStartedEmail = false;

        applicant.Scholarship__c = scholarship.Id;
        applicant.Confirmed_Criteria__c = true;
        applicant.Scholarship_Status__c = APPLICANT_STATUS_STARTED;
        if (selfReportRequired) {
            applicant.Declared_GPA__c = declaredGpa;
            applicant.Declared_ACT_SAT__c = declaredActSat;
        }
        // For Lightning Email Template merge
        applicant.Review_Award_Process_Description__c = scholarship.Review_Award_Process_Description__c;
        applicant.Scholarship_Communicated_Close_Date__c = scholarship.Communicated_Close_Date__c;
        applicant.Recommender_Question__c = scholarship.Recommender_Question__c;
        applicant.Recommender2_Question__c = scholarship.Recommender2_Question__c;

        if (applicant.Scholarship_Date_Started__c == null) {
            sendStartedEmail = scholarship.Send_Started_Scholarship_Email__c == true;
            applicant.Scholarship_Date_Started__c = Datetime.now();
        }
        if (String.isBlank(applicant.Contact__c)) {
            applicant.Contact__c = contactId;
        }

        try {
            upsert applicant;
        } catch (DmlException ex) {
            result.message = 'Scholarship not saved: ' + ex.getDmlMessage(0);
            return result;
        }

        if (sendStartedEmail) {
            result.startedEmailFailed = !sendStartedEmail(scholarship, applicant.Id, contactId);
        }

        result.success = true;
        return result;
    }

    /**
     * Returns false if the "started" email could not be built or sent. The application is already
     * saved at this point, so a failure only produces a warning for the applicant.
     */
    private static Boolean sendStartedEmail(Scholarship__c scholarship, Id applicantId, Id contactId) {
        try {
            Scholarship_Applicant__c saved = ScholarshipSharedUtilities.getApplicantInfo(scholarship.Id, contactId);
            ScholarshipSharedUtilities.emailUtilities emailBuilder = new ScholarshipSharedUtilities.emailUtilities();
            List<Messaging.SingleEmailMessage> emailsToSend = new List<Messaging.SingleEmailMessage>{
                    emailBuilder.createEmail(scholarship.Start_Scholarship_Email_Template_Id__c, scholarship.Org_Wide_Email_Id__c,
                            applicantId, saved.Contact__c, saved.Contact__r.Email)
            };
            emailBuilder.sendCreatedEmails(emailsToSend);
            return true;
        } catch (Exception ex) {
            System.debug('Send Start Email exception: ' + ex.getMessage());
            return false;
        }
    }

    /**
     * Server side authority for the rules the browser also checks (see criteriaValidation.js).
     */
    @TestVisible
    private static List<String> validate(Boolean selfReportRequired, Decimal declaredGpa, Decimal declaredActSat, Boolean confirmed) {
        List<String> errors = new List<String>();

        if (selfReportRequired) {
            if (declaredGpa == null || declaredGpa < MIN_GPA || declaredGpa > MAX_GPA) {
                errors.add('Please enter a valid GPA (example 3.5).');
            }
            if (declaredActSat == null || declaredActSat < MIN_ACT_SAT || declaredActSat > MAX_ACT_SAT
                    || declaredActSat.setScale(0, RoundingMode.DOWN) != declaredActSat) {
                errors.add('Please enter a valid ACT/SAT score (example 27).');
            }
        }
        if (confirmed != true) {
            errors.add('You must confirm that you meet the eligibility criteria to continue.');
        }
        return errors;
    }

    /**
     * Same administrator-facing setup checks the VF page showed through ApexPages.addMessage.
     */
    @TestVisible
    private static List<String> configWarnings(Scholarship__c scholarship) {
        List<String> warnings = new List<String>();

        List<RecordType> scholarshipType = [
                SELECT Id
                FROM RecordType
                WHERE SobjectType = 'Scholarship__c'
                AND Id = :scholarship.RecordTypeId
                AND DeveloperName IN ('Graduate_Scholarship', 'Scholarship', 'Signature_Programs')
        ];
        if (scholarshipType.isEmpty()) {
            return warnings;
        }

        if (String.isBlank(scholarship.Org_Wide_Email_Id__c)) {
            warnings.add('Org Wide Email Not Set');
        }
        if (scholarship.Send_Started_Scholarship_Email__c == true && String.isBlank(scholarship.Start_Scholarship_Email_Template_Id__c)) {
            warnings.add('Started Email Template Not Set');
        }
        if (String.isBlank(scholarship.Submit_Scholarship_Email_Template_Id__c)) {
            warnings.add('Submit Email Template Not Set');
        }
        if ((scholarship.Recommender_Option__c == 'Recommender Required' || scholarship.Recommender_Option__c == 'Recommender Optional')
                && String.isBlank(scholarship.Recommender_Email_Template_Id__c)) {
            warnings.add('Recommender 1 Email Template Not Set');
        }
        if ((scholarship.Recommender2_Option__c == 'Recommender2 Required' || scholarship.Recommender2_Option__c == 'Recommender2 Optional')
                && String.isBlank(scholarship.Recommender2_Email_Template_Id__c)) {
            warnings.add('Recommender 2 Email Template Not Set');
        }
        return warnings;
    }
}
