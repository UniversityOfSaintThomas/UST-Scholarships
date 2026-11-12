/**
 * Apex controller for the scholarshipAppPage2Lwc component (Page 2 of the scholarship application).
 *
 * LWC counterpart of ScholarshipApplicationPage2Controller, currently covering the application questions
 * (Question_1..4), the essays (Essay_1..2, typed or uploaded) and the recommender requests (Recommender 1..2).
 * Save & Submit validates the whole application, sends any recommender requests still pending, marks the
 * application complete and sends the confirmation email.
 *
 * It never reads ApexPages, cookies or PageReference: the scholarship id (the "sid" URL parameter) is
 * passed in explicitly and the applicant's Contact is always derived on the server from the running user.
 * Only the answer fields, the essay upload fields, the recommender fields, the initials and the completion fields are written, so nothing else on
 * the applicant record can be overwritten.
 *
 * Essay files are Salesforce Files (ContentVersion/ContentDocumentLink) uploaded by lightning-file-upload
 * straight onto the applicant record. Because both essays link to the same record, the server renames each
 * file's title to start with "Essay1_" or "Essay2_" (the VF flow used the same prefix on its Attachment
 * names) so a file can be matched to its essay later.
 */
public with sharing class ScholarshipAppPage2LwcController {

    /**
     * Returned in place of OPEN when the applicant has not confirmed the criteria on Page 1 yet, so the
     * LWC sends them back there instead of letting them skip it.
     */
    public static final String STATUS_CRITERIA_REQUIRED = 'CRITERIA_REQUIRED';

    // Question_N_Answer__c is a 7000 character long text area; Essay_N_Answer__c is a 131072 character rich text area.
    @TestVisible private static final Integer MAX_ANSWER_LENGTH = 7000;
    @TestVisible private static final Integer MAX_ESSAY_LENGTH = 131072;
    // Essay_N_Uploaded_Orig_Filename__c is a 200 character text field.
    @TestVisible private static final Integer MAX_FILENAME_LENGTH = 200;
    private static final Integer QUESTION_COUNT = 4;
    private static final Integer ESSAY_COUNT = 2;
    private static final Integer RECOMMENDER_COUNT = 2;
    // Recommender_Name__c and Recommender2_Name__c are 80 character text fields.
    @TestVisible private static final Integer MAX_RECOMMENDER_NAME_LENGTH = 80;
    // Signature__c (the initials) is a 30 character text field.
    @TestVisible private static final Integer MAX_SIGNATURE_LENGTH = 30;
    // The Scholarship_Status__c value the VF page set when an application was submitted.
    @TestVisible private static final String APPLICANT_STATUS_SUBMITTED = 'Submitted App';

    // The same file types the VF page accepted.
    @TestVisible private static final List<String> ALLOWED_FILE_EXTENSIONS = new List<String>{'pdf', 'doc', 'docx', 'txt', 'rtf'};

    @TestVisible private static final String MSG_CRITERIA_REQUIRED = 'Please confirm the eligibility criteria before continuing.';
    @TestVisible private static final String MSG_FILE_NOT_FOUND = 'The uploaded file could not be found on your application. Please try uploading it again.';

    public class Question {
        @AuraEnabled public Integer questionNumber;
        @AuraEnabled public String promptHtml;
        @AuraEnabled public String answer;
        @AuraEnabled public Integer maxLength = MAX_ANSWER_LENGTH;
    }

    public class Essay {
        @AuraEnabled public Integer essayNumber;
        @AuraEnabled public String promptHtml;
        @AuraEnabled public Boolean allowUpload = false;
        @AuraEnabled public String answerHtml;
        @AuraEnabled public Boolean uploaded = false;
        @AuraEnabled public String uploadedFilename;
    }

    public class Recommender {
        @AuraEnabled public Integer recommenderNumber;
        // True for "Recommender Required" / "Recommender2 Required", false for the optional ones.
        @AuraEnabled public Boolean required = false;
        @AuraEnabled public String descriptionHtml;
        @AuraEnabled public String name;
        @AuraEnabled public String email;
        // When the request email was sent, as text in Central Time, or null if it has not been sent.
        @AuraEnabled public String requestedOn;
    }

    public class PageData {
        @AuraEnabled public String status;
        @AuraEnabled public String scholarshipName;
        // The record lightning-file-upload attaches essay files to.
        @AuraEnabled public Id applicantId;
        // With a leading dot (".pdf") so they can be used directly as the file upload "accept" list.
        @AuraEnabled public List<String> allowedFileExtensions = new List<String>();
        @AuraEnabled public List<Question> questions = new List<Question>();
        @AuraEnabled public List<Essay> essays = new List<Essay>();
        @AuraEnabled public List<Recommender> recommenders = new List<Recommender>();
        // The scholarship's completion statement (HTML), or null when it has none. Initials are only asked for when it is set.
        @AuraEnabled public String completionStatementHtml;
        // The initials the applicant already saved.
        @AuraEnabled public String signature;
    }

    public class SaveResult {
        @AuraEnabled public Boolean success = false;
        @AuraEnabled public String status;
        @AuraEnabled public String message;
        // Only set by attachEssayFile and deleteEssayFile: the essay's file state after the call.
        @AuraEnabled public Boolean uploaded;
        @AuraEnabled public String uploadedFilename;
        // Only set by requestRecommendation: when the request email was sent (Central Time text).
        @AuraEnabled public String requestedOn;
        // Only set by submitApplication when the application is incomplete: the fields to highlight, such as
        // "question:1", "essay:2", "recommender:1:name", "recommender:1:email" and "signature".
        @AuraEnabled public List<String> invalidFields = new List<String>();
        // Only set by submitApplication: true if the application was submitted but the confirmation email was not sent.
        @AuraEnabled public Boolean submitEmailFailed = false;
    }

    /** What happened when one recommender's request email was built and sent. */
    private class SendOutcome {
        // Null when the request was sent, otherwise why it was not.
        public String errorMessage;
        public Datetime sentOn;
    }

    /** The result of checking whether an application is complete enough to submit. */
    @TestVisible
    private class SubmitCheck {
        public List<String> messages = new List<String>();
        public List<String> invalidFields = new List<String>();
    }

    /** The scholarship and the running user's confirmed applicant, once a request has passed the gates. */
    private class RequestContext {
        public Scholarship__c scholarship;
        public Scholarship_Applicant__c applicant;
    }

    /**
     * Everything Page 2 needs to render its questions and essays, plus the access status. The LWC redirects
     * when the status is anything other than OPEN. Not cacheable: depends on the current time and the
     * applicant's record.
     *
     * @param sid The scholarship id from the "sid" URL parameter.
     * @return The scholarship content, the applicant's saved values and the access status.
     */
    @AuraEnabled(cacheable=false)
    public static PageData getPageData(String sid) {
        return buildPageData(sid, ScholarshipSharedUtilities.getActiveContactId(), ScholarshipLwcService.getAccessStatus(sid));
    }

    /**
     * Mirrors SaveFinishLater() in the VF controller for the question answers, the typed essays and the
     * recommenders' names and emails: saves what the applicant entered so far without requiring any answer.
     * The parameters are maps of number to text: "1".."4" for questions, "1".."2" for essays, and keys such as
     * "name1" and "email2" for recommenders. Plain maps are used because a custom Apex class passed from the
     * component arrived with empty fields when the answers were sent that way.
     * Essays are only included for the essays whose text editor the applicant is using, so a typed answer is
     * never overwritten while the applicant is on the upload option. Recommenders whose request was already
     * sent are locked and their values are ignored.
     *
     * @param sid The scholarship id from the "sid" URL parameter.
     * @param answers Question number ("1".."4") mapped to the answer text.
     * @param essayAnswers Essay number ("1".."2") mapped to the essay HTML, only for essays being typed.
     * @param recommenders "name1", "email1", "name2" and "email2" mapped to the recommender's name or email.
     * @param signature The applicant's initials, or null to leave them as they are. Ignored when the scholarship
     *                  has no completion statement.
     * @return Whether the save succeeded, the access status, and a message when it did not.
     */
    @AuraEnabled(cacheable=false)
    public static SaveResult saveAnswers(String sid, Map<String, String> answers, Map<String, String> essayAnswers,
            Map<String, String> recommenders, String signature) {
        return saveAnswersForContact(sid, answers, essayAnswers, recommenders, signature, ScholarshipSharedUtilities.getActiveContactId(), ScholarshipLwcService.getAccessStatus(sid));
    }

    /**
     * Counterpart of SaveComplete() in the VF controller. Saves what the applicant entered (as Save & Finish
     * Later does), then checks that the application is complete, sends any recommender requests still pending,
     * marks the application submitted and sends the confirmation email. The VF page only checked required
     * fields in the browser; this server-side check is the authoritative one.
     * If the application is incomplete, the entered answers stay saved and nothing is submitted. If a pending
     * recommender request cannot be sent, nothing is submitted either, as in the VF page; requests that were
     * sent are not repeated on the next attempt. If only the confirmation email fails, the application is still
     * submitted and submitEmailFailed is true.
     *
     * @param sid The scholarship id from the "sid" URL parameter.
     * @param answers Question number ("1".."4") mapped to the answer text.
     * @param essayAnswers Essay number ("1".."2") mapped to the essay HTML, only for essays being typed.
     * @param recommenders "name1", "email1", "name2" and "email2" mapped to the recommender's name or email.
     * @param signature The applicant's initials.
     * @return Whether the application was submitted, the fields to highlight when it is incomplete, and a message when it was not submitted.
     */
    @AuraEnabled(cacheable=false)
    public static SaveResult submitApplication(String sid, Map<String, String> answers, Map<String, String> essayAnswers,
            Map<String, String> recommenders, String signature) {
        return submitApplicationForContact(sid, answers, essayAnswers, recommenders, signature, ScholarshipSharedUtilities.getActiveContactId(), ScholarshipLwcService.getAccessStatus(sid));
    }

    /**
     * Called by the LWC after lightning-file-upload has stored a file on the applicant record. Only the file's
     * id is accepted; the owner, the link to the applicant, the file type and the filename are all read from
     * Salesforce here. A file that is not acceptable is deleted again so it does not linger on the record.
     *
     * @param sid The scholarship id from the "sid" URL parameter.
     * @param essayNumber The essay the file is for (1 or 2).
     * @param contentDocumentId The id of the file lightning-file-upload stored on the applicant record.
     * @return Whether the file was accepted and the essay's uploaded filename, or a message explaining the rejection.
     */
    @AuraEnabled(cacheable=false)
    public static SaveResult attachEssayFile(String sid, Integer essayNumber, String contentDocumentId) {
        return attachEssayFileForContact(sid, essayNumber, contentDocumentId, ScholarshipSharedUtilities.getActiveContactId(), ScholarshipLwcService.getAccessStatus(sid));
    }

    /**
     * Counterpart of DeleteEssay1/2 in the VF controller ("Delete and re-upload"): removes the essay's file,
     * including an old Attachment from before the move to Files, and resets the uploaded fields.
     *
     * @param sid The scholarship id from the "sid" URL parameter.
     * @param essayNumber The essay whose file is removed (1 or 2).
     * @return Whether the file was removed, or a message explaining why not.
     */
    @AuraEnabled(cacheable=false)
    public static SaveResult deleteEssayFile(String sid, Integer essayNumber) {
        return deleteEssayFileForContact(sid, essayNumber, ScholarshipSharedUtilities.getActiveContactId(), ScholarshipLwcService.getAccessStatus(sid));
    }

    /**
     * Counterpart of the "Request Now" link and SendRecommenderEmail() in the VF controller: saves the
     * recommender's name and email, then sends the request email built from the scholarship's template, and
     * records when it was sent. If the email cannot be built or sent, the name and email stay saved but no
     * send date is recorded, so the applicant can try again. A request that was already sent is never repeated
     * and its name and email can no longer be changed.
     *
     * @param sid The scholarship id from the "sid" URL parameter.
     * @param recommenderNumber Which recommender to request (1 or 2).
     * @param name The recommender's name.
     * @param email The recommender's email address.
     * @return Whether the request was sent, when it was sent, or a message explaining why not.
     */
    @AuraEnabled(cacheable=false)
    public static SaveResult requestRecommendation(String sid, Integer recommenderNumber, String name, String email) {
        return requestRecommendationForContact(sid, recommenderNumber, name, email, ScholarshipSharedUtilities.getActiveContactId(), ScholarshipLwcService.getAccessStatus(sid));
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

        data.applicantId = applicant.Id;
        for (String extension : ALLOWED_FILE_EXTENSIONS) {
            data.allowedFileExtensions.add('.' + extension);
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

        for (Integer n = 1; n <= ESSAY_COUNT; n++) {
            String prompt = (String) scholarship.get('Essay_' + n + '_Text__c');
            if (String.isNotBlank(prompt)) {
                Essay essay = new Essay();
                essay.essayNumber = n;
                essay.promptHtml = prompt;
                essay.allowUpload = (Boolean) scholarship.get('Essay_' + n + '_Allow_Upload__c') == true;
                essay.answerHtml = (String) applicant.get('Essay_' + n + '_Answer__c');
                essay.uploaded = (Boolean) applicant.get('Essay_' + n + '_Uploaded__c') == true;
                essay.uploadedFilename = (String) applicant.get('Essay_' + n + '_Uploaded_Orig_Filename__c');
                data.essays.add(essay);
            }
        }

        for (Integer n = 1; n <= RECOMMENDER_COUNT; n++) {
            if (recommenderConfigured(scholarship, n)) {
                Recommender recommender = new Recommender();
                recommender.recommenderNumber = n;
                recommender.required = recommenderRequired(scholarship, n);
                recommender.descriptionHtml = (String) scholarship.get(recommenderField(n, '_Description__c'));
                recommender.name = (String) applicant.get(recommenderField(n, '_Name__c'));
                recommender.email = (String) applicant.get(recommenderField(n, '_Email__c'));
                recommender.requestedOn = formatRequestedOn((Datetime) applicant.get(recommenderDateField(n)));
                data.recommenders.add(recommender);
            }
        }

        if (String.isNotBlank(scholarship.Completion_Statement__c)) {
            data.completionStatementHtml = scholarship.Completion_Statement__c;
            data.signature = applicant.Signature__c;
        }
        return data;
    }

    @TestVisible
    private static SaveResult saveAnswersForContact(String sid, Map<String, String> answers, Map<String, String> essayAnswers,
            Map<String, String> recommenders, String signature, Id contactId, ScholarshipLwcService.AccessResult access) {
        SaveResult result = new SaveResult();
        RequestContext context = openContext(sid, contactId, access, result);
        if (context == null) {
            return result;
        }
        Scholarship__c scholarship = context.scholarship;

        // Update a record that carries only the answer fields, so no other applicant data is touched.
        Scholarship_Applicant__c toUpdate = new Scholarship_Applicant__c(Id = context.applicant.Id);
        Boolean hasChanges = false;
        Integer recognizedAnswers = 0;
        List<String> errors = new List<String>();

        Map<String, String> submitted = answers == null ? new Map<String, String>() : answers;
        for (String key : sortedKeys(submitted)) {
            Integer n = parseNumber(key);
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

        Map<String, String> submittedEssays = essayAnswers == null ? new Map<String, String>() : essayAnswers;
        for (String key : sortedKeys(submittedEssays)) {
            Integer n = parseNumber(key);
            if (n == null || n < 1 || n > ESSAY_COUNT || String.isBlank((String) scholarship.get('Essay_' + n + '_Text__c'))) {
                continue;
            }
            recognizedAnswers++;
            String essay = submittedEssays.get(key);
            if (essay != null && essay.length() > MAX_ESSAY_LENGTH) {
                errors.add('Essay ' + n + ' is too long (maximum ' + MAX_ESSAY_LENGTH + ' characters).');
                continue;
            }
            toUpdate.put('Essay_' + n + '_Answer__c', isBlankHtml(essay) ? null : essay);
            hasChanges = true;
        }

        // Recommenders' names and emails. A recommender whose request was already sent is locked, as on the VF page.
        Map<String, String> submittedRecommenders = recommenders == null ? new Map<String, String>() : recommenders;
        for (Integer n = 1; n <= RECOMMENDER_COUNT; n++) {
            if (!recommenderConfigured(scholarship, n) || (!submittedRecommenders.containsKey('name' + n) && !submittedRecommenders.containsKey('email' + n))) {
                continue;
            }
            recognizedAnswers++;
            if (context.applicant.get(recommenderDateField(n)) != null) {
                continue;
            }
            String recommenderName = trimToNull(submittedRecommenders.get('name' + n));
            String recommenderEmail = trimToNull(submittedRecommenders.get('email' + n));
            if (recommenderName != null && recommenderName.length() > MAX_RECOMMENDER_NAME_LENGTH) {
                errors.add('The name for recommendation ' + n + ' is too long (maximum ' + MAX_RECOMMENDER_NAME_LENGTH + ' characters).');
                continue;
            }
            if (recommenderEmail != null && !isValidEmail(recommenderEmail)) {
                errors.add('Please enter a valid email address for recommendation ' + n + '.');
                continue;
            }
            toUpdate.put(recommenderField(n, '_Name__c'), recommenderName);
            toUpdate.put(recommenderField(n, '_Email__c'), recommenderEmail);
            hasChanges = true;
        }

        // The initials are only asked for when the scholarship has a completion statement. Null leaves them as they are.
        if (signature != null && String.isNotBlank(scholarship.Completion_Statement__c)) {
            String initials = trimToNull(signature);
            if (initials != null && initials.length() > MAX_SIGNATURE_LENGTH) {
                errors.add('The initials are too long (maximum ' + MAX_SIGNATURE_LENGTH + ' characters).');
            } else {
                toUpdate.put('Signature__c', initials);
                hasChanges = true;
            }
        }

        // Answers were sent but none belong to this scholarship: report it instead of silently saving nothing.
        if ((!submitted.isEmpty() || !submittedEssays.isEmpty() || !submittedRecommenders.isEmpty()) && recognizedAnswers == 0) {
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

    @TestVisible
    private static SaveResult attachEssayFileForContact(String sid, Integer essayNumber, String contentDocumentId, Id contactId,
            ScholarshipLwcService.AccessResult access) {
        SaveResult result = new SaveResult();
        RequestContext context = openContext(sid, contactId, access, result);
        if (context == null) {
            return result;
        }

        Integer n = essayNumber;
        if (!essayExists(context.scholarship, n)) {
            result.message = 'That essay is not part of this application.';
            return result;
        }

        Id documentId = toId(contentDocumentId);
        if (documentId == null) {
            result.message = MSG_FILE_NOT_FOUND;
            return result;
        }

        // The file must be the running user's own and already linked to their applicant record. Nothing about
        // it is taken from the client, so another user's file or another record's file cannot be attached.
        ContentVersion version = ownedLinkedVersion(documentId, context.applicant.Id);
        if (version == null) {
            result.message = MSG_FILE_NOT_FOUND;
            return result;
        }

        // From here on the file is verified to be this user's, so an unacceptable one can safely be removed.
        if ((Boolean) context.scholarship.get('Essay_' + n + '_Allow_Upload__c') != true) {
            discardFile(documentId);
            result.message = 'File upload is not available for this essay.';
            return result;
        }

        String extension = version.FileExtension == null ? '' : version.FileExtension.toLowerCase();
        if (!ALLOWED_FILE_EXTENSIONS.contains(extension)) {
            discardFile(documentId);
            result.message = 'Invalid file type. Please upload a ' + allowedExtensionsText() + ' file.';
            return result;
        }

        if ((Boolean) context.applicant.get('Essay_' + n + '_Uploaded__c') == true) {
            discardFile(documentId);
            result.message = 'A file has already been uploaded for this essay. Delete it before uploading another.';
            return result;
        }

        String filename = originalFilename(version);
        SavePoint savepoint = Database.setSavepoint();
        try {
            update new ContentDocument(Id = documentId, Title = ('Essay' + n + '_' + version.Title).left(255));
            Scholarship_Applicant__c toUpdate = new Scholarship_Applicant__c(Id = context.applicant.Id);
            toUpdate.put('Essay_' + n + '_Uploaded__c', true);
            toUpdate.put('Essay_' + n + '_Uploaded_Orig_Filename__c', filename);
            update toUpdate;
        } catch (DmlException ex) {
            Database.rollback(savepoint);
            discardFile(documentId);
            result.message = 'Error uploading essay ' + n + '. ' + ex.getDmlMessage(0);
            return result;
        }

        result.success = true;
        result.uploaded = true;
        result.uploadedFilename = filename;
        return result;
    }

    @TestVisible
    private static SaveResult deleteEssayFileForContact(String sid, Integer essayNumber, Id contactId,
            ScholarshipLwcService.AccessResult access) {
        SaveResult result = new SaveResult();
        RequestContext context = openContext(sid, contactId, access, result);
        if (context == null) {
            return result;
        }

        Integer n = essayNumber;
        if (!essayExists(context.scholarship, n)) {
            result.message = 'That essay is not part of this application.';
            return result;
        }

        Id applicantId = context.applicant.Id;
        Id userId = UserInfo.getUserId();

        // Files for this essay are the ones this controller titled "Essay<n>_...". "\_" is a literal underscore in LIKE.
        String filePattern = 'Essay' + n + '\\_%';
        List<Id> ownFileIds = new List<Id>();
        List<ContentDocumentLink> otherLinks = new List<ContentDocumentLink>();
        for (ContentDocumentLink link : [
                SELECT Id, ContentDocumentId, ContentDocument.OwnerId
                FROM ContentDocumentLink
                WHERE LinkedEntityId = :applicantId
                AND ContentDocument.Title LIKE :filePattern
        ]) {
            if (link.ContentDocument.OwnerId == userId) {
                ownFileIds.add(link.ContentDocumentId);
            } else {
                otherLinks.add(link);
            }
        }

        // Applicants who uploaded through the VF page have an Attachment instead of a File.
        String attachmentPattern = 'Essay' + n + '.%';
        List<Attachment> legacyAttachments = [
                SELECT Id
                FROM Attachment
                WHERE ParentId = :applicantId
                AND Name LIKE :attachmentPattern
        ];

        SavePoint savepoint = Database.setSavepoint();
        try {
            if (!ownFileIds.isEmpty()) {
                delete [SELECT Id FROM ContentDocument WHERE Id IN :ownFileIds];
            }
            // Files the applicant does not own cannot be deleted, so only their link to the application is removed.
            if (!otherLinks.isEmpty()) {
                delete otherLinks;
            }
            if (!legacyAttachments.isEmpty()) {
                delete legacyAttachments;
            }
            Scholarship_Applicant__c toUpdate = new Scholarship_Applicant__c(Id = applicantId);
            toUpdate.put('Essay_' + n + '_Uploaded__c', false);
            toUpdate.put('Essay_' + n + '_Uploaded_Orig_Filename__c', null);
            update toUpdate;
        } catch (DmlException ex) {
            Database.rollback(savepoint);
            result.message = 'The essay file could not be deleted. ' + ex.getDmlMessage(0);
            return result;
        }

        result.success = true;
        result.uploaded = false;
        return result;
    }

    @TestVisible
    private static SaveResult requestRecommendationForContact(String sid, Integer recommenderNumber, String name, String email,
            Id contactId, ScholarshipLwcService.AccessResult access) {
        SaveResult result = new SaveResult();
        RequestContext context = openContext(sid, contactId, access, result);
        if (context == null) {
            return result;
        }

        Integer n = recommenderNumber;
        if (!recommenderConfigured(context.scholarship, n)) {
            result.message = 'That recommendation is not part of this application.';
            return result;
        }

        Datetime alreadyRequested = (Datetime) context.applicant.get(recommenderDateField(n));
        if (alreadyRequested != null) {
            result.requestedOn = formatRequestedOn(alreadyRequested);
            result.message = 'A request has already been sent for this recommendation.';
            return result;
        }

        String recommenderName = trimToNull(name);
        String recommenderEmail = trimToNull(email);
        if (recommenderName == null) {
            result.message = 'Please enter the recommender\'s name.';
            return result;
        }
        if (recommenderName.length() > MAX_RECOMMENDER_NAME_LENGTH) {
            result.message = 'The recommender\'s name is too long (maximum ' + MAX_RECOMMENDER_NAME_LENGTH + ' characters).';
            return result;
        }
        if (!isValidEmail(recommenderEmail)) {
            result.message = 'Please enter a valid email address for the recommender.';
            return result;
        }

        // The name and email are saved first and stay saved if the email cannot be sent, as in the VF page.
        Scholarship_Applicant__c toUpdate = new Scholarship_Applicant__c(Id = context.applicant.Id);
        toUpdate.put(recommenderField(n, '_Name__c'), recommenderName);
        toUpdate.put(recommenderField(n, '_Email__c'), recommenderEmail);
        try {
            update toUpdate;
        } catch (DmlException ex) {
            result.message = 'Recommender information not saved. No Request Sent. ' + ex.getDmlMessage(0);
            return result;
        }

        SendOutcome outcome = sendRecommenderRequest(context, n, recommenderEmail);
        if (outcome.errorMessage != null) {
            result.message = outcome.errorMessage;
            return result;
        }

        result.success = true;
        result.requestedOn = formatRequestedOn(outcome.sentOn);
        return result;
    }

    @TestVisible
    private static SaveResult submitApplicationForContact(String sid, Map<String, String> answers, Map<String, String> essayAnswers,
            Map<String, String> recommenders, String signature, Id contactId, ScholarshipLwcService.AccessResult access) {
        // Save first, exactly as Save & Finish Later does, so the applicant's work is kept even if the application is incomplete.
        SaveResult result = saveAnswersForContact(sid, answers, essayAnswers, recommenders, signature, contactId, access);
        if (!result.success) {
            return result;
        }
        result.success = false;

        // Read the application back, so the check is made on what is actually stored.
        RequestContext context = openContext(sid, contactId, access, result);
        if (context == null) {
            return result;
        }

        SubmitCheck check = validateForSubmit(context.scholarship, context.applicant);
        if (!check.messages.isEmpty()) {
            result.message = String.join(check.messages, ' ');
            result.invalidFields = check.invalidFields;
            return result;
        }

        // Send the recommender requests that are still pending, as the VF page did. If one fails, nothing is submitted;
        // requests that were already sent are not sent again on the next attempt.
        for (Integer n = 1; n <= RECOMMENDER_COUNT; n++) {
            String recommenderName = (String) context.applicant.get(recommenderField(n, '_Name__c'));
            String recommenderEmail = (String) context.applicant.get(recommenderField(n, '_Email__c'));
            if (!recommenderConfigured(context.scholarship, n) || context.applicant.get(recommenderDateField(n)) != null
                    || String.isBlank(recommenderName) || String.isBlank(recommenderEmail)) {
                continue;
            }
            SendOutcome outcome = sendRecommenderRequest(context, n, recommenderEmail);
            if (outcome.errorMessage != null) {
                result.message = outcome.errorMessage + ' Your application has not been submitted.';
                return result;
            }
        }

        Scholarship_Applicant__c completion = new Scholarship_Applicant__c(Id = context.applicant.Id);
        completion.Scholarship_Complete__c = true;
        completion.Scholarship_Status__c = APPLICANT_STATUS_SUBMITTED;
        completion.Scholarship_Date_Submitted__c = Datetime.now();
        try {
            update completion;
        } catch (DmlException ex) {
            System.debug('Upsert Applicant exception: ' + ex.getMessage());
            result.message = 'Your application could not be submitted: ' + ex.getDmlMessage(0);
            return result;
        }

        result.success = true;
        result.submitEmailFailed = !sendSubmitEmail(context);
        return result;
    }

    /**
     * The completeness rules for Save & Submit. They follow validateApplication() in the VF page's script, which
     * only ran in the browser: every question is required, an essay that allows uploads needs a file or text,
     * a "Required" recommender needs a name and a valid email, and the initials are required when the
     * scholarship has a completion statement. Like the VF page, an essay that can only be typed may be left empty.
     *
     * @param scholarship The scholarship being applied for.
     * @param applicant The applicant as stored.
     * @return The messages and the fields to highlight; both are empty when the application is complete.
     */
    @TestVisible
    private static SubmitCheck validateForSubmit(Scholarship__c scholarship, Scholarship_Applicant__c applicant) {
        SubmitCheck check = new SubmitCheck();

        for (Integer n = 1; n <= QUESTION_COUNT; n++) {
            if (String.isNotBlank((String) scholarship.get('Question_' + n + '_Text__c')) && String.isBlank((String) applicant.get('Question_' + n + '_Answer__c'))) {
                check.invalidFields.add('question:' + n);
                check.messages.add('Please answer question ' + n + '.');
            }
        }

        for (Integer n = 1; n <= ESSAY_COUNT; n++) {
            Boolean essayRequired = String.isNotBlank((String) scholarship.get('Essay_' + n + '_Text__c'))
                    && (Boolean) scholarship.get('Essay_' + n + '_Allow_Upload__c') == true;
            Boolean essayAnswered = (Boolean) applicant.get('Essay_' + n + '_Uploaded__c') == true
                    || !isBlankHtml((String) applicant.get('Essay_' + n + '_Answer__c'));
            if (essayRequired && !essayAnswered) {
                check.invalidFields.add('essay:' + n);
                check.messages.add('Essay ' + n + ' needs an uploaded file or a typed answer.');
            }
        }

        for (Integer n = 1; n <= RECOMMENDER_COUNT; n++) {
            if (!recommenderConfigured(scholarship, n) || !recommenderRequired(scholarship, n)) {
                continue;
            }
            Boolean missingName = String.isBlank((String) applicant.get(recommenderField(n, '_Name__c')));
            Boolean badEmail = !isValidEmail((String) applicant.get(recommenderField(n, '_Email__c')));
            if (missingName) {
                check.invalidFields.add('recommender:' + n + ':name');
            }
            if (badEmail) {
                check.invalidFields.add('recommender:' + n + ':email');
            }
            if (missingName || badEmail) {
                check.messages.add('Recommendation ' + n + ' needs the recommender\'s name and a valid email address.');
            }
        }

        if (String.isNotBlank(scholarship.Completion_Statement__c) && String.isBlank(applicant.Signature__c)) {
            check.invalidFields.add('signature');
            check.messages.add('Please enter your initials to agree to the statement.');
        }
        return check;
    }

    /**
     * Builds and sends one recommender's request email and records when it was sent. The recommender's name and
     * email must already be saved on the applicant. Used by "Request Now" and by Save & Submit.
     *
     * @param context The scholarship and the applicant.
     * @param recommenderNumber 1 or 2.
     * @param recommenderEmail The address to send the request to.
     * @return No error message and the send time when it was sent, otherwise the reason it was not sent.
     */
    private static SendOutcome sendRecommenderRequest(RequestContext context, Integer recommenderNumber, String recommenderEmail) {
        SendOutcome outcome = new SendOutcome();
        Integer n = recommenderNumber;

        String templateId = (String) context.scholarship.get(recommenderField(n, '_Email_Template_Id__c'));
        String fromAddressId = context.scholarship.Org_Wide_Email_Id__c;
        if (String.isBlank(templateId)) {
            outcome.errorMessage = 'Recommendation saved. No request email sent. Recommender ' + n + ' Email Template Not Set';
            return outcome;
        }
        if (String.isBlank(fromAddressId)) {
            outcome.errorMessage = 'Recommendation saved. No request email sent. Org Wide Email Not Set';
            return outcome;
        }

        ScholarshipSharedUtilities.emailUtilities emailBuilder = new ScholarshipSharedUtilities.emailUtilities();
        List<Messaging.SingleEmailMessage> emailsToSend = new List<Messaging.SingleEmailMessage>();
        try {
            emailsToSend.add(emailBuilder.createEmail(templateId, fromAddressId, context.applicant.Id, context.applicant.Contact__c, recommenderEmail));
        } catch (Exception ex) {
            System.debug('Recommender ' + n + ' Email Template exception: ' + ex.getMessage());
            outcome.errorMessage = 'Recommender ' + n + ' Email Template exception: ' + ex.getMessage();
            return outcome;
        }
        try {
            emailBuilder.sendCreatedEmails(emailsToSend);
        } catch (Exception ex) {
            System.debug('Recommendation saved. No request email sent: ' + ex.getMessage());
            outcome.errorMessage = 'Recommendation saved. No request email sent.';
            return outcome;
        }

        Datetime sentOn = Datetime.now();
        Scholarship_Applicant__c dateUpdate = new Scholarship_Applicant__c(Id = context.applicant.Id);
        dateUpdate.put(recommenderDateField(n), sentOn);
        try {
            update dateUpdate;
        } catch (DmlException ex) {
            System.debug('Request email sent but recommendation request date not saved: ' + ex.getMessage());
            outcome.errorMessage = 'Request email sent but recommendation request date not saved';
            return outcome;
        }

        outcome.sentOn = sentOn;
        return outcome;
    }

    /**
     * Sends the "application submitted" confirmation to the applicant. The application is already submitted at
     * this point, so a failure only produces a warning for the applicant.
     *
     * @param context The scholarship and the applicant.
     * @return True if the email was sent, false if the template, the sender or the address is missing or it could not be sent.
     */
    private static Boolean sendSubmitEmail(RequestContext context) {
        String templateId = context.scholarship.Submit_Scholarship_Email_Template_Id__c;
        String fromAddressId = context.scholarship.Org_Wide_Email_Id__c;
        String toAddress = context.applicant.Contact__r == null ? null : context.applicant.Contact__r.Email;
        if (String.isBlank(templateId) || String.isBlank(fromAddressId) || String.isBlank(toAddress)) {
            System.debug('Send Submit Email exception: no Org_Wide_Email_Id__c, Submit_Scholarship_Email_Template_Id__c or applicant email');
            return false;
        }
        try {
            ScholarshipSharedUtilities.emailUtilities emailBuilder = new ScholarshipSharedUtilities.emailUtilities();
            emailBuilder.sendCreatedEmails(new List<Messaging.SingleEmailMessage>{
                    emailBuilder.createEmail(templateId, fromAddressId, context.applicant.Id, context.applicant.Contact__c, toAddress)
            });
            return true;
        } catch (Exception ex) {
            System.debug('Send Submit Email exception: ' + ex.getMessage());
            return false;
        }
    }

    /**
     * @param scholarship The scholarship being applied for.
     * @param recommenderNumber 1 or 2.
     * @return True when the scholarship's option for this recommender is "Recommender Required" / "Recommender2 Required".
     */
    private static Boolean recommenderRequired(Scholarship__c scholarship, Integer recommenderNumber) {
        return (String) scholarship.get(recommenderField(recommenderNumber, '_Option__c')) == 'Recommender' + recommenderSuffix(recommenderNumber) + ' Required';
    }

    /**
     * The gates every write goes through, as in the VF sanityCheck: the scholarship must exist and be open for
     * this user, and the applicant must already exist with the criteria confirmed. When a request is refused,
     * result.status and result.message explain why and null is returned.
     *
     * @param sid The scholarship id from the "sid" URL parameter.
     * @param contactId The running user's Contact id, or null if the user has none.
     * @param access The access status for this scholarship and user.
     * @param result Filled in with the status and a message when the request is refused.
     * @return The scholarship and the confirmed applicant, or null when the request is refused.
     */
    private static RequestContext openContext(String sid, Id contactId, ScholarshipLwcService.AccessResult access, SaveResult result) {
        Scholarship__c scholarship = ScholarshipLwcService.getScholarshipInfo(sid);
        if (scholarship == null) {
            result.status = ScholarshipLwcService.STATUS_NOT_FOUND;
            result.message = 'Scholarship not found.';
            return null;
        }

        result.status = access.status;
        if (access.status != ScholarshipLwcService.STATUS_OPEN) {
            result.message = 'This scholarship is not currently available for editing.';
            return null;
        }

        Scholarship_Applicant__c applicant = existingConfirmedApplicant(scholarship, contactId);
        if (applicant == null) {
            result.status = STATUS_CRITERIA_REQUIRED;
            result.message = MSG_CRITERIA_REQUIRED;
            return null;
        }

        RequestContext context = new RequestContext();
        context.scholarship = scholarship;
        context.applicant = applicant;
        return context;
    }

    /**
     * The running user's applicant for this scholarship, only if it already exists and the criteria were
     * confirmed on Page 1. Returns null otherwise (including when the user has no Contact).
     *
     * @param scholarship The scholarship being applied for.
     * @param contactId The running user's Contact id, or null if the user has none.
     * @return The confirmed applicant, or null.
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

    private static Boolean essayExists(Scholarship__c scholarship, Integer essayNumber) {
        return essayNumber != null && essayNumber >= 1 && essayNumber <= ESSAY_COUNT
                && String.isNotBlank((String) scholarship.get('Essay_' + essayNumber + '_Text__c'));
    }

    /**
     * The latest version of a file, only if it is owned by the running user and linked to the given record.
     *
     * @param documentId The ContentDocument id of the file.
     * @param linkedEntityId The record the file must be linked to.
     * @return The latest version of the file, or null if it is not the user's or not linked to the record.
     */
    private static ContentVersion ownedLinkedVersion(Id documentId, Id linkedEntityId) {
        List<ContentDocumentLink> links = [
                SELECT Id
                FROM ContentDocumentLink
                WHERE LinkedEntityId = :linkedEntityId
                AND ContentDocumentId = :documentId
        ];
        if (links.isEmpty()) {
            return null;
        }
        List<ContentVersion> versions = [
                SELECT Id, Title, PathOnClient, FileExtension, ContentDocument.OwnerId
                FROM ContentVersion
                WHERE ContentDocumentId = :documentId
                AND IsLatest = TRUE
        ];
        if (versions.isEmpty() || versions[0].ContentDocument.OwnerId != UserInfo.getUserId()) {
            return null;
        }
        return versions[0];
    }

    private static void discardFile(Id documentId) {
        try {
            delete [SELECT Id FROM ContentDocument WHERE Id = :documentId AND OwnerId = :UserInfo.getUserId()];
        } catch (DmlException ex) {
            System.debug('Could not remove rejected essay file: ' + ex.getMessage());
        }
    }

    /**
     * The name the applicant's file had on their computer, shortened to fit Essay_N_Uploaded_Orig_Filename__c.
     *
     * @param version The uploaded file's latest version.
     * @return The filename, without any folder path, at most 200 characters long.
     */
    private static String originalFilename(ContentVersion version) {
        String name = String.isNotBlank(version.PathOnClient)
                ? version.PathOnClient
                : version.Title + (String.isBlank(version.FileExtension) ? '' : '.' + version.FileExtension);
        if (name.contains('/')) {
            name = name.substringAfterLast('/');
        }
        if (name.contains('\\')) {
            name = name.substringAfterLast('\\');
        }
        return name.left(MAX_FILENAME_LENGTH);
    }

    /**
     * For example ".pdf, .doc, .docx, .txt, or .rtf".
     *
     * @return The allowed file extensions as readable text.
     */
    private static String allowedExtensionsText() {
        List<String> dotted = new List<String>();
        for (String extension : ALLOWED_FILE_EXTENSIONS) {
            dotted.add('.' + extension);
        }
        String last = dotted.remove(dotted.size() - 1);
        return String.join(dotted, ', ') + ', or ' + last;
    }

    /**
     * True for empty rich text such as "<p><br></p>", so an essay the applicant cleared is stored as blank.
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

    private static List<String> sortedKeys(Map<String, String> values) {
        List<String> keys = new List<String>(values.keySet());
        keys.sort();
        return keys;
    }

    private static Integer parseNumber(String key) {
        return String.isNotBlank(key) && key.trim().isNumeric() ? Integer.valueOf(key.trim()) : null;
    }

    private static Id toId(String value) {
        if (String.isBlank(value)) {
            return null;
        }
        try {
            return Id.valueOf(value.trim());
        } catch (Exception ex) {
            return null;
        }
    }

    /**
     * The first recommender's fields have no number (Recommender_Name__c); the second's have a 2 (Recommender2_Name__c).
     *
     * @param recommenderNumber 1 or 2.
     * @return An empty string for recommender 1 and "2" for recommender 2.
     */
    private static String recommenderSuffix(Integer recommenderNumber) {
        return recommenderNumber == 2 ? '2' : '';
    }

    /**
     * @param recommenderNumber 1 or 2.
     * @param part The end of the field name, for example "_Name__c" or "_Option__c".
     * @return The full API name, for example "Recommender2_Name__c".
     */
    private static String recommenderField(Integer recommenderNumber, String part) {
        return 'Recommender' + recommenderSuffix(recommenderNumber) + part;
    }

    /**
     * @param recommenderNumber 1 or 2.
     * @return The API name of the field holding when the request was sent.
     */
    private static String recommenderDateField(Integer recommenderNumber) {
        return 'Recommendation' + recommenderSuffix(recommenderNumber) + '_Request_Date__c';
    }

    /**
     * Same rule as the VF page: a recommender is used unless the scholarship's option for it is empty or
     * starts with "No" ("No Recommender", "No Recommender 2").
     *
     * @param scholarship The scholarship being applied for.
     * @param recommenderNumber 1 or 2.
     * @return True when the scholarship asks for this recommender.
     */
    private static Boolean recommenderConfigured(Scholarship__c scholarship, Integer recommenderNumber) {
        if (recommenderNumber == null || recommenderNumber < 1 || recommenderNumber > RECOMMENDER_COUNT) {
            return false;
        }
        String option = (String) scholarship.get(recommenderField(recommenderNumber, '_Option__c'));
        return String.isNotBlank(option) && !option.startsWith('No');
    }

    /**
     * Same pattern the VF page showed: "May 3, 2026 02:15 PM", in Central Time.
     *
     * @param requestedOn When the request email was sent.
     * @return The date as text, or null when it has not been sent.
     */
    private static String formatRequestedOn(Datetime requestedOn) {
        return requestedOn == null ? null : requestedOn.format('MMMM d, yyyy hh:mm aaa', 'America/Chicago');
    }

    /**
     * A basic shape check (one @, no spaces, a dot in the domain). Salesforce's own Email field validation
     * is stricter and still applies when the value is saved.
     *
     * @param email The address to check.
     * @return True when the address looks like an email address.
     */
    @TestVisible
    private static Boolean isValidEmail(String email) {
        return String.isNotBlank(email) && Pattern.matches('^[^@\\s]+@[^@\\s]+\\.[^@\\s.]{2,}$', email.trim());
    }

    private static String trimToNull(String value) {
        return String.isBlank(value) ? null : value.trim();
    }
}
