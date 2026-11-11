/**
 * Apex controller for the scholarshipAppPage2Lwc component (Page 2 of the scholarship application).
 *
 * LWC counterpart of ScholarshipApplicationPage2Controller, currently covering the application questions
 * (Question_1..4) and the essays (Essay_1..2, typed or uploaded). Recommenders and final submit are added
 * in later tasks.
 *
 * It never reads ApexPages, cookies or PageReference: the scholarship id (the "sid" URL parameter) is
 * passed in explicitly and the applicant's Contact is always derived on the server from the running user.
 * Only the answer fields and the essay upload fields are written, so nothing else on the applicant record
 * can be overwritten.
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

    public class PageData {
        @AuraEnabled public String status;
        @AuraEnabled public String scholarshipName;
        // The record lightning-file-upload attaches essay files to.
        @AuraEnabled public Id applicantId;
        // With a leading dot (".pdf") so they can be used directly as the file upload "accept" list.
        @AuraEnabled public List<String> allowedFileExtensions = new List<String>();
        @AuraEnabled public List<Question> questions = new List<Question>();
        @AuraEnabled public List<Essay> essays = new List<Essay>();
    }

    public class SaveResult {
        @AuraEnabled public Boolean success = false;
        @AuraEnabled public String status;
        @AuraEnabled public String message;
        // Only set by attachEssayFile and deleteEssayFile: the essay's file state after the call.
        @AuraEnabled public Boolean uploaded;
        @AuraEnabled public String uploadedFilename;
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
     */
    @AuraEnabled(Cacheable=false)
    public static PageData getPageData(String sid) {
        return buildPageData(sid, ScholarshipSharedUtilities.getActiveContactId(), ScholarshipLwcService.getAccessStatus(sid));
    }

    /**
     * Mirrors SaveFinishLater() in the VF controller for the question answers and the typed essays: saves
     * what the applicant entered so far without requiring any answer. Both parameters are maps of number
     * ("1".."4" for questions, "1".."2" for essays) to the answer text. Plain maps are used because a custom
     * Apex class passed from the component arrived with empty fields when the answers were sent that way.
     * Essays are only included for the essays whose text editor the applicant is using, so a typed answer is
     * never overwritten while the applicant is on the upload option.
     */
    @AuraEnabled(Cacheable=false)
    public static SaveResult saveAnswers(String sid, Map<String, String> answers, Map<String, String> essayAnswers) {
        return saveAnswersForContact(sid, answers, essayAnswers, ScholarshipSharedUtilities.getActiveContactId(), ScholarshipLwcService.getAccessStatus(sid));
    }

    /**
     * Called by the LWC after lightning-file-upload has stored a file on the applicant record. Only the file's
     * id is accepted; the owner, the link to the applicant, the file type and the filename are all read from
     * Salesforce here. A file that is not acceptable is deleted again so it does not linger on the record.
     */
    @AuraEnabled(Cacheable=false)
    public static SaveResult attachEssayFile(String sid, Integer essayNumber, String contentDocumentId) {
        return attachEssayFileForContact(sid, essayNumber, contentDocumentId, ScholarshipSharedUtilities.getActiveContactId(), ScholarshipLwcService.getAccessStatus(sid));
    }

    /**
     * Counterpart of DeleteEssay1/2 in the VF controller ("Delete and re-upload"): removes the essay's file,
     * including an old Attachment from before the move to Files, and resets the uploaded fields.
     */
    @AuraEnabled(Cacheable=false)
    public static SaveResult deleteEssayFile(String sid, Integer essayNumber) {
        return deleteEssayFileForContact(sid, essayNumber, ScholarshipSharedUtilities.getActiveContactId(), ScholarshipLwcService.getAccessStatus(sid));
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
        return data;
    }

    @TestVisible
    private static SaveResult saveAnswersForContact(String sid, Map<String, String> answers, Map<String, String> essayAnswers,
            Id contactId, ScholarshipLwcService.AccessResult access) {
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

        // Answers were sent but none belong to this scholarship: report it instead of silently saving nothing.
        if ((!submitted.isEmpty() || !submittedEssays.isEmpty()) && recognizedAnswers == 0) {
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
        Savepoint savepoint = Database.setSavepoint();
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

        Savepoint savepoint = Database.setSavepoint();
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

    /**
     * The gates every write goes through, as in the VF sanityCheck: the scholarship must exist and be open for
     * this user, and the applicant must already exist with the criteria confirmed. When a request is refused,
     * result.status and result.message explain why and null is returned.
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
                AND IsLatest = true
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

    /** For example ".pdf, .doc, .docx, .txt, or .rtf". */
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
}
