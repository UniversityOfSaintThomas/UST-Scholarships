/**
 * Apex controller for the scholarshipAppPage2Lwc component (Page 2 of the scholarship application).
 *
 * LWC counterpart of ScholarshipApplicationPage2Controller, currently limited to the application
 * questions (Question_1..4). Essays, recommenders and final submit are added in later tasks.
 *
 * It never reads ApexPages, cookies or PageReference: the scholarship id (the "sid" URL parameter) is
 * passed in explicitly and the applicant's Contact is always derived on the server from the running user.
 * Only the question answers are written, so nothing else on the applicant record can be overwritten.
 */
public with sharing class ScholarshipAppPage2LwcController {

    /**
     * Returned in place of OPEN when the applicant has not confirmed the criteria on Page 1 yet, so the
     * LWC sends them back there instead of letting them skip it.
     */
    public static final String STATUS_CRITERIA_REQUIRED = 'CRITERIA_REQUIRED';

    // Question_N_Answer__c is a 7000 character long text area.
    @TestVisible private static final Integer MAX_ANSWER_LENGTH = 7000;
    private static final Integer QUESTION_COUNT = 4;

    public class Question {
        @AuraEnabled public Integer questionNumber;
        @AuraEnabled public String promptHtml;
        @AuraEnabled public String answer;
        @AuraEnabled public Integer maxLength = MAX_ANSWER_LENGTH;
    }

    public class PageData {
        @AuraEnabled public String status;
        @AuraEnabled public String scholarshipName;
        @AuraEnabled public List<Question> questions = new List<Question>();
    }

    public class SaveResult {
        @AuraEnabled public Boolean success = false;
        @AuraEnabled public String status;
        @AuraEnabled public String message;
    }

    /**
     * Everything Page 2 needs to render its questions, plus the access status. The LWC redirects when the
     * status is anything other than OPEN. Not cacheable: depends on the current time and the applicant's record.
     */
    @AuraEnabled(Cacheable=false)
    public static PageData getPageData(String sid) {
        return buildPageData(sid, ScholarshipSharedUtilities.getActiveContactId(), ScholarshipLwcService.getAccessStatus(sid));
    }

    /**
     * Mirrors SaveFinishLater() in the VF controller for the question answers: saves what the applicant
     * entered so far without requiring any answer. Only the answer text per question number is accepted,
     * as a map of question number ("1".."4") to answer text. A plain map is used because the platform does
     * not reliably populate custom Apex classes passed as parameters from a Lightning Web Component.
     */
    @AuraEnabled(Cacheable=false)
    public static SaveResult saveAnswers(String sid, Map<String, String> answers) {
        return saveAnswersForContact(sid, answers, ScholarshipSharedUtilities.getActiveContactId(), ScholarshipLwcService.getAccessStatus(sid));
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

        // Nothing else is needed when the LWC is going to redirect.
        if (access.status != ScholarshipLwcService.STATUS_OPEN) {
            return data;
        }

        Scholarship_Applicant__c applicant = existingConfirmedApplicant(scholarship, contactId);
        if (applicant == null) {
            data.status = STATUS_CRITERIA_REQUIRED;
            return data;
        }

        for (Integer n = 1; n <= QUESTION_COUNT; n++) {
            String prompt = (String) scholarship.get('Question_' + n + '_Text__c');
            if (String.isNotBlank(prompt)) {
                Question question = new Question();
                question.questionNumber = n;
                question.promptHtml = prompt;
                question.answer = (String) applicant.get('Question_' + n + '_Answer__c');
                data.questions.add(question);
            }
        }
        return data;
    }

    @TestVisible
    private static SaveResult saveAnswersForContact(String sid, Map<String, String> answers, Id contactId,
            ScholarshipLwcService.AccessResult access) {
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

        Scholarship_Applicant__c applicant = existingConfirmedApplicant(scholarship, contactId);
        if (applicant == null) {
            result.status = STATUS_CRITERIA_REQUIRED;
            result.message = 'Please confirm the eligibility criteria before answering the application questions.';
            return result;
        }

        // Update a record that carries only the answer fields, so no other applicant data is touched.
        Scholarship_Applicant__c toUpdate = new Scholarship_Applicant__c(Id = applicant.Id);
        Boolean hasChanges = false;
        Integer recognizedAnswers = 0;
        List<String> errors = new List<String>();

        Map<String, String> submitted = answers == null ? new Map<String, String>() : answers;
        List<String> keys = new List<String>(submitted.keySet());
        keys.sort();

        for (String key : keys) {
            Integer n = String.isNotBlank(key) && key.trim().isNumeric() ? Integer.valueOf(key.trim()) : null;
            // Ignore anything that is not one of this scholarship's questions.
            if (n == null || n < 1 || n > QUESTION_COUNT || String.isBlank((String) scholarship.get('Question_' + n + '_Text__c'))) {
                continue;
            }
            recognizedAnswers++;
            String answer = submitted.get(key);
            if (answer != null && answer.length() > MAX_ANSWER_LENGTH) {
                errors.add('The answer to question ' + n + ' is too long (maximum ' + MAX_ANSWER_LENGTH + ' characters).');
                continue;
            }
            toUpdate.put('Question_' + n + '_Answer__c', String.isBlank(answer) ? null : answer);
            hasChanges = true;
        }

        // Answers were sent but none belong to this scholarship: report it instead of silently saving nothing.
        if (!submitted.isEmpty() && recognizedAnswers == 0) {
            result.message = 'Your answers could not be saved. Please refresh the page and try again.';
            return result;
        }

        if (!errors.isEmpty()) {
            result.message = String.join(errors, ' ');
            return result;
        }

        if (hasChanges) {
            try {
                update toUpdate;
            } catch (DmlException ex) {
                result.message = 'Scholarship not saved: ' + ex.getDmlMessage(0);
                return result;
            }
        }

        result.success = true;
        return result;
    }

    /**
     * The running user's applicant for this scholarship, only if it already exists and the criteria were
     * confirmed on Page 1. Returns null otherwise (including when the user has no Contact).
     */
    private static Scholarship_Applicant__c existingConfirmedApplicant(Scholarship__c scholarship, Id contactId) {
        if (contactId == null) {
            return null;
        }
        Scholarship_Applicant__c applicant = ScholarshipSharedUtilities.getApplicantInfo(scholarship.Id, contactId);
        if (applicant == null || applicant.Id == null || applicant.Confirmed_Criteria__c != true) {
            return null;
        }
        return applicant;
    }
}
