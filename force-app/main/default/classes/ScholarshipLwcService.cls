/**
 * Cookie-free, parameter-driven service layer for the Scholarship LWCs on the Experience Cloud site.
 *
 * Every method here takes the scholarship id (the "sid" URL parameter) explicitly and never touches
 * ApexPages.currentPage(), cookies or PageReference. The applicant's Contact is always derived on the
 * server from the running user, never accepted from the client.
 *
 * The VF-facing methods in ScholarshipSharedUtilities are intentionally left untouched.
 */
public with sharing class ScholarshipLwcService {

    public static final String STATUS_NOT_FOUND = 'NOT_FOUND';
    public static final String STATUS_NOT_YET_OPEN = 'NOT_YET_OPEN';
    public static final String STATUS_CLOSED = 'CLOSED';
    public static final String STATUS_COMPLETE = 'COMPLETE';
    public static final String STATUS_OPEN = 'OPEN';

    /**
     * Simple status returned in place of the PageReference used by the VF flow. The LWC decides
     * where to navigate based on status.
     */
    public class AccessResult {
        @AuraEnabled public String status;
        @AuraEnabled public String scholarshipRecordId;
        @AuraEnabled public String scholarshipName;
        @AuraEnabled public String displayOpenDateTime;
        @AuraEnabled public String displayCloseDateTime;
    }

    /**
     * Pure read of the scholarship for an sid. Returns null when sid is blank or unknown.
     *
     * @param sid The scholarship id from the "sid" URL parameter.
     * @return The scholarship, or null when sid is blank or unknown.
     */
    @AuraEnabled(cacheable=true)
    public static Scholarship__c getScholarshipInfo(String sid) {
        return new ScholarshipReader().getBySid(sid);
    }

    /**
     * The running user's applicant record for a scholarship, or a new unsaved record if none exists.
     * Not cacheable: the result is user specific and changes after every save.
     *
     * @param scholarshipRecordId The Scholarship__c record id.
     * @return The running user's applicant record, or a new unsaved record if none exists.
     */
    @AuraEnabled(cacheable=false)
    public static Scholarship_Applicant__c getApplicantInfo(Id scholarshipRecordId) {
        return getApplicantForContact(scholarshipRecordId, ScholarshipSharedUtilities.getActiveContactId());
    }

    /**
     * Whether the running user may work on this scholarship right now, and if not, why.
     * Not cacheable: depends on the current time and on the applicant's current record.
     *
     * @param sid The scholarship id from the "sid" URL parameter.
     * @return The access status with the scholarship's name and its open and close times in Central Time.
     */
    @AuraEnabled(cacheable=false)
    public static AccessResult getAccessStatus(String sid) {
        return evaluateAccess(sid, ScholarshipSharedUtilities.getActiveContactId());
    }

    /**
     * Open/close check on a scholarship, using the same Central Time logic as the VF flow.
     *
     * @param scholarship The scholarship to check.
     * @return True when the scholarship is open right now.
     */
    public static Boolean isScholarshipOpen(Scholarship__c scholarship) {
        return ScholarshipSharedUtilities.isScholarshipOpen(scholarship);
    }

    @TestVisible
    private static Scholarship_Applicant__c getApplicantForContact(Id scholarshipRecordId, Id contactId) {
        if (scholarshipRecordId == null) {
            return null;
        }
        return ScholarshipSharedUtilities.getApplicantInfo(scholarshipRecordId, contactId);
    }

    @TestVisible
    private static AccessResult evaluateAccess(String sid, Id contactId) {
        AccessResult result = new AccessResult();
        Scholarship__c scholarship = new ScholarshipReader().getBySid(sid);

        if (scholarship == null) {
            result.status = STATUS_NOT_FOUND;
            return result;
        }

        result.scholarshipRecordId = scholarship.Id;
        result.scholarshipName = scholarship.Name;

        Map<String, Datetime> openCloseDatetime = ScholarshipSharedUtilities.scholarshipOpenCloseDatetime(scholarship);
        Datetime openDatetime = openCloseDatetime.get('Open');
        Datetime closeDatetime = openCloseDatetime.get('Close');
        if (openDatetime != null) {
            result.displayOpenDateTime = ScholarshipClosedController.displayDateTimeTz(openDatetime, 'America/Chicago');
        }
        if (closeDatetime != null) {
            result.displayCloseDateTime = ScholarshipClosedController.displayDateTimeTz(closeDatetime, 'America/Chicago');
        }

        // Same precedence as ScholarshipSharedUtilities.checkScholarshipAccess(): a completed
        // application is routed to the Complete page even if the scholarship has since closed.
        Scholarship_Applicant__c applicant = getApplicantForContact(scholarship.Id, contactId);
        if (applicant != null && applicant.Scholarship_Complete__c == true) {
            result.status = STATUS_COMPLETE;
        } else if (ScholarshipSharedUtilities.isScholarshipOpen(scholarship)) {
            result.status = STATUS_OPEN;
        } else if (openDatetime != null && openDatetime > ScholarshipSharedUtilities.adjustForCentralTime(Datetime.now())) {
            result.status = STATUS_NOT_YET_OPEN;
        } else {
            result.status = STATUS_CLOSED;
        }
        return result;
    }

    /**
     * Scholarship configuration is not user-owned data. The VF flow reads it in system context
     * (ScholarshipSharedUtilities is "without sharing"), so Experience users get the same behavior
     * here without needing sharing access to every Scholarship__c record. Only this lookup runs
     * without sharing; applicant data is always filtered by the running user's own Contact.
     */
    private without sharing class ScholarshipReader {
        public Scholarship__c getBySid(String sid) {
            if (String.isBlank(sid)) {
                return null;
            }
            List<Scholarship__c> scholarships = [
                    SELECT Close_Date__c, Completion_Statement__c, Criteria_Statement__c, Description__c, Essay_1_Text__c, Essay_2_Text__c,
                            Id, Name, Open_Date__c, OwnerId, Question_1_Text__c, Question_2_Text__c, Question_3_Text__c, Question_4_Text__c,
                            Recommender2_Auto_Send__c, Recommender2_Description__c, Recommender2_Question__c, Recommender2__c, Recommender_Auto_Send__c,
                            Recommender_Description__c, Recommender_Question__c, Recommender__c, Scholarship_ID__c, Short_Description__c,
                            Review_Award_Process_Description__c, Self_Report_ACT_GPA_Criteria__c, Essay_1_Allow_Upload__c, Essay_2_Allow_Upload__c,
                            Communicated_Close_Date__c, Org_Wide_Email_Id__c, Submit_Scholarship_Email_Template_Id__c, Send_Started_Scholarship_Email__c,
                            Start_Scholarship_Email_Template_Id__c, Recommender_Option__c, Recommender2_Option__c, Recommender_Email_Template_Id__c,
                            Recommender2_Email_Template_Id__c, RecordTypeId, Open_Time__c, Close_Time__c
                    FROM Scholarship__c
                    WHERE Scholarship_ID__c = :sid
                    LIMIT 1
            ];
            return scholarships.isEmpty() ? null : scholarships[0];
        }
    }
}
