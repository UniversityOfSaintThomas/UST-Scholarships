/**
 * Apex controller for the scholarshipAppCompleteLwc component (the confirmation page shown after an application
 * is submitted).
 *
 * LWC counterpart of ScholarshipApplicationCompleteController. It never reads ApexPages, cookies or
 * PageReference: the scholarship id (the "sid" URL parameter) is passed in explicitly and the applicant is always
 * derived on the server from the running user. That matters here because ScholarshipSharedUtilities.emailUtilities
 * reads Tasks and EmailMessages without sharing, so it must only ever be given the running user's own applicant.
 *
 * Unlike the VF page, which showed the confirmation to anyone who opened it, the details are only returned for
 * an application that has actually been submitted.
 */
public with sharing class ScholarshipAppCompleteLwcController {

    public static final String STATUS_UNOPENED = 'Unopened';

    public class RecommenderStatus {
        @AuraEnabled public Integer recommenderNumber;
        @AuraEnabled public String name;
        @AuraEnabled public String email;
        // When the request email was sent, as MM/dd/yyyy in Central Time.
        @AuraEnabled public String requestedOn;
        // "Opened" or "Unopened", from ScholarshipSharedUtilities.emailUtilities.emailStatus().
        @AuraEnabled public String status;
    }

    public class PageData {
        @AuraEnabled public String status;
        @AuraEnabled public String scholarshipName;
        @AuraEnabled public String reviewAwardProcessDescriptionHtml;
        // Only the recommenders whose request was sent.
        @AuraEnabled public List<RecommenderStatus> recommenders = new List<RecommenderStatus>();
    }

    /**
     * Everything the Complete page shows, plus the access status. The LWC redirects when the status is anything
     * other than COMPLETE. Not cacheable: depends on the applicant's record and on whether the emails were opened.
     *
     * @param sid The scholarship id from the "sid" URL parameter.
     * @return The scholarship name, the "what happens next" text, the recommender request status and the access status.
     */
    @AuraEnabled(cacheable=false)
    public static PageData getPageData(String sid) {
        return buildPageData(sid, ScholarshipSharedUtilities.getActiveContactId(), ScholarshipLwcService.getAccessStatus(sid));
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

        // Only a submitted application gets the details; the LWC redirects for every other status.
        if (access.status != ScholarshipLwcService.STATUS_COMPLETE) {
            return data;
        }

        Scholarship_Applicant__c applicant = contactId == null ? null : ScholarshipSharedUtilities.getApplicantInfo(scholarship.Id, contactId);
        if (applicant == null || applicant.Id == null || applicant.Scholarship_Complete__c != true) {
            data.status = ScholarshipLwcService.STATUS_OPEN;
            return data;
        }

        data.reviewAwardProcessDescriptionHtml = scholarship.Review_Award_Process_Description__c;

        ScholarshipSharedUtilities.emailUtilities emailChecker = new ScholarshipSharedUtilities.emailUtilities();
        for (Integer n = 1; n <= 2; n++) {
            String suffix = n == 2 ? '2' : '';
            Datetime requestedOn = (Datetime) applicant.get('Recommendation' + suffix + '_Request_Date__c');
            if (requestedOn == null) {
                continue;
            }
            RecommenderStatus recommender = new RecommenderStatus();
            recommender.recommenderNumber = n;
            recommender.name = (String) applicant.get('Recommender' + suffix + '_Name__c');
            recommender.email = (String) applicant.get('Recommender' + suffix + '_Email__c');
            recommender.requestedOn = requestedOn.format('MM/dd/yyyy', 'America/Chicago');
            recommender.status = String.isBlank(recommender.email) ? STATUS_UNOPENED : emailChecker.emailStatus(applicant.Id, recommender.email);
            data.recommenders.add(recommender);
        }
        return data;
    }
}
