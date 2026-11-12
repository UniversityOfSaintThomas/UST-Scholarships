/**
 * Apex controller for the scholarshipRecommenderLwc component: the page an outside recommender (a teacher or an
 * employer) opens from the emailed link to read the request and submit a recommendation.
 *
 * LWC counterpart of ScholarshipRecommenderController. Recommenders have no login, so the page is open to
 * guests and the link is the only credential: "recId" is the applicant record's Id followed by 1 or 2 for the
 * first or second recommender, exactly the links Recommendation_Link__c and Recommendation_Link_2__c already put
 * in the emails.
 *
 * Reading and writing the applicant needs access a guest user does not have, so those two steps are the only
 * ones that run without sharing, in a private inner class, and each touches only the one record the link names.
 * Compared with the VF page it also: refuses a link whose request was never sent, refuses a second submission on
 * the server (the VF page only hid the form), refuses an empty recommendation, and updates only the
 * recommendation text and its received date, not the whole record.
 */
public with sharing class ScholarshipRecommenderLwcController {

    // The form can be filled in.
    public static final String STATUS_READY = 'READY';
    // A recommendation was already submitted for this link.
    public static final String STATUS_RECEIVED = 'RECEIVED';
    // The link is malformed, names no applicant, or names a recommender whose request was never sent.
    public static final String STATUS_INVALID_LINK = 'INVALID_LINK';

    // Recommendation__c and Recommendation2__c are 32768 character rich text areas.
    @TestVisible private static final Integer MAX_RECOMMENDATION_LENGTH = 32768;

    public class PageData {
        @AuraEnabled public String status = STATUS_INVALID_LINK;
        @AuraEnabled public String scholarshipName;
        // The applicant's first and last name, as the VF page showed them.
        @AuraEnabled public String applicantName;
        @AuraEnabled public String recommenderName;
        @AuraEnabled public String scholarshipDescriptionHtml;
        @AuraEnabled public String questionHtml;
        // Text already stored for this recommendation, if any.
        @AuraEnabled public String recommendationHtml;
    }

    public class SaveResult {
        @AuraEnabled public Boolean success = false;
        @AuraEnabled public String status = STATUS_INVALID_LINK;
        @AuraEnabled public String message;
    }

    /** What the "recId" in the link names. */
    @TestVisible
    private class RecommendationLink {
        public Id applicantId;
        public Integer recommenderNumber;
    }

    /**
     * What the recommender sees when they open the link. Nothing about the applicant is returned unless the link
     * is valid and the request was actually sent. Not cacheable: depends on whether it was already submitted.
     *
     * @param recId The "recId" from the link: the applicant's Id followed by 1 or 2.
     * @return The request details and a status of READY, RECEIVED or INVALID_LINK.
     */
    @AuraEnabled(cacheable=false)
    public static PageData getRecommendationRequest(String recId) {
        PageData data = new PageData();

        RecommendationLink link = parseLink(recId);
        if (link == null) {
            return data;
        }
        Scholarship_Applicant__c applicant = new RecommendationStore().findApplicant(link.applicantId);
        if (!requestWasSent(applicant, link.recommenderNumber)) {
            return data;
        }

        Integer n = link.recommenderNumber;
        data.scholarshipName = applicant.Scholarship__r.Name;
        data.applicantName = applicantName(applicant);
        data.recommenderName = (String) applicant.get(field(n, 'Recommender', '_Name__c'));
        data.scholarshipDescriptionHtml = applicant.Scholarship__r.Description__c;
        data.questionHtml = (String) applicant.Scholarship__r.get(field(n, 'Recommender', '_Question__c'));
        data.recommendationHtml = (String) applicant.get(field(n, 'Recommendation', '__c'));
        data.status = applicant.get(field(n, 'Recommendation', '_Received__c')) == null ? STATUS_READY : STATUS_RECEIVED;
        return data;
    }

    /**
     * Counterpart of Save() in the VF controller: stores the recommendation and the time it was received. The
     * recommendation can only be submitted once; a second attempt is refused and changes nothing.
     *
     * @param recId The "recId" from the link: the applicant's Id followed by 1 or 2.
     * @param recommendationHtml The recommendation as rich text.
     * @return Whether it was saved, a status of RECEIVED, READY or INVALID_LINK, and a message when it was not saved.
     */
    @AuraEnabled(cacheable=false)
    public static SaveResult submitRecommendation(String recId, String recommendationHtml) {
        SaveResult result = new SaveResult();

        RecommendationLink link = parseLink(recId);
        RecommendationStore store = new RecommendationStore();
        Scholarship_Applicant__c applicant = link == null ? null : store.findApplicant(link.applicantId);
        if (!requestWasSent(applicant, link == null ? null : link.recommenderNumber)) {
            result.message = 'This recommendation request could not be found.';
            return result;
        }

        Integer n = link.recommenderNumber;
        if (applicant.get(field(n, 'Recommendation', '_Received__c')) != null) {
            result.status = STATUS_RECEIVED;
            result.message = 'A recommendation has already been submitted for this request.';
            return result;
        }

        result.status = STATUS_READY;
        if (isBlankHtml(recommendationHtml)) {
            result.message = 'Please enter your recommendation.';
            return result;
        }
        if (recommendationHtml.length() > MAX_RECOMMENDATION_LENGTH) {
            result.message = 'Your recommendation is too long (maximum ' + MAX_RECOMMENDATION_LENGTH + ' characters).';
            return result;
        }

        try {
            store.saveRecommendation(link.applicantId, n, recommendationHtml);
        } catch (DmlException ex) {
            System.debug('Recommendation not saved: ' + ex.getMessage());
            result.message = 'Your recommendation could not be saved: ' + ex.getDmlMessage(0);
            return result;
        }

        result.success = true;
        result.status = STATUS_RECEIVED;
        return result;
    }

    /**
     * The only code that runs without sharing: a guest user cannot read or update the applicant. Each method
     * works on the single record whose Id came from the link.
     */
    private without sharing class RecommendationStore {

        public Scholarship_Applicant__c findApplicant(Id applicantId) {
            List<Scholarship_Applicant__c> applicants = [
                    SELECT Recommender_Name__c, Recommender2_Name__c, Recommendation__c, Recommendation2__c,
                            Recommendation_Request_Date__c, Recommendation2_Request_Date__c,
                            Recommendation_Received__c, Recommendation2_Received__c,
                            Contact__r.FirstName, Contact__r.LastName,
                            Scholarship__r.Name, Scholarship__r.Description__c,
                            Scholarship__r.Recommender_Question__c, Scholarship__r.Recommender2_Question__c
                    FROM Scholarship_Applicant__c
                    WHERE Id = :applicantId
                    LIMIT 1
            ];
            return applicants.isEmpty() ? null : applicants[0];
        }

        public void saveRecommendation(Id applicantId, Integer recommenderNumber, String recommendationHtml) {
            Scholarship_Applicant__c toUpdate = new Scholarship_Applicant__c(Id = applicantId);
            toUpdate.put(field(recommenderNumber, 'Recommendation', '__c'), recommendationHtml);
            toUpdate.put(field(recommenderNumber, 'Recommendation', '_Received__c'), Datetime.now());
            update toUpdate;
        }
    }

    /**
     * @param recId The "recId" from the link.
     * @return The applicant Id and recommender number it names, or null if it is not a valid link.
     */
    @TestVisible
    private static RecommendationLink parseLink(String recId) {
        String value = String.isBlank(recId) ? null : recId.trim();
        if (value == null || value.length() < 2) {
            return null;
        }

        String numberPart = value.substring(value.length() - 1);
        if (numberPart != '1' && numberPart != '2') {
            return null;
        }

        Id applicantId;
        try {
            applicantId = Id.valueOf(value.substring(0, value.length() - 1));
        } catch (Exception ex) {
            return null;
        }
        // The Id of any other kind of record is not a recommendation link.
        if (applicantId.getSobjectType() != Scholarship_Applicant__c.SObjectType) {
            return null;
        }

        RecommendationLink link = new RecommendationLink();
        link.applicantId = applicantId;
        link.recommenderNumber = Integer.valueOf(numberPart);
        return link;
    }

    /**
     * @param applicant The applicant the link names, or null.
     * @param recommenderNumber 1 or 2.
     * @return True when the applicant exists and the request email for this recommender was sent.
     */
    private static Boolean requestWasSent(Scholarship_Applicant__c applicant, Integer recommenderNumber) {
        return applicant != null && recommenderNumber != null && applicant.get(field(recommenderNumber, 'Recommendation', '_Request_Date__c')) != null;
    }

    /**
     * The first recommender's fields have no number (Recommendation__c); the second's have a 2 (Recommendation2__c).
     *
     * @param recommenderNumber 1 or 2.
     * @param prefix The start of the field name, for example "Recommender" or "Recommendation".
     * @param suffix The end of the field name, for example "_Name__c".
     * @return The full API name, for example "Recommender2_Name__c".
     */
    private static String field(Integer recommenderNumber, String prefix, String suffix) {
        return prefix + (recommenderNumber == 2 ? '2' : '') + suffix;
    }

    private static String applicantName(Scholarship_Applicant__c applicant) {
        List<String> parts = new List<String>();
        if (applicant.Contact__r != null) {
            if (String.isNotBlank(applicant.Contact__r.FirstName)) {
                parts.add(applicant.Contact__r.FirstName);
            }
            if (String.isNotBlank(applicant.Contact__r.LastName)) {
                parts.add(applicant.Contact__r.LastName);
            }
        }
        return String.join(parts, ' ');
    }

    /**
     * True for empty rich text such as "<p><br></p>", so a recommendation with nothing in it is not accepted.
     *
     * @param html The rich text to check.
     * @return True when the rich text has no visible content.
     */
    private static Boolean isBlankHtml(String html) {
        if (String.isBlank(html)) {
            return true;
        }
        if (html.containsIgnoreCase('<img')) {
            return false;
        }
        return String.isBlank(html.stripHtmlTags().replace('&nbsp;', ' ').trim());
    }
}
