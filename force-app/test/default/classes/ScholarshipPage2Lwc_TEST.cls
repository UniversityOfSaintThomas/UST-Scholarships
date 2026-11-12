@IsTest
private class ScholarshipPage2Lwc_TEST {

    private static final String NAME_QUESTIONS = 'P2 Lwc Questions';
    private static final String NAME_NO_QUESTIONS = 'P2 Lwc No Questions';
    private static final String NAME_CLOSED = 'P2 Lwc Closed';
    private static final String NAME_ESSAYS = 'P2 Lwc Essays';
    private static final String NAME_ESSAY_TEXT_ONLY = 'P2 Lwc Essay Text Only';
    private static final String NAME_RECOMMENDERS = 'P2 Lwc Recommenders';
    private static final String NAME_SECOND_RECOMMENDER_ONLY = 'P2 Lwc Second Recommender Only';
    private static final String NAME_STATEMENT = 'P2 Lwc Completion Statement';
    private static final String NAME_EVERYTHING = 'P2 Lwc Everything';

    @TestSetup
    static void setup() {
        insert new List<Scholarship__c>{
                // Questions 1 and 3 are configured; 2 and 4 are not.
                new Scholarship__c(Name = NAME_QUESTIONS, Open_Date__c = Date.today().addDays(-3), Close_Date__c = Date.today().addDays(3),
                        Question_1_Text__c = '<p>Why do you deserve it?</p>', Question_3_Text__c = '<p>Tell us more.</p>'),
                new Scholarship__c(Name = NAME_NO_QUESTIONS, Open_Date__c = Date.today().addDays(-3), Close_Date__c = Date.today().addDays(3)),
                new Scholarship__c(Name = NAME_CLOSED, Open_Date__c = Date.today().addDays(-3), Close_Date__c = Date.today().addDays(-2),
                        Question_1_Text__c = '<p>Closed question</p>'),
                // Both essays can be typed or uploaded.
                new Scholarship__c(Name = NAME_ESSAYS, Open_Date__c = Date.today().addDays(-3), Close_Date__c = Date.today().addDays(3),
                        Essay_1_Text__c = '<p>Essay one prompt</p>', Essay_1_Allow_Upload__c = true,
                        Essay_2_Text__c = '<p>Essay two prompt</p>', Essay_2_Allow_Upload__c = true),
                // Essay 1 can only be typed.
                new Scholarship__c(Name = NAME_ESSAY_TEXT_ONLY, Open_Date__c = Date.today().addDays(-3), Close_Date__c = Date.today().addDays(3),
                        Essay_1_Text__c = '<p>Typed essay prompt</p>', Essay_1_Allow_Upload__c = false),
                // Recommender 1 is required and recommender 2 is optional. No email template or sender is set.
                new Scholarship__c(Name = NAME_RECOMMENDERS, Open_Date__c = Date.today().addDays(-3), Close_Date__c = Date.today().addDays(3),
                        Recommender_Option__c = 'Recommender Required', Recommender_Description__c = '<p>First recommender</p>',
                        Recommender2_Option__c = 'Recommender2 Optional', Recommender2_Description__c = '<p>Second recommender</p>'),
                // Only the second recommender is asked for.
                new Scholarship__c(Name = NAME_SECOND_RECOMMENDER_ONLY, Open_Date__c = Date.today().addDays(-3), Close_Date__c = Date.today().addDays(3),
                        Recommender_Option__c = 'No Recommender', Recommender2_Option__c = 'Recommender2 Required'),
                // Only a completion statement, so only the initials are asked for.
                new Scholarship__c(Name = NAME_STATEMENT, Open_Date__c = Date.today().addDays(-3), Close_Date__c = Date.today().addDays(3),
                        Completion_Statement__c = '<p>I agree to the terms.</p>'),
                // One of everything: a question, an essay that can be uploaded, a typed-only essay, both
                // recommenders (the first required) and a completion statement.
                new Scholarship__c(Name = NAME_EVERYTHING, Open_Date__c = Date.today().addDays(-3), Close_Date__c = Date.today().addDays(3),
                        Question_1_Text__c = '<p>A question</p>',
                        Essay_1_Text__c = '<p>Uploadable essay</p>', Essay_1_Allow_Upload__c = true,
                        Essay_2_Text__c = '<p>Typed essay</p>', Essay_2_Allow_Upload__c = false,
                        Recommender_Option__c = 'Recommender Required', Recommender2_Option__c = 'Recommender2 Optional',
                        Completion_Statement__c = '<p>I agree to the terms.</p>')
        };

        Account testAccount = new Account(Name = 'P2 Lwc Test Account');
        insert testAccount;

        insert new Contact(FirstName = 'P2', LastName = 'Student', Email = 'p2.student@test.com', AccountId = testAccount.Id);
    }

    private static Scholarship__c scholarshipByName(String name) {
        return [SELECT Id, Name, Scholarship_ID__c FROM Scholarship__c WHERE Name = :name LIMIT 1];
    }

    private static Contact student() {
        return [SELECT Id FROM Contact WHERE LastName = 'Student' LIMIT 1];
    }

    private static Scholarship_Applicant__c createApplicant(Scholarship__c scholarship, Boolean confirmed) {
        Scholarship_Applicant__c applicant = new Scholarship_Applicant__c(
                Scholarship__c = scholarship.Id,
                Contact__c = student().Id,
                Confirmed_Criteria__c = confirmed
        );
        insert applicant;
        return applicant;
    }

    private static Scholarship_Applicant__c reload(Id applicantId) {
        return [
                SELECT Id, Question_1_Answer__c, Question_2_Answer__c, Question_3_Answer__c, Question_4_Answer__c,
                        Essay_1_Answer__c, Essay_2_Answer__c, Essay_1_Uploaded__c, Essay_2_Uploaded__c,
                        Essay_1_Uploaded_Orig_Filename__c, Essay_2_Uploaded_Orig_Filename__c,
                        Recommender_Name__c, Recommender_Email__c, Recommender2_Name__c, Recommender2_Email__c,
                        Recommendation_Request_Date__c, Recommendation2_Request_Date__c,
                        Signature__c, Scholarship_Complete__c, Scholarship_Date_Submitted__c,
                        Declared_GPA__c, Scholarship_Status__c
                FROM Scholarship_Applicant__c
                WHERE Id = :applicantId
        ];
    }

    /**
     * Stores a File on the record, as lightning-file-upload does.
     *
     * @param linkedEntityId The record the file is attached to.
     * @param title The file's title.
     * @param pathOnClient The file's original name on the user's computer, including the extension.
     * @return The file's ContentDocument id.
     */
    private static Id createFile(Id linkedEntityId, String title, String pathOnClient) {
        ContentVersion version = new ContentVersion(
                Title = title,
                PathOnClient = pathOnClient,
                VersionData = Blob.valueOf('essay content'),
                FirstPublishLocationId = linkedEntityId
        );
        insert version;
        return [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :version.Id].ContentDocumentId;
    }

    private static Boolean documentExists(Id documentId) {
        return ![SELECT Id FROM ContentDocument WHERE Id = :documentId].isEmpty();
    }

    private static String documentTitle(Id documentId) {
        return [SELECT Title FROM ContentDocument WHERE Id = :documentId].Title;
    }

    private static Integer linkCount(Id documentId, Id linkedEntityId) {
        return [SELECT COUNT() FROM ContentDocumentLink WHERE ContentDocumentId = :documentId AND LinkedEntityId = :linkedEntityId];
    }

    /**
     * A second internal user.
     *
     * @return The new user, or null if the org has no 'Standard User' profile.
     */
    private static User createOtherUser() {
        List<Profile> profiles = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        if (profiles.isEmpty()) {
            return null;
        }
        User other = new User(
                Alias = 'p2other',
                Email = 'p2.other@test.com',
                EmailEncodingKey = 'UTF-8',
                LastName = 'Other',
                LanguageLocaleKey = 'en_US',
                LocaleSidKey = 'en_US',
                ProfileId = profiles[0].Id,
                TimeZoneSidKey = 'America/Chicago',
                Username = 'p2.other.' + Math.abs(Crypto.getRandomInteger()) + '@test.com'
        );
        // Avoids MIXED_DML_OPERATION: a user is a setup object and files are not.
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert other;
        }
        return other;
    }

    private static ScholarshipAppPage2LwcController.SaveResult attach(Scholarship__c scholarship, Integer essayNumber, Id documentId) {
        return ScholarshipAppPage2LwcController.attachEssayFileForContact(
                scholarship.Scholarship_ID__c, essayNumber, documentId == null ? null : String.valueOf(documentId), student().Id, accessFor(scholarship));
    }

    private static ScholarshipAppPage2LwcController.SaveResult deleteFile(Scholarship__c scholarship, Integer essayNumber) {
        return ScholarshipAppPage2LwcController.deleteEssayFileForContact(
                scholarship.Scholarship_ID__c, essayNumber, student().Id, accessFor(scholarship));
    }

    private static ScholarshipLwcService.AccessResult accessFor(Scholarship__c scholarship) {
        return ScholarshipLwcService.evaluateAccess(scholarship.Scholarship_ID__c, student().Id);
    }

    private static ScholarshipAppPage2LwcController.PageData pageData(Scholarship__c scholarship) {
        return ScholarshipAppPage2LwcController.buildPageData(scholarship.Scholarship_ID__c, student().Id, accessFor(scholarship));
    }

    private static ScholarshipAppPage2LwcController.SaveResult save(Scholarship__c scholarship, Map<String, String> answers) {
        return save(scholarship, answers, null, null);
    }

    private static ScholarshipAppPage2LwcController.SaveResult save(Scholarship__c scholarship, Map<String, String> answers, Map<String, String> essayAnswers) {
        return save(scholarship, answers, essayAnswers, null);
    }

    private static ScholarshipAppPage2LwcController.SaveResult save(Scholarship__c scholarship, Map<String, String> answers, Map<String, String> essayAnswers, Map<String, String> recommenders) {
        return save(scholarship, answers, essayAnswers, recommenders, null);
    }

    private static ScholarshipAppPage2LwcController.SaveResult save(Scholarship__c scholarship, Map<String, String> answers, Map<String, String> essayAnswers, Map<String, String> recommenders, String signature) {
        return ScholarshipAppPage2LwcController.saveAnswersForContact(scholarship.Scholarship_ID__c, answers, essayAnswers, recommenders, signature, student().Id, accessFor(scholarship));
    }

    private static ScholarshipAppPage2LwcController.SaveResult submit(Scholarship__c scholarship, Map<String, String> answers, Map<String, String> essayAnswers, Map<String, String> recommenders, String signature) {
        return ScholarshipAppPage2LwcController.submitApplicationForContact(scholarship.Scholarship_ID__c, answers, essayAnswers, recommenders, signature, student().Id, accessFor(scholarship));
    }

    // ---- getPageData ----

    @IsTest
    static void getPageData_unknownSid_returnsNotFound() {
        Test.startTest();
        ScholarshipAppPage2LwcController.PageData data = ScholarshipAppPage2LwcController.getPageData('does-not-exist');
        Test.stopTest();

        System.assertEquals(ScholarshipLwcService.STATUS_NOT_FOUND, data.status);
        System.assertEquals(0, data.questions.size());
    }

    @IsTest
    static void getPageData_runningUserWithoutContact_requiresCriteria() {
        Scholarship__c scholarship = scholarshipByName(NAME_QUESTIONS);
        createApplicant(scholarship, true);

        Test.startTest();
        // The running test user has no Contact, so another contact's applicant must not be used.
        ScholarshipAppPage2LwcController.PageData data = ScholarshipAppPage2LwcController.getPageData(scholarship.Scholarship_ID__c);
        Test.stopTest();

        System.assertEquals(ScholarshipAppPage2LwcController.STATUS_CRITERIA_REQUIRED, data.status);
        System.assertEquals(0, data.questions.size());
    }

    @IsTest
    static void buildPageData_onlyConfiguredQuestionsAreReturned() {
        Scholarship__c scholarship = scholarshipByName(NAME_QUESTIONS);
        Scholarship_Applicant__c applicant = createApplicant(scholarship, true);
        applicant.Question_1_Answer__c = 'Saved answer one';
        applicant.Question_2_Answer__c = 'Stale answer for a question that is not configured';
        update applicant;

        Test.startTest();
        ScholarshipAppPage2LwcController.PageData data = pageData(scholarship);
        Test.stopTest();

        System.assertEquals(ScholarshipLwcService.STATUS_OPEN, data.status);
        System.assertEquals(NAME_QUESTIONS, data.scholarshipName);
        System.assertEquals(2, data.questions.size());
        System.assertEquals(1, data.questions[0].questionNumber);
        System.assertEquals('<p>Why do you deserve it?</p>', data.questions[0].promptHtml);
        System.assertEquals('Saved answer one', data.questions[0].answer);
        System.assertEquals(7000, data.questions[0].maxLength);
        System.assertEquals(3, data.questions[1].questionNumber);
        System.assertEquals(null, data.questions[1].answer);
    }

    @IsTest
    static void buildPageData_scholarshipWithoutQuestions_returnsNone() {
        Scholarship__c scholarship = scholarshipByName(NAME_NO_QUESTIONS);
        createApplicant(scholarship, true);

        Test.startTest();
        ScholarshipAppPage2LwcController.PageData data = pageData(scholarship);
        Test.stopTest();

        System.assertEquals(ScholarshipLwcService.STATUS_OPEN, data.status);
        System.assertEquals(0, data.questions.size());
    }

    @IsTest
    static void buildPageData_noApplicant_requiresCriteria() {
        Scholarship__c scholarship = scholarshipByName(NAME_QUESTIONS);

        Test.startTest();
        ScholarshipAppPage2LwcController.PageData data = pageData(scholarship);
        Test.stopTest();

        System.assertEquals(ScholarshipAppPage2LwcController.STATUS_CRITERIA_REQUIRED, data.status);
        System.assertEquals(0, data.questions.size());
    }

    @IsTest
    static void buildPageData_criteriaNotConfirmed_requiresCriteria() {
        Scholarship__c scholarship = scholarshipByName(NAME_QUESTIONS);
        createApplicant(scholarship, false);

        Test.startTest();
        ScholarshipAppPage2LwcController.PageData data = pageData(scholarship);
        Test.stopTest();

        System.assertEquals(ScholarshipAppPage2LwcController.STATUS_CRITERIA_REQUIRED, data.status);
    }

    @IsTest
    static void buildPageData_closedScholarship_returnsClosedWithoutQuestions() {
        Scholarship__c scholarship = scholarshipByName(NAME_CLOSED);
        createApplicant(scholarship, true);

        Test.startTest();
        ScholarshipAppPage2LwcController.PageData data = pageData(scholarship);
        Test.stopTest();

        System.assertEquals(ScholarshipLwcService.STATUS_CLOSED, data.status);
        System.assertEquals(NAME_CLOSED, data.scholarshipName);
        System.assertEquals(0, data.questions.size());
    }

    @IsTest
    static void buildPageData_completedApplication_returnsComplete() {
        Scholarship__c scholarship = scholarshipByName(NAME_QUESTIONS);
        Scholarship_Applicant__c applicant = createApplicant(scholarship, true);
        applicant.Scholarship_Complete__c = true;
        update applicant;

        Test.startTest();
        ScholarshipAppPage2LwcController.PageData data = pageData(scholarship);
        Test.stopTest();

        System.assertEquals(ScholarshipLwcService.STATUS_COMPLETE, data.status);
        System.assertEquals(0, data.questions.size());
    }

    // ---- saveAnswers (Save & Finish Later) ----

    @IsTest
    static void saveAnswers_savesAnswersForConfiguredQuestions() {
        Scholarship__c scholarship = scholarshipByName(NAME_QUESTIONS);
        Scholarship_Applicant__c applicant = createApplicant(scholarship, true);

        Test.startTest();
        ScholarshipAppPage2LwcController.SaveResult result = save(scholarship, new Map<String, String>{
                '1' => 'First answer', '3' => 'Third answer'
        });
        Test.stopTest();

        System.assertEquals(true, result.success, result.message);
        Scholarship_Applicant__c saved = reload(applicant.Id);
        System.assertEquals('First answer', saved.Question_1_Answer__c);
        System.assertEquals('Third answer', saved.Question_3_Answer__c);
    }

    @IsTest
    static void saveAnswers_partialAnswers_arePreservedAndDoNotRequireTheRest() {
        Scholarship__c scholarship = scholarshipByName(NAME_QUESTIONS);
        Scholarship_Applicant__c applicant = createApplicant(scholarship, true);

        Test.startTest();
        ScholarshipAppPage2LwcController.SaveResult first = save(scholarship, new Map<String, String>{
                '1' => 'Only the first so far', '3' => ''
        });
        Test.stopTest();

        System.assertEquals(true, first.success, first.message);
        Scholarship_Applicant__c saved = reload(applicant.Id);
        System.assertEquals('Only the first so far', saved.Question_1_Answer__c);
        System.assertEquals(null, saved.Question_3_Answer__c);
    }

    @IsTest
    static void saveAnswers_blankAnswer_clearsPreviousAnswer() {
        Scholarship__c scholarship = scholarshipByName(NAME_QUESTIONS);
        Scholarship_Applicant__c applicant = createApplicant(scholarship, true);
        applicant.Question_1_Answer__c = 'Old answer';
        update applicant;

        Test.startTest();
        ScholarshipAppPage2LwcController.SaveResult result = save(scholarship, new Map<String, String>{
                '1' => '   '
        });
        Test.stopTest();

        System.assertEquals(true, result.success, result.message);
        System.assertEquals(null, reload(applicant.Id).Question_1_Answer__c);
    }

    @IsTest
    static void saveAnswers_doesNotTouchOtherApplicantData() {
        Scholarship__c scholarship = scholarshipByName(NAME_QUESTIONS);
        Scholarship_Applicant__c applicant = createApplicant(scholarship, true);
        applicant.Essay_1_Answer__c = 'Essay text';
        applicant.Recommender_Name__c = 'Dr Recommender';
        applicant.Declared_GPA__c = 3.5;
        applicant.Scholarship_Status__c = 'Started App';
        update applicant;

        Test.startTest();
        save(scholarship, new Map<String, String>{'1' => 'New answer'});
        Test.stopTest();

        Scholarship_Applicant__c saved = reload(applicant.Id);
        System.assertEquals('New answer', saved.Question_1_Answer__c);
        System.assertEquals('Essay text', saved.Essay_1_Answer__c);
        System.assertEquals('Dr Recommender', saved.Recommender_Name__c);
        System.assertEquals(3.5, saved.Declared_GPA__c);
        System.assertEquals('Started App', saved.Scholarship_Status__c);
    }

    @IsTest
    static void saveAnswers_ignoresQuestionsTheScholarshipDoesNotHave() {
        Scholarship__c scholarship = scholarshipByName(NAME_QUESTIONS);
        Scholarship_Applicant__c applicant = createApplicant(scholarship, true);

        Test.startTest();
        ScholarshipAppPage2LwcController.SaveResult result = save(scholarship, new Map<String, String>{
                '2' => 'Not a question here', '4' => 'Neither', '5' => 'Out of range', '0' => 'Out of range',
                'abc' => 'Not a number', '' => 'Empty key', '1' => 'Real answer'
        });
        Test.stopTest();

        System.assertEquals(true, result.success, result.message);
        Scholarship_Applicant__c saved = reload(applicant.Id);
        System.assertEquals('Real answer', saved.Question_1_Answer__c);
        System.assertEquals(null, saved.Question_2_Answer__c);
        System.assertEquals(null, saved.Question_4_Answer__c);
    }

    @IsTest
    static void saveAnswers_noRecognizedAnswers_reportsFailureInsteadOfSilentlySucceeding() {
        Scholarship__c scholarship = scholarshipByName(NAME_QUESTIONS);
        Scholarship_Applicant__c applicant = createApplicant(scholarship, true);
        applicant.Question_1_Answer__c = 'Kept';
        update applicant;

        Test.startTest();
        // Answers were submitted but none of them match this scholarship's questions (for example, keys that
        // were not populated), so reporting "saved" would be wrong.
        ScholarshipAppPage2LwcController.SaveResult result = save(scholarship, new Map<String, String>{
                '2' => 'Not configured', 'abc' => 'Not a number'
        });
        Test.stopTest();

        System.assertEquals(false, result.success);
        System.assertEquals(ScholarshipLwcService.STATUS_OPEN, result.status);
        System.assertNotEquals(null, result.message);
        System.assertEquals('Kept', reload(applicant.Id).Question_1_Answer__c);
    }

    @IsTest
    static void saveAnswers_scholarshipWithoutQuestions_emptyAnswersSucceed() {
        Scholarship__c scholarship = scholarshipByName(NAME_NO_QUESTIONS);
        createApplicant(scholarship, true);

        Test.startTest();
        ScholarshipAppPage2LwcController.SaveResult result = save(scholarship, new Map<String, String>());
        Test.stopTest();

        System.assertEquals(true, result.success, result.message);
    }

    @IsTest
    static void saveAnswers_answerTooLong_rejectsTheWholeSave() {
        Scholarship__c scholarship = scholarshipByName(NAME_QUESTIONS);
        Scholarship_Applicant__c applicant = createApplicant(scholarship, true);
        applicant.Question_1_Answer__c = 'Existing';
        update applicant;

        Test.startTest();
        ScholarshipAppPage2LwcController.SaveResult result = save(scholarship, new Map<String, String>{
                '1' => 'Changed', '3' => 'a'.repeat(7001)
        });
        Test.stopTest();

        System.assertEquals(false, result.success);
        System.assertEquals(ScholarshipLwcService.STATUS_OPEN, result.status);
        System.assert(result.message.contains('question 3'), result.message);
        System.assertEquals('Existing', reload(applicant.Id).Question_1_Answer__c, 'Nothing is saved when any answer is rejected');
    }

    @IsTest
    static void saveAnswers_answerAtMaximumLength_isSaved() {
        Scholarship__c scholarship = scholarshipByName(NAME_QUESTIONS);
        Scholarship_Applicant__c applicant = createApplicant(scholarship, true);

        Test.startTest();
        ScholarshipAppPage2LwcController.SaveResult result = save(scholarship, new Map<String, String>{
                '1' => 'a'.repeat(7000)
        });
        Test.stopTest();

        System.assertEquals(true, result.success, result.message);
        System.assertEquals(7000, reload(applicant.Id).Question_1_Answer__c.length());
    }

    @IsTest
    static void saveAnswers_nullAnswerList_succeedsWithoutChanges() {
        Scholarship__c scholarship = scholarshipByName(NAME_QUESTIONS);
        Scholarship_Applicant__c applicant = createApplicant(scholarship, true);
        applicant.Question_1_Answer__c = 'Kept';
        update applicant;

        Test.startTest();
        ScholarshipAppPage2LwcController.SaveResult result = save(scholarship, null);
        Test.stopTest();

        System.assertEquals(true, result.success, result.message);
        System.assertEquals('Kept', reload(applicant.Id).Question_1_Answer__c);
    }

    @IsTest
    static void saveAnswers_noApplicant_requiresCriteriaAndCreatesNothing() {
        Scholarship__c scholarship = scholarshipByName(NAME_QUESTIONS);

        Test.startTest();
        ScholarshipAppPage2LwcController.SaveResult result = save(scholarship, new Map<String, String>{'1' => 'Answer'});
        Test.stopTest();

        System.assertEquals(false, result.success);
        System.assertEquals(ScholarshipAppPage2LwcController.STATUS_CRITERIA_REQUIRED, result.status);
        System.assertEquals(0, [SELECT COUNT() FROM Scholarship_Applicant__c WHERE Scholarship__c = :scholarship.Id]);
    }

    @IsTest
    static void saveAnswers_criteriaNotConfirmed_doesNotSave() {
        Scholarship__c scholarship = scholarshipByName(NAME_QUESTIONS);
        Scholarship_Applicant__c applicant = createApplicant(scholarship, false);

        Test.startTest();
        ScholarshipAppPage2LwcController.SaveResult result = save(scholarship, new Map<String, String>{'1' => 'Answer'});
        Test.stopTest();

        System.assertEquals(false, result.success);
        System.assertEquals(ScholarshipAppPage2LwcController.STATUS_CRITERIA_REQUIRED, result.status);
        System.assertEquals(null, reload(applicant.Id).Question_1_Answer__c);
    }

    @IsTest
    static void saveAnswers_closedScholarship_doesNotSave() {
        Scholarship__c scholarship = scholarshipByName(NAME_CLOSED);
        Scholarship_Applicant__c applicant = createApplicant(scholarship, true);

        Test.startTest();
        ScholarshipAppPage2LwcController.SaveResult result = save(scholarship, new Map<String, String>{'1' => 'Too late'});
        Test.stopTest();

        System.assertEquals(false, result.success);
        System.assertEquals(ScholarshipLwcService.STATUS_CLOSED, result.status);
        System.assertEquals(null, reload(applicant.Id).Question_1_Answer__c);
    }

    @IsTest
    static void saveAnswers_completedApplication_doesNotSave() {
        Scholarship__c scholarship = scholarshipByName(NAME_QUESTIONS);
        Scholarship_Applicant__c applicant = createApplicant(scholarship, true);
        applicant.Scholarship_Complete__c = true;
        update applicant;

        Test.startTest();
        ScholarshipAppPage2LwcController.SaveResult result = save(scholarship, new Map<String, String>{'1' => 'After submit'});
        Test.stopTest();

        System.assertEquals(false, result.success);
        System.assertEquals(ScholarshipLwcService.STATUS_COMPLETE, result.status);
        System.assertEquals(null, reload(applicant.Id).Question_1_Answer__c);
    }

    @IsTest
    static void saveAnswers_unknownSid_returnsNotFound() {
        Test.startTest();
        ScholarshipAppPage2LwcController.SaveResult result = ScholarshipAppPage2LwcController.saveAnswers('does-not-exist', new Map<String, String>{'1' => 'x'}, null, null, null);
        Test.stopTest();

        System.assertEquals(false, result.success);
        System.assertEquals(ScholarshipLwcService.STATUS_NOT_FOUND, result.status);
    }

    @IsTest
    static void saveAnswers_runningUserWithoutContact_doesNotSave() {
        Scholarship__c scholarship = scholarshipByName(NAME_QUESTIONS);
        Scholarship_Applicant__c applicant = createApplicant(scholarship, true);

        Test.startTest();
        // The running test user has no Contact, so the public entry point must not touch another contact's applicant.
        ScholarshipAppPage2LwcController.SaveResult result = ScholarshipAppPage2LwcController.saveAnswers(
                scholarship.Scholarship_ID__c, new Map<String, String>{'1' => 'Not mine'}, null, null, null);
        Test.stopTest();

        System.assertEquals(false, result.success);
        System.assertEquals(null, reload(applicant.Id).Question_1_Answer__c);
    }

    // ---- essays: getPageData ----

    @IsTest
    static void buildPageData_essays_returnsPromptsAnswersAndUploadState() {
        Scholarship__c scholarship = scholarshipByName(NAME_ESSAYS);
        Scholarship_Applicant__c applicant = createApplicant(scholarship, true);
        applicant.Essay_1_Answer__c = '<p>My draft</p>';
        applicant.Essay_2_Uploaded__c = true;
        applicant.Essay_2_Uploaded_Orig_Filename__c = 'old essay.pdf';
        update applicant;

        Test.startTest();
        ScholarshipAppPage2LwcController.PageData data = pageData(scholarship);
        Test.stopTest();

        System.assertEquals(ScholarshipLwcService.STATUS_OPEN, data.status);
        System.assertEquals(applicant.Id, data.applicantId);
        System.assertEquals(new List<String>{'.pdf', '.doc', '.docx', '.txt', '.rtf'}, data.allowedFileExtensions);
        System.assertEquals(0, data.questions.size());
        System.assertEquals(2, data.essays.size());

        System.assertEquals(1, data.essays[0].essayNumber);
        System.assertEquals('<p>Essay one prompt</p>', data.essays[0].promptHtml);
        System.assertEquals(true, data.essays[0].allowUpload);
        System.assertEquals('<p>My draft</p>', data.essays[0].answerHtml);
        System.assertEquals(false, data.essays[0].uploaded);

        System.assertEquals(2, data.essays[1].essayNumber);
        System.assertEquals(true, data.essays[1].uploaded);
        System.assertEquals('old essay.pdf', data.essays[1].uploadedFilename);
    }

    @IsTest
    static void buildPageData_essayThatCannotBeUploaded_isFlagged() {
        Scholarship__c scholarship = scholarshipByName(NAME_ESSAY_TEXT_ONLY);
        createApplicant(scholarship, true);

        Test.startTest();
        ScholarshipAppPage2LwcController.PageData data = pageData(scholarship);
        Test.stopTest();

        System.assertEquals(1, data.essays.size());
        System.assertEquals(false, data.essays[0].allowUpload);
    }

    @IsTest
    static void buildPageData_scholarshipWithoutEssays_returnsNone() {
        Scholarship__c scholarship = scholarshipByName(NAME_QUESTIONS);
        createApplicant(scholarship, true);

        Test.startTest();
        ScholarshipAppPage2LwcController.PageData data = pageData(scholarship);
        Test.stopTest();

        System.assertEquals(0, data.essays.size());
    }

    // ---- essays: typed answers (Save & Finish Later) ----

    @IsTest
    static void saveAnswers_savesTypedEssays() {
        Scholarship__c scholarship = scholarshipByName(NAME_ESSAYS);
        Scholarship_Applicant__c applicant = createApplicant(scholarship, true);

        Test.startTest();
        ScholarshipAppPage2LwcController.SaveResult result = save(scholarship, new Map<String, String>(), new Map<String, String>{
                '1' => '<p>First essay</p>', '2' => '<p>Second essay</p>'
        });
        Test.stopTest();

        System.assertEquals(true, result.success, result.message);
        Scholarship_Applicant__c saved = reload(applicant.Id);
        System.assertEquals('<p>First essay</p>', saved.Essay_1_Answer__c);
        System.assertEquals('<p>Second essay</p>', saved.Essay_2_Answer__c);
    }

    @IsTest
    static void saveAnswers_essaysOmittedFromTheRequest_areLeftAlone() {
        Scholarship__c scholarship = scholarshipByName(NAME_ESSAYS);
        Scholarship_Applicant__c applicant = createApplicant(scholarship, true);
        applicant.Essay_1_Answer__c = '<p>Kept while the applicant uploads instead</p>';
        update applicant;

        Test.startTest();
        ScholarshipAppPage2LwcController.SaveResult result = save(scholarship, new Map<String, String>(), new Map<String, String>{
                '2' => '<p>Only essay two</p>'
        });
        Test.stopTest();

        System.assertEquals(true, result.success, result.message);
        Scholarship_Applicant__c saved = reload(applicant.Id);
        System.assertEquals('<p>Kept while the applicant uploads instead</p>', saved.Essay_1_Answer__c);
        System.assertEquals('<p>Only essay two</p>', saved.Essay_2_Answer__c);
    }

    @IsTest
    static void saveAnswers_emptyLookingRichText_isStoredAsBlank() {
        Scholarship__c scholarship = scholarshipByName(NAME_ESSAYS);
        Scholarship_Applicant__c applicant = createApplicant(scholarship, true);
        applicant.Essay_1_Answer__c = '<p>Old</p>';
        applicant.Essay_2_Answer__c = '<p>Old</p>';
        update applicant;

        Test.startTest();
        save(scholarship, new Map<String, String>(), new Map<String, String>{'1' => '<p><br></p>', '2' => '<p>&nbsp;</p>'});
        Test.stopTest();

        Scholarship_Applicant__c saved = reload(applicant.Id);
        System.assertEquals(null, saved.Essay_1_Answer__c);
        System.assertEquals(null, saved.Essay_2_Answer__c);
    }

    @IsTest
    static void saveAnswers_essayWithOnlyAnImage_isNotBlank() {
        Scholarship__c scholarship = scholarshipByName(NAME_ESSAYS);
        Scholarship_Applicant__c applicant = createApplicant(scholarship, true);

        Test.startTest();
        save(scholarship, new Map<String, String>(), new Map<String, String>{'1' => '<p><img src="https://example.com/a.png"></p>'});
        Test.stopTest();

        System.assertNotEquals(null, reload(applicant.Id).Essay_1_Answer__c);
    }

    @IsTest
    static void saveAnswers_essayTooLong_rejectsTheWholeSave() {
        Scholarship__c scholarship = scholarshipByName(NAME_ESSAYS);
        Scholarship_Applicant__c applicant = createApplicant(scholarship, true);
        applicant.Essay_1_Answer__c = '<p>Existing</p>';
        update applicant;

        Test.startTest();
        ScholarshipAppPage2LwcController.SaveResult result = save(scholarship, new Map<String, String>(), new Map<String, String>{
                '1' => '<p>Changed</p>', '2' => 'a'.repeat(ScholarshipAppPage2LwcController.MAX_ESSAY_LENGTH + 1)
        });
        Test.stopTest();

        System.assertEquals(false, result.success);
        System.assert(result.message.contains('Essay 2'), result.message);
        System.assertEquals('<p>Existing</p>', reload(applicant.Id).Essay_1_Answer__c);
    }

    @IsTest
    static void saveAnswers_essayTheScholarshipDoesNotHave_reportsFailure() {
        Scholarship__c scholarship = scholarshipByName(NAME_QUESTIONS);
        createApplicant(scholarship, true);

        Test.startTest();
        ScholarshipAppPage2LwcController.SaveResult result = save(scholarship, new Map<String, String>(), new Map<String, String>{'1' => '<p>No such essay</p>'});
        Test.stopTest();

        System.assertEquals(false, result.success);
    }

    @IsTest
    static void saveAnswers_questionsAndEssaysTogether() {
        Scholarship__c scholarship = scholarshipByName(NAME_QUESTIONS);
        Scholarship_Applicant__c applicant = createApplicant(scholarship, true);
        // NAME_QUESTIONS has no essays, so only the question is stored, and the unknown essay is ignored.
        Test.startTest();
        ScholarshipAppPage2LwcController.SaveResult result = save(scholarship, new Map<String, String>{'1' => 'Answer'}, new Map<String, String>{'1' => '<p>Ignored</p>'});
        Test.stopTest();

        System.assertEquals(true, result.success, result.message);
        Scholarship_Applicant__c saved = reload(applicant.Id);
        System.assertEquals('Answer', saved.Question_1_Answer__c);
        System.assertEquals(null, saved.Essay_1_Answer__c);
    }

    // ---- essays: attachEssayFile ----

    @IsTest
    static void attachEssayFile_validFile_marksUploadedAndTitlesTheFile() {
        Scholarship__c scholarship = scholarshipByName(NAME_ESSAYS);
        Scholarship_Applicant__c applicant = createApplicant(scholarship, true);
        Id documentId = createFile(applicant.Id, 'My Essay', 'my essay.pdf');

        Test.startTest();
        ScholarshipAppPage2LwcController.SaveResult result = attach(scholarship, 1, documentId);
        Test.stopTest();

        System.assertEquals(true, result.success, result.message);
        System.assertEquals(true, result.uploaded);
        System.assertEquals('my essay.pdf', result.uploadedFilename);
        Scholarship_Applicant__c saved = reload(applicant.Id);
        System.assertEquals(true, saved.Essay_1_Uploaded__c);
        System.assertEquals('my essay.pdf', saved.Essay_1_Uploaded_Orig_Filename__c);
        System.assertEquals(false, saved.Essay_2_Uploaded__c);
        System.assertEquals('Essay1_My Essay', documentTitle(documentId));
        System.assertEquals(1, linkCount(documentId, applicant.Id));
    }

    @IsTest
    static void attachEssayFile_secondEssay_isTrackedSeparately() {
        Scholarship__c scholarship = scholarshipByName(NAME_ESSAYS);
        Scholarship_Applicant__c applicant = createApplicant(scholarship, true);
        Id first = createFile(applicant.Id, 'First', 'first.pdf');
        Id second = createFile(applicant.Id, 'Second', 'second.docx');

        Test.startTest();
        ScholarshipAppPage2LwcController.SaveResult one = attach(scholarship, 1, first);
        ScholarshipAppPage2LwcController.SaveResult two = attach(scholarship, 2, second);
        Test.stopTest();

        System.assertEquals(true, one.success, one.message);
        System.assertEquals(true, two.success, two.message);
        Scholarship_Applicant__c saved = reload(applicant.Id);
        System.assertEquals('first.pdf', saved.Essay_1_Uploaded_Orig_Filename__c);
        System.assertEquals('second.docx', saved.Essay_2_Uploaded_Orig_Filename__c);
        System.assertEquals('Essay1_First', documentTitle(first));
        System.assertEquals('Essay2_Second', documentTitle(second));
    }

    @IsTest
    static void attachEssayFile_upperCaseExtension_isAccepted() {
        Scholarship__c scholarship = scholarshipByName(NAME_ESSAYS);
        Scholarship_Applicant__c applicant = createApplicant(scholarship, true);
        Id documentId = createFile(applicant.Id, 'Loud Essay', 'LOUD ESSAY.PDF');

        Test.startTest();
        ScholarshipAppPage2LwcController.SaveResult result = attach(scholarship, 1, documentId);
        Test.stopTest();

        System.assertEquals(true, result.success, result.message);
    }

    @IsTest
    static void attachEssayFile_disallowedFileType_isRejectedAndRemoved() {
        Scholarship__c scholarship = scholarshipByName(NAME_ESSAYS);
        Scholarship_Applicant__c applicant = createApplicant(scholarship, true);
        Id documentId = createFile(applicant.Id, 'Malware', 'setup.exe');

        Test.startTest();
        ScholarshipAppPage2LwcController.SaveResult result = attach(scholarship, 1, documentId);
        Test.stopTest();

        System.assertEquals(false, result.success);
        System.assertEquals('Invalid file type. Please upload a .pdf, .doc, .docx, .txt, or .rtf file.', result.message);
        System.assertEquals(false, documentExists(documentId), 'The rejected file must not stay on the application');
        Scholarship_Applicant__c saved = reload(applicant.Id);
        System.assertEquals(false, saved.Essay_1_Uploaded__c);
        System.assertEquals(null, saved.Essay_1_Uploaded_Orig_Filename__c);
    }

    @IsTest
    static void attachEssayFile_fileWithoutExtension_isRejected() {
        Scholarship__c scholarship = scholarshipByName(NAME_ESSAYS);
        Scholarship_Applicant__c applicant = createApplicant(scholarship, true);
        Id documentId = createFile(applicant.Id, 'No extension', 'noextension');

        Test.startTest();
        ScholarshipAppPage2LwcController.SaveResult result = attach(scholarship, 1, documentId);
        Test.stopTest();

        System.assertEquals(false, result.success);
        System.assertEquals(false, documentExists(documentId));
    }

    @IsTest
    static void attachEssayFile_essayAlreadyHasAFile_rejectsTheNewFileAndKeepsTheOld() {
        Scholarship__c scholarship = scholarshipByName(NAME_ESSAYS);
        Scholarship_Applicant__c applicant = createApplicant(scholarship, true);
        Id original = createFile(applicant.Id, 'Original', 'original.pdf');
        attach(scholarship, 1, original);
        Id replacement = createFile(applicant.Id, 'Replacement', 'replacement.pdf');

        Test.startTest();
        ScholarshipAppPage2LwcController.SaveResult result = attach(scholarship, 1, replacement);
        Test.stopTest();

        System.assertEquals(false, result.success);
        System.assert(result.message.contains('already been uploaded'), result.message);
        System.assertEquals(false, documentExists(replacement));
        System.assertEquals(true, documentExists(original));
        System.assertEquals('original.pdf', reload(applicant.Id).Essay_1_Uploaded_Orig_Filename__c);
    }

    @IsTest
    static void attachEssayFile_essayThatCannotBeUploaded_isRejectedAndRemoved() {
        Scholarship__c scholarship = scholarshipByName(NAME_ESSAY_TEXT_ONLY);
        Scholarship_Applicant__c applicant = createApplicant(scholarship, true);
        Id documentId = createFile(applicant.Id, 'Sneaky', 'sneaky.pdf');

        Test.startTest();
        ScholarshipAppPage2LwcController.SaveResult result = attach(scholarship, 1, documentId);
        Test.stopTest();

        System.assertEquals(false, result.success);
        System.assertEquals(false, documentExists(documentId));
        System.assertEquals(false, reload(applicant.Id).Essay_1_Uploaded__c);
    }

    @IsTest
    static void attachEssayFile_essayTheScholarshipDoesNotHave_isRejected() {
        Scholarship__c scholarship = scholarshipByName(NAME_ESSAYS);
        Scholarship_Applicant__c applicant = createApplicant(scholarship, true);
        Id documentId = createFile(applicant.Id, 'Third', 'third.pdf');

        Test.startTest();
        ScholarshipAppPage2LwcController.SaveResult result3 = attach(scholarship, 3, documentId);
        ScholarshipAppPage2LwcController.SaveResult resultNull = attach(scholarship, null, documentId);
        Test.stopTest();

        System.assertEquals(false, result3.success);
        System.assertEquals(false, resultNull.success);
    }

    @IsTest
    static void attachEssayFile_fileNotLinkedToTheApplicant_isRejectedAndLeftAlone() {
        Scholarship__c scholarship = scholarshipByName(NAME_ESSAYS);
        createApplicant(scholarship, true);
        // A file attached to some other record, not to the applicant.
        Id documentId = createFile(student().Id, 'Elsewhere', 'elsewhere.pdf');

        Test.startTest();
        ScholarshipAppPage2LwcController.SaveResult result = attach(scholarship, 1, documentId);
        Test.stopTest();

        System.assertEquals(false, result.success);
        System.assertEquals(ScholarshipAppPage2LwcController.MSG_FILE_NOT_FOUND, result.message);
        System.assertEquals(true, documentExists(documentId), 'A file that is not on the application must not be deleted');
    }

    @IsTest
    static void attachEssayFile_fileOwnedBySomeoneElse_isRejectedAndLeftAlone() {
        Scholarship__c scholarship = scholarshipByName(NAME_ESSAYS);
        Scholarship_Applicant__c applicant = createApplicant(scholarship, true);
        Id documentId = createFile(applicant.Id, 'Not mine', 'not mine.pdf');
        User other = createOtherUser();
        if (other == null) {
            return; // The org has no 'Standard User' profile to create a second owner with.
        }
        try {
            update new ContentDocument(Id = documentId, OwnerId = other.Id);
        } catch (DmlException ex) {
            return; // Ownership of this file cannot be changed in this org, so the case cannot be set up.
        }

        Test.startTest();
        ScholarshipAppPage2LwcController.SaveResult result = attach(scholarship, 1, documentId);
        Test.stopTest();

        System.assertEquals(false, result.success);
        System.assertEquals(true, documentExists(documentId));
        System.assertEquals(false, reload(applicant.Id).Essay_1_Uploaded__c);
    }

    @IsTest
    static void attachEssayFile_invalidOrMissingDocumentId_isRejected() {
        Scholarship__c scholarship = scholarshipByName(NAME_ESSAYS);
        createApplicant(scholarship, true);

        Test.startTest();
        ScholarshipAppPage2LwcController.SaveResult notAnId = ScholarshipAppPage2LwcController.attachEssayFileForContact(
                scholarship.Scholarship_ID__c, 1, 'not-an-id', student().Id, accessFor(scholarship));
        ScholarshipAppPage2LwcController.SaveResult blank = attach(scholarship, 1, null);
        Test.stopTest();

        System.assertEquals(false, notAnId.success);
        System.assertEquals(false, blank.success);
    }

    @IsTest
    static void attachEssayFile_noApplicant_requiresCriteria() {
        Scholarship__c scholarship = scholarshipByName(NAME_ESSAYS);
        Id documentId = createFile(scholarship.Id, 'Early', 'early.pdf');

        Test.startTest();
        ScholarshipAppPage2LwcController.SaveResult result = attach(scholarship, 1, documentId);
        Test.stopTest();

        System.assertEquals(false, result.success);
        System.assertEquals(ScholarshipAppPage2LwcController.STATUS_CRITERIA_REQUIRED, result.status);
    }

    @IsTest
    static void attachEssayFile_closedScholarship_isRejected() {
        Scholarship__c scholarship = scholarshipByName(NAME_CLOSED);
        createApplicant(scholarship, true);

        Test.startTest();
        ScholarshipAppPage2LwcController.SaveResult result = attach(scholarship, 1, null);
        Test.stopTest();

        System.assertEquals(false, result.success);
        System.assertEquals(ScholarshipLwcService.STATUS_CLOSED, result.status);
    }

    @IsTest
    static void attachEssayFile_publicEntryPoints_refuseUnknownScholarshipAndUsersWithoutContact() {
        Scholarship__c scholarship = scholarshipByName(NAME_ESSAYS);
        Scholarship_Applicant__c applicant = createApplicant(scholarship, true);
        Id documentId = createFile(applicant.Id, 'Mine', 'mine.pdf');

        Test.startTest();
        ScholarshipAppPage2LwcController.SaveResult unknown = ScholarshipAppPage2LwcController.attachEssayFile('does-not-exist', 1, String.valueOf(documentId));
        // The running test user has no Contact, so another contact's applicant must not be used.
        ScholarshipAppPage2LwcController.SaveResult noContact = ScholarshipAppPage2LwcController.attachEssayFile(scholarship.Scholarship_ID__c, 1, String.valueOf(documentId));
        Test.stopTest();

        System.assertEquals(ScholarshipLwcService.STATUS_NOT_FOUND, unknown.status);
        System.assertEquals(false, unknown.success);
        System.assertEquals(false, noContact.success);
        System.assertEquals(false, reload(applicant.Id).Essay_1_Uploaded__c);
    }

    // ---- essays: deleteEssayFile ("Delete and re-upload") ----

    @IsTest
    static void deleteEssayFile_removesTheFileAndResetsTheUploadFields() {
        Scholarship__c scholarship = scholarshipByName(NAME_ESSAYS);
        Scholarship_Applicant__c applicant = createApplicant(scholarship, true);
        Id documentId = createFile(applicant.Id, 'My Essay', 'my essay.pdf');
        attach(scholarship, 1, documentId);

        Test.startTest();
        ScholarshipAppPage2LwcController.SaveResult result = deleteFile(scholarship, 1);
        Test.stopTest();

        System.assertEquals(true, result.success, result.message);
        System.assertEquals(false, result.uploaded);
        System.assertEquals(false, documentExists(documentId));
        Scholarship_Applicant__c saved = reload(applicant.Id);
        System.assertEquals(false, saved.Essay_1_Uploaded__c);
        System.assertEquals(null, saved.Essay_1_Uploaded_Orig_Filename__c);
    }

    @IsTest
    static void deleteEssayFile_afterDelete_theEssayCanBeUploadedAgain() {
        Scholarship__c scholarship = scholarshipByName(NAME_ESSAYS);
        Scholarship_Applicant__c applicant = createApplicant(scholarship, true);
        attach(scholarship, 1, createFile(applicant.Id, 'First try', 'first try.pdf'));
        deleteFile(scholarship, 1);
        Id second = createFile(applicant.Id, 'Second try', 'second try.docx');

        Test.startTest();
        ScholarshipAppPage2LwcController.SaveResult result = attach(scholarship, 1, second);
        Test.stopTest();

        System.assertEquals(true, result.success, result.message);
        System.assertEquals('second try.docx', reload(applicant.Id).Essay_1_Uploaded_Orig_Filename__c);
    }

    @IsTest
    static void deleteEssayFile_onlyAffectsTheRequestedEssay() {
        Scholarship__c scholarship = scholarshipByName(NAME_ESSAYS);
        Scholarship_Applicant__c applicant = createApplicant(scholarship, true);
        Id first = createFile(applicant.Id, 'First', 'first.pdf');
        Id second = createFile(applicant.Id, 'Second', 'second.pdf');
        attach(scholarship, 1, first);
        attach(scholarship, 2, second);

        Test.startTest();
        ScholarshipAppPage2LwcController.SaveResult result = deleteFile(scholarship, 1);
        Test.stopTest();

        System.assertEquals(true, result.success, result.message);
        System.assertEquals(false, documentExists(first));
        System.assertEquals(true, documentExists(second));
        Scholarship_Applicant__c saved = reload(applicant.Id);
        System.assertEquals(false, saved.Essay_1_Uploaded__c);
        System.assertEquals(true, saved.Essay_2_Uploaded__c);
        System.assertEquals('second.pdf', saved.Essay_2_Uploaded_Orig_Filename__c);
    }

    @IsTest
    static void deleteEssayFile_doesNotTouchOtherFilesOnTheApplicant() {
        Scholarship__c scholarship = scholarshipByName(NAME_ESSAYS);
        Scholarship_Applicant__c applicant = createApplicant(scholarship, true);
        attach(scholarship, 1, createFile(applicant.Id, 'Essay file', 'essay.pdf'));
        Id unrelated = createFile(applicant.Id, 'Transcript', 'transcript.pdf');

        Test.startTest();
        deleteFile(scholarship, 1);
        Test.stopTest();

        System.assertEquals(true, documentExists(unrelated));
    }

    @IsTest
    static void deleteEssayFile_removesAnOldVisualforceAttachment() {
        Scholarship__c scholarship = scholarshipByName(NAME_ESSAYS);
        Scholarship_Applicant__c applicant = createApplicant(scholarship, true);
        applicant.Essay_1_Uploaded__c = true;
        applicant.Essay_1_Uploaded_Orig_Filename__c = 'from the old page.pdf';
        update applicant;
        insert new List<Attachment>{
                new Attachment(ParentId = applicant.Id, Name = 'Essay1.pdf', Body = Blob.valueOf('old')),
                new Attachment(ParentId = applicant.Id, Name = 'Essay2.pdf', Body = Blob.valueOf('other essay'))
        };

        Test.startTest();
        ScholarshipAppPage2LwcController.SaveResult result = deleteFile(scholarship, 1);
        Test.stopTest();

        System.assertEquals(true, result.success, result.message);
        System.assertEquals(0, [SELECT COUNT() FROM Attachment WHERE ParentId = :applicant.Id AND Name = 'Essay1.pdf']);
        System.assertEquals(1, [SELECT COUNT() FROM Attachment WHERE ParentId = :applicant.Id AND Name = 'Essay2.pdf'], 'The other essay is untouched');
        System.assertEquals(false, reload(applicant.Id).Essay_1_Uploaded__c);
    }

    @IsTest
    static void deleteEssayFile_flagSetButNoFileLeft_stillResetsTheFields() {
        Scholarship__c scholarship = scholarshipByName(NAME_ESSAYS);
        Scholarship_Applicant__c applicant = createApplicant(scholarship, true);
        applicant.Essay_2_Uploaded__c = true;
        applicant.Essay_2_Uploaded_Orig_Filename__c = 'gone.pdf';
        update applicant;

        Test.startTest();
        ScholarshipAppPage2LwcController.SaveResult result = deleteFile(scholarship, 2);
        Test.stopTest();

        System.assertEquals(true, result.success, result.message);
        Scholarship_Applicant__c saved = reload(applicant.Id);
        System.assertEquals(false, saved.Essay_2_Uploaded__c);
        System.assertEquals(null, saved.Essay_2_Uploaded_Orig_Filename__c);
    }

    @IsTest
    static void deleteEssayFile_fileOwnedBySomeoneElse_onlyUnlinksIt() {
        Scholarship__c scholarship = scholarshipByName(NAME_ESSAYS);
        Scholarship_Applicant__c applicant = createApplicant(scholarship, true);
        Id documentId = createFile(applicant.Id, 'Essay1_Staff copy', 'staff copy.pdf');
        User other = createOtherUser();
        if (other == null) {
            return; // The org has no 'Standard User' profile to create a second owner with.
        }
        try {
            update new ContentDocument(Id = documentId, OwnerId = other.Id);
        } catch (DmlException ex) {
            return; // Ownership of this file cannot be changed in this org, so the case cannot be set up.
        }
        applicant.Essay_1_Uploaded__c = true;
        update applicant;

        Test.startTest();
        ScholarshipAppPage2LwcController.SaveResult result = deleteFile(scholarship, 1);
        Test.stopTest();

        System.assertEquals(true, result.success, result.message);
        System.assertEquals(true, documentExists(documentId), 'A file the applicant does not own is not deleted');
        System.assertEquals(0, linkCount(documentId, applicant.Id), 'but it is no longer attached to the application');
        System.assertEquals(false, reload(applicant.Id).Essay_1_Uploaded__c);
    }

    @IsTest
    static void deleteEssayFile_essayTheScholarshipDoesNotHave_isRejected() {
        Scholarship__c scholarship = scholarshipByName(NAME_ESSAYS);
        createApplicant(scholarship, true);

        Test.startTest();
        ScholarshipAppPage2LwcController.SaveResult result = deleteFile(scholarship, 3);
        Test.stopTest();

        System.assertEquals(false, result.success);
    }

    @IsTest
    static void deleteEssayFile_noApplicantOrClosedScholarship_isRejected() {
        Scholarship__c noApplicant = scholarshipByName(NAME_ESSAYS);
        Scholarship__c closed = scholarshipByName(NAME_CLOSED);
        createApplicant(closed, true);

        Test.startTest();
        ScholarshipAppPage2LwcController.SaveResult resultNoApplicant = deleteFile(noApplicant, 1);
        ScholarshipAppPage2LwcController.SaveResult resultClosed = deleteFile(closed, 1);
        Test.stopTest();

        System.assertEquals(ScholarshipAppPage2LwcController.STATUS_CRITERIA_REQUIRED, resultNoApplicant.status);
        System.assertEquals(ScholarshipLwcService.STATUS_CLOSED, resultClosed.status);
        System.assertEquals(false, resultNoApplicant.success);
        System.assertEquals(false, resultClosed.success);
    }

    @IsTest
    static void deleteEssayFile_publicEntryPoint_refusesUnknownScholarshipAndUsersWithoutContact() {
        Scholarship__c scholarship = scholarshipByName(NAME_ESSAYS);
        Scholarship_Applicant__c applicant = createApplicant(scholarship, true);
        applicant.Essay_1_Uploaded__c = true;
        update applicant;

        Test.startTest();
        ScholarshipAppPage2LwcController.SaveResult unknown = ScholarshipAppPage2LwcController.deleteEssayFile('does-not-exist', 1);
        ScholarshipAppPage2LwcController.SaveResult noContact = ScholarshipAppPage2LwcController.deleteEssayFile(scholarship.Scholarship_ID__c, 1);
        Test.stopTest();

        System.assertEquals(ScholarshipLwcService.STATUS_NOT_FOUND, unknown.status);
        System.assertEquals(false, noContact.success);
        System.assertEquals(true, reload(applicant.Id).Essay_1_Uploaded__c, 'Another contact\'s upload must not be reset');
    }

    // ---- recommenders ----

    private static ScholarshipAppPage2LwcController.SaveResult requestRecommendation(Scholarship__c scholarship, Integer recommenderNumber, String name, String email) {
        return ScholarshipAppPage2LwcController.requestRecommendationForContact(
                scholarship.Scholarship_ID__c, recommenderNumber, name, email, student().Id, accessFor(scholarship));
    }

    // ---- recommenders: getPageData ----

    @IsTest
    static void buildPageData_recommenders_returnsDescriptionsSavedValuesAndSentDate() {
        Scholarship__c scholarship = scholarshipByName(NAME_RECOMMENDERS);
        Scholarship_Applicant__c applicant = createApplicant(scholarship, true);
        applicant.Recommender_Name__c = 'Dr One';
        applicant.Recommender_Email__c = 'one@test.com';
        // 19:15 GMT on 3 May is 2:15 PM Central (daylight time).
        applicant.Recommendation_Request_Date__c = Datetime.newInstanceGmt(2026, 5, 3, 19, 15, 0);
        update applicant;

        Test.startTest();
        ScholarshipAppPage2LwcController.PageData data = pageData(scholarship);
        Test.stopTest();

        System.assertEquals(2, data.recommenders.size());

        ScholarshipAppPage2LwcController.Recommender first = data.recommenders[0];
        System.assertEquals(1, first.recommenderNumber);
        System.assertEquals(true, first.required);
        System.assertEquals('<p>First recommender</p>', first.descriptionHtml);
        System.assertEquals('Dr One', first.name);
        System.assertEquals('one@test.com', first.email);
        System.assertEquals('May 3, 2026 02:15 PM', first.requestedOn);

        ScholarshipAppPage2LwcController.Recommender second = data.recommenders[1];
        System.assertEquals(2, second.recommenderNumber);
        System.assertEquals(false, second.required);
        System.assertEquals('<p>Second recommender</p>', second.descriptionHtml);
        System.assertEquals(null, second.name);
        System.assertEquals(null, second.requestedOn);
    }

    @IsTest
    static void buildPageData_noRecommenderOption_isLeftOut() {
        Scholarship__c secondOnly = scholarshipByName(NAME_SECOND_RECOMMENDER_ONLY);
        Scholarship__c none = scholarshipByName(NAME_QUESTIONS);
        createApplicant(secondOnly, true);
        createApplicant(none, true);

        Test.startTest();
        ScholarshipAppPage2LwcController.PageData onlySecond = pageData(secondOnly);
        ScholarshipAppPage2LwcController.PageData noRecommenders = pageData(none);
        Test.stopTest();

        System.assertEquals(1, onlySecond.recommenders.size());
        System.assertEquals(2, onlySecond.recommenders[0].recommenderNumber);
        System.assertEquals(true, onlySecond.recommenders[0].required);
        System.assertEquals(0, noRecommenders.recommenders.size());
    }

    // ---- recommenders: Save & Finish Later ----

    @IsTest
    static void saveAnswers_savesRecommenderNamesAndEmails() {
        Scholarship__c scholarship = scholarshipByName(NAME_RECOMMENDERS);
        Scholarship_Applicant__c applicant = createApplicant(scholarship, true);

        Test.startTest();
        ScholarshipAppPage2LwcController.SaveResult result = save(scholarship, new Map<String, String>(), null, new Map<String, String>{
                'name1' => '  Dr One ', 'email1' => ' one@test.com ', 'name2' => 'Prof Two', 'email2' => 'two@test.com'
        });
        Test.stopTest();

        System.assertEquals(true, result.success, result.message);
        Scholarship_Applicant__c saved = reload(applicant.Id);
        System.assertEquals('Dr One', saved.Recommender_Name__c);
        System.assertEquals('one@test.com', saved.Recommender_Email__c);
        System.assertEquals('Prof Two', saved.Recommender2_Name__c);
        System.assertEquals('two@test.com', saved.Recommender2_Email__c);
        System.assertEquals(null, saved.Recommendation_Request_Date__c, 'Saving must never send a request');
    }

    @IsTest
    static void saveAnswers_blankRecommenderValues_clearThem() {
        Scholarship__c scholarship = scholarshipByName(NAME_RECOMMENDERS);
        Scholarship_Applicant__c applicant = createApplicant(scholarship, true);
        applicant.Recommender_Name__c = 'Dr One';
        applicant.Recommender_Email__c = 'one@test.com';
        update applicant;

        Test.startTest();
        ScholarshipAppPage2LwcController.SaveResult result = save(scholarship, new Map<String, String>(), null, new Map<String, String>{
                'name1' => '', 'email1' => '   '
        });
        Test.stopTest();

        System.assertEquals(true, result.success, result.message);
        Scholarship_Applicant__c saved = reload(applicant.Id);
        System.assertEquals(null, saved.Recommender_Name__c);
        System.assertEquals(null, saved.Recommender_Email__c);
    }

    @IsTest
    static void saveAnswers_recommenderWhoseRequestWasSent_isLocked() {
        Scholarship__c scholarship = scholarshipByName(NAME_RECOMMENDERS);
        Scholarship_Applicant__c applicant = createApplicant(scholarship, true);
        applicant.Recommender_Name__c = 'Dr One';
        applicant.Recommender_Email__c = 'one@test.com';
        applicant.Recommendation_Request_Date__c = Datetime.now().addDays(-1);
        update applicant;

        Test.startTest();
        ScholarshipAppPage2LwcController.SaveResult result = save(scholarship, new Map<String, String>(), null, new Map<String, String>{
                'name1' => 'Someone Else', 'email1' => 'else@test.com', 'name2' => 'Prof Two'
        });
        Test.stopTest();

        System.assertEquals(true, result.success, result.message);
        Scholarship_Applicant__c saved = reload(applicant.Id);
        System.assertEquals('Dr One', saved.Recommender_Name__c, 'A recommender who was already asked cannot be changed');
        System.assertEquals('one@test.com', saved.Recommender_Email__c);
        System.assertEquals('Prof Two', saved.Recommender2_Name__c);
    }

    @IsTest
    static void saveAnswers_invalidRecommenderEmail_rejectsTheWholeSave() {
        Scholarship__c scholarship = scholarshipByName(NAME_RECOMMENDERS);
        Scholarship_Applicant__c applicant = createApplicant(scholarship, true);

        Test.startTest();
        ScholarshipAppPage2LwcController.SaveResult result = save(scholarship, new Map<String, String>(), null, new Map<String, String>{
                'name1' => 'Dr One', 'email1' => 'one@test.com', 'name2' => 'Prof Two', 'email2' => 'not an email'
        });
        Test.stopTest();

        System.assertEquals(false, result.success);
        System.assert(result.message.contains('recommendation 2'), result.message);
        System.assertEquals(null, reload(applicant.Id).Recommender_Name__c, 'Nothing is saved when any value is rejected');
    }

    @IsTest
    static void saveAnswers_recommenderNameTooLong_isRejected() {
        Scholarship__c scholarship = scholarshipByName(NAME_RECOMMENDERS);
        createApplicant(scholarship, true);

        Test.startTest();
        ScholarshipAppPage2LwcController.SaveResult result = save(scholarship, new Map<String, String>(), null, new Map<String, String>{
                'name1' => 'a'.repeat(ScholarshipAppPage2LwcController.MAX_RECOMMENDER_NAME_LENGTH + 1)
        });
        Test.stopTest();

        System.assertEquals(false, result.success);
        System.assert(result.message.contains('too long'), result.message);
    }

    @IsTest
    static void saveAnswers_recommenderTheScholarshipDoesNotAskFor_reportsFailure() {
        Scholarship__c scholarship = scholarshipByName(NAME_SECOND_RECOMMENDER_ONLY);
        Scholarship_Applicant__c applicant = createApplicant(scholarship, true);

        Test.startTest();
        ScholarshipAppPage2LwcController.SaveResult notAsked = save(scholarship, new Map<String, String>(), null, new Map<String, String>{
                'name1' => 'Dr One', 'email1' => 'one@test.com', 'name3' => 'Nobody', 'foo' => 'bar'
        });
        Test.stopTest();

        System.assertEquals(false, notAsked.success);
        System.assertEquals(null, reload(applicant.Id).Recommender_Name__c);
    }

    // ---- recommenders: Request Now ----

    @IsTest
    static void requestRecommendation_invalidInput_savesNothing() {
        Scholarship__c scholarship = scholarshipByName(NAME_RECOMMENDERS);
        Scholarship_Applicant__c applicant = createApplicant(scholarship, true);

        Test.startTest();
        ScholarshipAppPage2LwcController.SaveResult blankName = requestRecommendation(scholarship, 1, '  ', 'one@test.com');
        ScholarshipAppPage2LwcController.SaveResult nullName = requestRecommendation(scholarship, 1, null, 'one@test.com');
        ScholarshipAppPage2LwcController.SaveResult longName = requestRecommendation(scholarship, 1,
                'a'.repeat(ScholarshipAppPage2LwcController.MAX_RECOMMENDER_NAME_LENGTH + 1), 'one@test.com');
        ScholarshipAppPage2LwcController.SaveResult blankEmail = requestRecommendation(scholarship, 1, 'Dr One', '');
        ScholarshipAppPage2LwcController.SaveResult badEmail = requestRecommendation(scholarship, 1, 'Dr One', 'not an email');
        Test.stopTest();

        System.assertEquals(false, blankName.success);
        System.assertEquals(false, nullName.success);
        System.assertEquals(false, longName.success);
        System.assertEquals(false, blankEmail.success);
        System.assertEquals(false, badEmail.success);
        System.assert(badEmail.message.contains('valid email'), badEmail.message);
        Scholarship_Applicant__c saved = reload(applicant.Id);
        System.assertEquals(null, saved.Recommender_Name__c);
        System.assertEquals(null, saved.Recommender_Email__c);
        System.assertEquals(null, saved.Recommendation_Request_Date__c);
    }

    @IsTest
    static void requestRecommendation_noEmailTemplate_keepsTheRecommenderButSendsNothing() {
        Scholarship__c scholarship = scholarshipByName(NAME_RECOMMENDERS);
        Scholarship_Applicant__c applicant = createApplicant(scholarship, true);

        Test.startTest();
        ScholarshipAppPage2LwcController.SaveResult result = requestRecommendation(scholarship, 1, 'Dr One', 'one@test.com');
        Test.stopTest();

        System.assertEquals(false, result.success);
        System.assertEquals(null, result.requestedOn);
        System.assert(result.message.contains('Recommender 1 Email Template Not Set'), result.message);
        System.assertEquals(0, Limits.getEmailInvocations());
        Scholarship_Applicant__c saved = reload(applicant.Id);
        System.assertEquals('Dr One', saved.Recommender_Name__c, 'The recommender is saved even though no email was sent');
        System.assertEquals('one@test.com', saved.Recommender_Email__c);
        System.assertEquals(null, saved.Recommendation_Request_Date__c, 'No send date, so the applicant can try again');
    }

    @IsTest
    static void requestRecommendation_noSenderAddress_keepsTheRecommenderButSendsNothing() {
        Scholarship__c scholarship = scholarshipByName(NAME_RECOMMENDERS);
        update new Scholarship__c(Id = scholarship.Id, Recommender2_Email_Template_Id__c = '00X000000000000AAA');
        Scholarship_Applicant__c applicant = createApplicant(scholarship, true);

        Test.startTest();
        ScholarshipAppPage2LwcController.SaveResult result = requestRecommendation(scholarship, 2, 'Prof Two', 'two@test.com');
        Test.stopTest();

        System.assertEquals(false, result.success);
        System.assert(result.message.contains('Org Wide Email Not Set'), result.message);
        Scholarship_Applicant__c saved = reload(applicant.Id);
        System.assertEquals('Prof Two', saved.Recommender2_Name__c);
        System.assertEquals(null, saved.Recommendation2_Request_Date__c);
    }

    @IsTest
    static void requestRecommendation_emailCannotBeBuilt_stillSavesTheRecommender() {
        Scholarship__c scholarship = scholarshipByName(NAME_RECOMMENDERS);
        // Ids that do not exist, so building the email from the template fails.
        update new Scholarship__c(Id = scholarship.Id, Recommender_Email_Template_Id__c = '00X000000000000AAA', Org_Wide_Email_Id__c = '0D2000000000000AAA');
        Scholarship_Applicant__c applicant = createApplicant(scholarship, true);

        Test.startTest();
        ScholarshipAppPage2LwcController.SaveResult result = requestRecommendation(scholarship, 1, 'Dr One', 'one@test.com');
        Test.stopTest();

        System.assertEquals(false, result.success);
        System.assert(result.message.contains('Recommender 1 Email Template exception'), result.message);
        System.assertEquals(0, Limits.getEmailInvocations());
        Scholarship_Applicant__c saved = reload(applicant.Id);
        System.assertEquals('Dr One', saved.Recommender_Name__c, 'The recommender is saved even though the email failed');
        System.assertEquals('one@test.com', saved.Recommender_Email__c);
        System.assertEquals(null, saved.Recommendation_Request_Date__c);
    }

    @IsTest
    static void requestRecommendation_validSetup_sendsTheEmailAndRecordsTheDate() {
        List<OrgWideEmailAddress> senders = [SELECT Id FROM OrgWideEmailAddress LIMIT 1];
        if (senders.isEmpty()) {
            return; // The org has no organization-wide email address to send from, so the send cannot be tested.
        }
        EmailTemplate template = new EmailTemplate(
                Name = 'P2 Lwc Recommendation Request',
                DeveloperName = 'P2_Lwc_Recommendation_Request',
                TemplateType = 'text',
                FolderId = UserInfo.getUserId(),
                Subject = 'Recommendation request',
                Body = 'Please recommend our applicant.'
        );
        insert template;
        Scholarship__c scholarship = scholarshipByName(NAME_RECOMMENDERS);
        update new Scholarship__c(Id = scholarship.Id, Recommender_Email_Template_Id__c = template.Id, Org_Wide_Email_Id__c = senders[0].Id);
        Scholarship_Applicant__c applicant = createApplicant(scholarship, true);

        Test.startTest();
        ScholarshipAppPage2LwcController.SaveResult result = requestRecommendation(scholarship, 1, ' Dr One ', ' one@test.com ');
        Test.stopTest();

        System.assertEquals(true, result.success, result.message);
        System.assertNotEquals(null, result.requestedOn);
        System.assertEquals(1, Limits.getEmailInvocations());
        Scholarship_Applicant__c saved = reload(applicant.Id);
        System.assertEquals('Dr One', saved.Recommender_Name__c);
        System.assertEquals('one@test.com', saved.Recommender_Email__c);
        System.assertNotEquals(null, saved.Recommendation_Request_Date__c);
        System.assertEquals(null, saved.Recommendation2_Request_Date__c, 'Only the requested recommender is marked as sent');
    }

    @IsTest
    static void requestRecommendation_alreadySent_isNotRepeatedOrChanged() {
        Scholarship__c scholarship = scholarshipByName(NAME_RECOMMENDERS);
        Scholarship_Applicant__c applicant = createApplicant(scholarship, true);
        applicant.Recommender_Name__c = 'Dr One';
        applicant.Recommender_Email__c = 'one@test.com';
        applicant.Recommendation_Request_Date__c = Datetime.newInstanceGmt(2026, 5, 3, 19, 15, 0);
        update applicant;

        Test.startTest();
        ScholarshipAppPage2LwcController.SaveResult result = requestRecommendation(scholarship, 1, 'Someone Else', 'else@test.com');
        Test.stopTest();

        System.assertEquals(false, result.success);
        System.assert(result.message.contains('already been sent'), result.message);
        System.assertEquals('May 3, 2026 02:15 PM', result.requestedOn);
        System.assertEquals(0, Limits.getEmailInvocations());
        System.assertEquals('Dr One', reload(applicant.Id).Recommender_Name__c);
    }

    @IsTest
    static void requestRecommendation_recommenderTheScholarshipDoesNotAskFor_isRejected() {
        Scholarship__c scholarship = scholarshipByName(NAME_SECOND_RECOMMENDER_ONLY);
        Scholarship_Applicant__c applicant = createApplicant(scholarship, true);

        Test.startTest();
        ScholarshipAppPage2LwcController.SaveResult first = requestRecommendation(scholarship, 1, 'Dr One', 'one@test.com');
        ScholarshipAppPage2LwcController.SaveResult third = requestRecommendation(scholarship, 3, 'Dr Three', 'three@test.com');
        ScholarshipAppPage2LwcController.SaveResult none = requestRecommendation(scholarship, null, 'Nobody', 'nobody@test.com');
        Test.stopTest();

        System.assertEquals(false, first.success);
        System.assertEquals(false, third.success);
        System.assertEquals(false, none.success);
        System.assertEquals(null, reload(applicant.Id).Recommender_Name__c);
    }

    @IsTest
    static void requestRecommendation_noApplicantOrClosedScholarship_isRejected() {
        Scholarship__c noApplicant = scholarshipByName(NAME_RECOMMENDERS);
        Scholarship__c closed = scholarshipByName(NAME_CLOSED);
        createApplicant(closed, true);

        Test.startTest();
        ScholarshipAppPage2LwcController.SaveResult resultNoApplicant = requestRecommendation(noApplicant, 1, 'Dr One', 'one@test.com');
        ScholarshipAppPage2LwcController.SaveResult resultClosed = requestRecommendation(closed, 1, 'Dr One', 'one@test.com');
        Test.stopTest();

        System.assertEquals(ScholarshipAppPage2LwcController.STATUS_CRITERIA_REQUIRED, resultNoApplicant.status);
        System.assertEquals(ScholarshipLwcService.STATUS_CLOSED, resultClosed.status);
        System.assertEquals(false, resultNoApplicant.success);
        System.assertEquals(false, resultClosed.success);
    }

    @IsTest
    static void requestRecommendation_publicEntryPoint_refusesUnknownScholarshipAndUsersWithoutContact() {
        Scholarship__c scholarship = scholarshipByName(NAME_RECOMMENDERS);
        Scholarship_Applicant__c applicant = createApplicant(scholarship, true);

        Test.startTest();
        ScholarshipAppPage2LwcController.SaveResult unknown = ScholarshipAppPage2LwcController.requestRecommendation('does-not-exist', 1, 'Dr One', 'one@test.com');
        // The running test user has no Contact, so another contact's applicant must not be used.
        ScholarshipAppPage2LwcController.SaveResult noContact = ScholarshipAppPage2LwcController.requestRecommendation(scholarship.Scholarship_ID__c, 1, 'Dr One', 'one@test.com');
        Test.stopTest();

        System.assertEquals(ScholarshipLwcService.STATUS_NOT_FOUND, unknown.status);
        System.assertEquals(false, unknown.success);
        System.assertEquals(false, noContact.success);
        System.assertEquals(null, reload(applicant.Id).Recommender_Name__c);
    }

    // ---- recommenders: email check ----

    @IsTest
    static void isValidEmail_acceptsAddressesAndRejectsGarbage() {
        System.assertEquals(true, ScholarshipAppPage2LwcController.isValidEmail('person@example.com'));
        System.assertEquals(true, ScholarshipAppPage2LwcController.isValidEmail(' first.last+tag@sub.example.org '));
        System.assertEquals(false, ScholarshipAppPage2LwcController.isValidEmail(null));
        System.assertEquals(false, ScholarshipAppPage2LwcController.isValidEmail(''));
        System.assertEquals(false, ScholarshipAppPage2LwcController.isValidEmail('no-at-sign.example.com'));
        System.assertEquals(false, ScholarshipAppPage2LwcController.isValidEmail('two@@example.com'));
        System.assertEquals(false, ScholarshipAppPage2LwcController.isValidEmail('spaces in@example.com'));
        System.assertEquals(false, ScholarshipAppPage2LwcController.isValidEmail('missing-dot@example'));
        System.assertEquals(false, ScholarshipAppPage2LwcController.isValidEmail('short-tld@example.c'));
    }

    // ---- completion statement and initials ----

    @IsTest
    static void buildPageData_completionStatement_returnsStatementAndSavedInitials() {
        Scholarship__c withStatement = scholarshipByName(NAME_STATEMENT);
        Scholarship__c without = scholarshipByName(NAME_QUESTIONS);
        Scholarship_Applicant__c applicant = createApplicant(withStatement, true);
        applicant.Signature__c = 'AB';
        update applicant;
        createApplicant(without, true);

        Test.startTest();
        ScholarshipAppPage2LwcController.PageData data = pageData(withStatement);
        ScholarshipAppPage2LwcController.PageData noStatement = pageData(without);
        Test.stopTest();

        System.assertEquals('<p>I agree to the terms.</p>', data.completionStatementHtml);
        System.assertEquals('AB', data.signature);
        System.assertEquals(null, noStatement.completionStatementHtml);
        System.assertEquals(null, noStatement.signature);
    }

    @IsTest
    static void saveAnswers_savesTheInitialsWhenThereIsACompletionStatement() {
        Scholarship__c scholarship = scholarshipByName(NAME_STATEMENT);
        Scholarship_Applicant__c applicant = createApplicant(scholarship, true);

        Test.startTest();
        ScholarshipAppPage2LwcController.SaveResult result = save(scholarship, new Map<String, String>(), null, null, '  AB ');
        Test.stopTest();

        System.assertEquals(true, result.success, result.message);
        System.assertEquals('AB', reload(applicant.Id).Signature__c);
    }

    @IsTest
    static void saveAnswers_nullInitialsLeaveThemAlone_andBlankInitialsClearThem() {
        Scholarship__c scholarship = scholarshipByName(NAME_STATEMENT);
        Scholarship_Applicant__c applicant = createApplicant(scholarship, true);
        applicant.Signature__c = 'AB';
        update applicant;

        Test.startTest();
        save(scholarship, new Map<String, String>(), null, null, null);
        String afterNull = reload(applicant.Id).Signature__c;
        save(scholarship, new Map<String, String>(), null, null, '   ');
        String afterBlank = reload(applicant.Id).Signature__c;
        Test.stopTest();

        System.assertEquals('AB', afterNull);
        System.assertEquals(null, afterBlank);
    }

    @IsTest
    static void saveAnswers_initialsAreIgnoredWithoutACompletionStatement() {
        Scholarship__c scholarship = scholarshipByName(NAME_QUESTIONS);
        Scholarship_Applicant__c applicant = createApplicant(scholarship, true);

        Test.startTest();
        ScholarshipAppPage2LwcController.SaveResult result = save(scholarship, new Map<String, String>(), null, null, 'AB');
        Test.stopTest();

        System.assertEquals(true, result.success, result.message);
        System.assertEquals(null, reload(applicant.Id).Signature__c);
    }

    @IsTest
    static void saveAnswers_initialsTooLong_areRejected() {
        Scholarship__c scholarship = scholarshipByName(NAME_STATEMENT);
        Scholarship_Applicant__c applicant = createApplicant(scholarship, true);

        Test.startTest();
        ScholarshipAppPage2LwcController.SaveResult result = save(scholarship, new Map<String, String>(), null, null,
                'a'.repeat(ScholarshipAppPage2LwcController.MAX_SIGNATURE_LENGTH + 1));
        Test.stopTest();

        System.assertEquals(false, result.success);
        System.assert(result.message.contains('initials'), result.message);
        System.assertEquals(null, reload(applicant.Id).Signature__c);
    }

    // ---- Save & Submit: the completeness check ----

    @IsTest
    static void validateForSubmit_completeApplication_hasNoProblems() {
        Scholarship__c scholarship = new Scholarship__c(Question_1_Text__c = '<p>Q</p>', Completion_Statement__c = '<p>Agree</p>');
        Scholarship_Applicant__c applicant = new Scholarship_Applicant__c(Question_1_Answer__c = 'A', Signature__c = 'AB');

        ScholarshipAppPage2LwcController.SubmitCheck check = ScholarshipAppPage2LwcController.validateForSubmit(scholarship, applicant);

        System.assertEquals(0, check.messages.size());
        System.assertEquals(0, check.invalidFields.size());
    }

    @IsTest
    static void validateForSubmit_everyConfiguredQuestionNeedsAnAnswer() {
        Scholarship__c scholarship = new Scholarship__c(Question_1_Text__c = '<p>Q1</p>', Question_3_Text__c = '<p>Q3</p>');
        Scholarship_Applicant__c applicant = new Scholarship_Applicant__c(Question_1_Answer__c = '   ', Question_2_Answer__c = 'Answer to a question not asked');

        ScholarshipAppPage2LwcController.SubmitCheck check = ScholarshipAppPage2LwcController.validateForSubmit(scholarship, applicant);

        System.assertEquals(new List<String>{'question:1', 'question:3'}, check.invalidFields);
        System.assertEquals(new List<String>{'Please answer question 1.', 'Please answer question 3.'}, check.messages);
    }

    @IsTest
    static void validateForSubmit_uploadableEssayNeedsAFileOrText_butTypedOnlyEssayDoesNot() {
        Scholarship__c scholarship = new Scholarship__c(
                Essay_1_Text__c = '<p>E1</p>', Essay_1_Allow_Upload__c = true,
                Essay_2_Text__c = '<p>E2</p>', Essay_2_Allow_Upload__c = false);

        ScholarshipAppPage2LwcController.SubmitCheck empty = ScholarshipAppPage2LwcController.validateForSubmit(scholarship, new Scholarship_Applicant__c());
        ScholarshipAppPage2LwcController.SubmitCheck blankLooking = ScholarshipAppPage2LwcController.validateForSubmit(scholarship,
                new Scholarship_Applicant__c(Essay_1_Answer__c = '<p><br></p>'));
        ScholarshipAppPage2LwcController.SubmitCheck typed = ScholarshipAppPage2LwcController.validateForSubmit(scholarship,
                new Scholarship_Applicant__c(Essay_1_Answer__c = '<p>My essay</p>'));
        ScholarshipAppPage2LwcController.SubmitCheck uploaded = ScholarshipAppPage2LwcController.validateForSubmit(scholarship,
                new Scholarship_Applicant__c(Essay_1_Uploaded__c = true));

        System.assertEquals(new List<String>{'essay:1'}, empty.invalidFields, 'Essay 2 can only be typed, so it may stay empty, as on the VF page');
        System.assertEquals(new List<String>{'essay:1'}, blankLooking.invalidFields);
        System.assertEquals(0, typed.invalidFields.size());
        System.assertEquals(0, uploaded.invalidFields.size());
    }

    @IsTest
    static void validateForSubmit_requiredRecommenderNeedsNameAndValidEmail_optionalOneDoesNot() {
        Scholarship__c scholarship = new Scholarship__c(Recommender_Option__c = 'Recommender Required', Recommender2_Option__c = 'Recommender2 Optional');

        ScholarshipAppPage2LwcController.SubmitCheck empty = ScholarshipAppPage2LwcController.validateForSubmit(scholarship, new Scholarship_Applicant__c());
        ScholarshipAppPage2LwcController.SubmitCheck onlyName = ScholarshipAppPage2LwcController.validateForSubmit(scholarship,
                new Scholarship_Applicant__c(Recommender_Name__c = 'Dr One'));
        ScholarshipAppPage2LwcController.SubmitCheck complete = ScholarshipAppPage2LwcController.validateForSubmit(scholarship,
                new Scholarship_Applicant__c(Recommender_Name__c = 'Dr One', Recommender_Email__c = 'one@test.com'));

        System.assertEquals(new List<String>{'recommender:1:name', 'recommender:1:email'}, empty.invalidFields);
        System.assertEquals(1, empty.messages.size(), 'One message per recommender');
        System.assertEquals(new List<String>{'recommender:1:email'}, onlyName.invalidFields);
        System.assertEquals(0, complete.invalidFields.size());
    }

    @IsTest
    static void validateForSubmit_secondRecommenderCanBeTheRequiredOne() {
        Scholarship__c scholarship = new Scholarship__c(Recommender_Option__c = 'No Recommender', Recommender2_Option__c = 'Recommender2 Required');

        ScholarshipAppPage2LwcController.SubmitCheck check = ScholarshipAppPage2LwcController.validateForSubmit(scholarship, new Scholarship_Applicant__c());

        System.assertEquals(new List<String>{'recommender:2:name', 'recommender:2:email'}, check.invalidFields);
    }

    @IsTest
    static void validateForSubmit_initialsAreOnlyRequiredWithACompletionStatement() {
        Scholarship__c withStatement = new Scholarship__c(Completion_Statement__c = '<p>Agree</p>');
        Scholarship__c without = new Scholarship__c();

        ScholarshipAppPage2LwcController.SubmitCheck missing = ScholarshipAppPage2LwcController.validateForSubmit(withStatement, new Scholarship_Applicant__c());
        ScholarshipAppPage2LwcController.SubmitCheck notNeeded = ScholarshipAppPage2LwcController.validateForSubmit(without, new Scholarship_Applicant__c());

        System.assertEquals(new List<String>{'signature'}, missing.invalidFields);
        System.assertEquals(0, notNeeded.invalidFields.size());
    }

    // ---- Save & Submit ----

    @IsTest
    static void submitApplication_nothingRequired_marksTheApplicationSubmitted() {
        Scholarship__c scholarship = scholarshipByName(NAME_NO_QUESTIONS);
        Scholarship_Applicant__c applicant = createApplicant(scholarship, true);

        Test.startTest();
        ScholarshipAppPage2LwcController.SaveResult result = submit(scholarship, new Map<String, String>(), null, null, null);
        Test.stopTest();

        System.assertEquals(true, result.success, result.message);
        System.assertEquals(0, result.invalidFields.size());
        Scholarship_Applicant__c saved = reload(applicant.Id);
        System.assertEquals(true, saved.Scholarship_Complete__c);
        System.assertEquals('Submitted App', saved.Scholarship_Status__c);
        System.assertNotEquals(null, saved.Scholarship_Date_Submitted__c);
    }

    @IsTest
    static void submitApplication_noSubmitEmailTemplate_stillSubmitsButFlagsTheEmail() {
        Scholarship__c scholarship = scholarshipByName(NAME_NO_QUESTIONS);
        Scholarship_Applicant__c applicant = createApplicant(scholarship, true);

        Test.startTest();
        ScholarshipAppPage2LwcController.SaveResult result = submit(scholarship, new Map<String, String>(), null, null, null);
        Test.stopTest();

        System.assertEquals(true, result.success, result.message);
        System.assertEquals(true, result.submitEmailFailed);
        System.assertEquals(0, Limits.getEmailInvocations());
        System.assertEquals(true, reload(applicant.Id).Scholarship_Complete__c);
    }

    @IsTest
    static void submitApplication_confirmationEmailCannotBeBuilt_stillSubmits() {
        Scholarship__c scholarship = scholarshipByName(NAME_NO_QUESTIONS);
        // Ids that do not exist, so building the confirmation email fails.
        update new Scholarship__c(Id = scholarship.Id, Submit_Scholarship_Email_Template_Id__c = '00X000000000000AAA', Org_Wide_Email_Id__c = '0D2000000000000AAA');
        Scholarship_Applicant__c applicant = createApplicant(scholarship, true);

        Test.startTest();
        ScholarshipAppPage2LwcController.SaveResult result = submit(scholarship, new Map<String, String>(), null, null, null);
        Test.stopTest();

        System.assertEquals(true, result.success, result.message);
        System.assertEquals(true, result.submitEmailFailed);
        System.assertEquals(true, reload(applicant.Id).Scholarship_Complete__c);
    }

    @IsTest
    static void submitApplication_incomplete_savesTheWorkButSubmitsNothing() {
        Scholarship__c scholarship = scholarshipByName(NAME_QUESTIONS);
        Scholarship_Applicant__c applicant = createApplicant(scholarship, true);

        Test.startTest();
        ScholarshipAppPage2LwcController.SaveResult result = submit(scholarship, new Map<String, String>{'1' => 'Only the first'}, null, null, null);
        Test.stopTest();

        System.assertEquals(false, result.success);
        System.assertEquals(ScholarshipLwcService.STATUS_OPEN, result.status);
        System.assertEquals(new List<String>{'question:3'}, result.invalidFields);
        System.assertEquals('Please answer question 3.', result.message);
        Scholarship_Applicant__c saved = reload(applicant.Id);
        System.assertEquals('Only the first', saved.Question_1_Answer__c, 'The entered answer is kept');
        System.assertEquals(false, saved.Scholarship_Complete__c);
        System.assertEquals(null, saved.Scholarship_Date_Submitted__c);
    }

    @IsTest
    static void submitApplication_questionsAnsweredInTheSameRequest_areEnough() {
        Scholarship__c scholarship = scholarshipByName(NAME_QUESTIONS);
        Scholarship_Applicant__c applicant = createApplicant(scholarship, true);

        Test.startTest();
        ScholarshipAppPage2LwcController.SaveResult result = submit(scholarship, new Map<String, String>{'1' => 'One', '3' => 'Three'}, null, null, null);
        Test.stopTest();

        System.assertEquals(true, result.success, result.message);
        System.assertEquals(true, reload(applicant.Id).Scholarship_Complete__c);
    }

    @IsTest
    static void submitApplication_uploadableEssays_needAFileOrText() {
        Scholarship__c scholarship = scholarshipByName(NAME_ESSAYS);
        Scholarship_Applicant__c applicant = createApplicant(scholarship, true);

        Test.startTest();
        ScholarshipAppPage2LwcController.SaveResult missing = submit(scholarship, new Map<String, String>(), null, null, null);
        // Essay 1 typed, essay 2 already has an uploaded file.
        applicant.Essay_2_Uploaded__c = true;
        applicant.Essay_2_Uploaded_Orig_Filename__c = 'essay two.pdf';
        update applicant;
        ScholarshipAppPage2LwcController.SaveResult answered = submit(scholarship, new Map<String, String>(),
                new Map<String, String>{'1' => '<p>My first essay</p>'}, null, null);
        Test.stopTest();

        System.assertEquals(false, missing.success);
        System.assertEquals(new List<String>{'essay:1', 'essay:2'}, missing.invalidFields);
        System.assertEquals(true, answered.success, answered.message);
    }

    @IsTest
    static void submitApplication_essayThatCanOnlyBeTyped_mayStayEmpty() {
        Scholarship__c scholarship = scholarshipByName(NAME_ESSAY_TEXT_ONLY);
        createApplicant(scholarship, true);

        Test.startTest();
        ScholarshipAppPage2LwcController.SaveResult result = submit(scholarship, new Map<String, String>(), null, null, null);
        Test.stopTest();

        System.assertEquals(true, result.success, result.message);
    }

    @IsTest
    static void submitApplication_requiredRecommenderMissing_isReported() {
        Scholarship__c scholarship = scholarshipByName(NAME_RECOMMENDERS);
        Scholarship_Applicant__c applicant = createApplicant(scholarship, true);

        Test.startTest();
        ScholarshipAppPage2LwcController.SaveResult result = submit(scholarship, new Map<String, String>(), null, new Map<String, String>{'name2' => 'Prof Two'}, null);
        Test.stopTest();

        System.assertEquals(false, result.success);
        System.assertEquals(new List<String>{'recommender:1:name', 'recommender:1:email'}, result.invalidFields);
        System.assertEquals('Prof Two', reload(applicant.Id).Recommender2_Name__c, 'The optional recommender typed so far is kept');
        System.assertEquals(false, reload(applicant.Id).Scholarship_Complete__c);
    }

    @IsTest
    static void submitApplication_pendingRecommenderRequestCannotBeSent_blocksTheSubmission() {
        Scholarship__c scholarship = scholarshipByName(NAME_RECOMMENDERS);
        Scholarship_Applicant__c applicant = createApplicant(scholarship, true);

        Test.startTest();
        // No email template is set on this scholarship, so the pending request cannot be sent.
        ScholarshipAppPage2LwcController.SaveResult result = submit(scholarship, new Map<String, String>(), null,
                new Map<String, String>{'name1' => 'Dr One', 'email1' => 'one@test.com'}, null);
        Test.stopTest();

        System.assertEquals(false, result.success);
        System.assert(result.message.contains('Recommender 1 Email Template Not Set'), result.message);
        System.assert(result.message.contains('Your application has not been submitted.'), result.message);
        Scholarship_Applicant__c saved = reload(applicant.Id);
        System.assertEquals('Dr One', saved.Recommender_Name__c, 'The recommender is kept so the applicant can try again');
        System.assertEquals(null, saved.Recommendation_Request_Date__c);
        System.assertEquals(false, saved.Scholarship_Complete__c);
        System.assertEquals(null, saved.Scholarship_Date_Submitted__c);
    }

    @IsTest
    static void submitApplication_optionalRecommenderWithNameAndEmail_isAlsoSentAndSoCanBlock() {
        Scholarship__c scholarship = scholarshipByName(NAME_RECOMMENDERS);
        Scholarship_Applicant__c applicant = createApplicant(scholarship, true);
        applicant.Recommender_Name__c = 'Dr One';
        applicant.Recommender_Email__c = 'one@test.com';
        applicant.Recommendation_Request_Date__c = Datetime.now().addDays(-1);
        update applicant;

        Test.startTest();
        ScholarshipAppPage2LwcController.SaveResult result = submit(scholarship, new Map<String, String>(), null,
                new Map<String, String>{'name2' => 'Prof Two', 'email2' => 'two@test.com'}, null);
        Test.stopTest();

        System.assertEquals(false, result.success);
        System.assert(result.message.contains('Recommender 2 Email Template Not Set'), result.message);
        System.assertEquals(false, reload(applicant.Id).Scholarship_Complete__c);
    }

    @IsTest
    static void submitApplication_requestsAlreadySentAndHalfFilledOptionalRecommender_dontBlock() {
        Scholarship__c scholarship = scholarshipByName(NAME_RECOMMENDERS);
        Scholarship_Applicant__c applicant = createApplicant(scholarship, true);
        applicant.Recommender_Name__c = 'Dr One';
        applicant.Recommender_Email__c = 'one@test.com';
        applicant.Recommendation_Request_Date__c = Datetime.now().addDays(-1);
        update applicant;

        Test.startTest();
        // Recommender 1 was already asked. Recommender 2 is optional and has only a name, so nothing is sent for it.
        ScholarshipAppPage2LwcController.SaveResult result = submit(scholarship, new Map<String, String>(), null,
                new Map<String, String>{'name2' => 'Prof Two'}, null);
        Test.stopTest();

        System.assertEquals(true, result.success, result.message);
        System.assertEquals(0, Limits.getEmailInvocations());
        Scholarship_Applicant__c saved = reload(applicant.Id);
        System.assertEquals(true, saved.Scholarship_Complete__c);
        System.assertEquals(null, saved.Recommendation2_Request_Date__c);
    }

    @IsTest
    static void submitApplication_completionStatement_needsTheInitials() {
        Scholarship__c scholarship = scholarshipByName(NAME_STATEMENT);
        Scholarship_Applicant__c applicant = createApplicant(scholarship, true);

        Test.startTest();
        ScholarshipAppPage2LwcController.SaveResult missing = submit(scholarship, new Map<String, String>(), null, null, null);
        ScholarshipAppPage2LwcController.SaveResult blank = submit(scholarship, new Map<String, String>(), null, null, '   ');
        ScholarshipAppPage2LwcController.SaveResult signed = submit(scholarship, new Map<String, String>(), null, null, ' AB ');
        Test.stopTest();

        System.assertEquals(false, missing.success);
        System.assertEquals(new List<String>{'signature'}, missing.invalidFields);
        System.assertEquals(false, blank.success);
        System.assertEquals(true, signed.success, signed.message);
        Scholarship_Applicant__c saved = reload(applicant.Id);
        System.assertEquals('AB', saved.Signature__c);
        System.assertEquals(true, saved.Scholarship_Complete__c);
    }

    @IsTest
    static void submitApplication_initialsSavedEarlier_areEnough() {
        Scholarship__c scholarship = scholarshipByName(NAME_STATEMENT);
        Scholarship_Applicant__c applicant = createApplicant(scholarship, true);
        applicant.Signature__c = 'AB';
        update applicant;

        Test.startTest();
        ScholarshipAppPage2LwcController.SaveResult result = submit(scholarship, new Map<String, String>(), null, null, null);
        Test.stopTest();

        System.assertEquals(true, result.success, result.message);
    }

    @IsTest
    static void submitApplication_everythingIncomplete_reportsEveryField() {
        Scholarship__c scholarship = scholarshipByName(NAME_EVERYTHING);
        createApplicant(scholarship, true);

        Test.startTest();
        ScholarshipAppPage2LwcController.SaveResult result = submit(scholarship, new Map<String, String>(), null, null, null);
        Test.stopTest();

        System.assertEquals(false, result.success);
        System.assertEquals(new List<String>{'question:1', 'essay:1', 'recommender:1:name', 'recommender:1:email', 'signature'}, result.invalidFields);
    }

    @IsTest
    static void submitApplication_invalidValueInTheSave_stopsBeforeAnyCheck() {
        Scholarship__c scholarship = scholarshipByName(NAME_RECOMMENDERS);
        Scholarship_Applicant__c applicant = createApplicant(scholarship, true);

        Test.startTest();
        ScholarshipAppPage2LwcController.SaveResult result = submit(scholarship, new Map<String, String>(), null,
                new Map<String, String>{'name1' => 'Dr One', 'email1' => 'not an email'}, null);
        Test.stopTest();

        System.assertEquals(false, result.success);
        System.assert(result.message.contains('valid email'), result.message);
        System.assertEquals(false, reload(applicant.Id).Scholarship_Complete__c);
    }

    @IsTest
    static void submitApplication_cannotBeSubmittedTwice() {
        Scholarship__c scholarship = scholarshipByName(NAME_NO_QUESTIONS);
        createApplicant(scholarship, true);

        Test.startTest();
        ScholarshipAppPage2LwcController.SaveResult first = submit(scholarship, new Map<String, String>(), null, null, null);
        ScholarshipAppPage2LwcController.SaveResult second = submit(scholarship, new Map<String, String>(), null, null, null);
        Test.stopTest();

        System.assertEquals(true, first.success, first.message);
        System.assertEquals(false, second.success);
        System.assertEquals(ScholarshipLwcService.STATUS_COMPLETE, second.status);
    }

    @IsTest
    static void submitApplication_closedScholarshipOrNoApplicant_isRejected() {
        Scholarship__c closed = scholarshipByName(NAME_CLOSED);
        Scholarship__c noApplicant = scholarshipByName(NAME_NO_QUESTIONS);
        Scholarship_Applicant__c closedApplicant = createApplicant(closed, true);

        Test.startTest();
        ScholarshipAppPage2LwcController.SaveResult resultClosed = submit(closed, new Map<String, String>(), null, null, null);
        ScholarshipAppPage2LwcController.SaveResult resultNoApplicant = submit(noApplicant, new Map<String, String>(), null, null, null);
        Test.stopTest();

        System.assertEquals(ScholarshipLwcService.STATUS_CLOSED, resultClosed.status);
        System.assertEquals(false, resultClosed.success);
        System.assertEquals(ScholarshipAppPage2LwcController.STATUS_CRITERIA_REQUIRED, resultNoApplicant.status);
        System.assertEquals(false, resultNoApplicant.success);
        System.assertEquals(false, reload(closedApplicant.Id).Scholarship_Complete__c);
    }

    @IsTest
    static void submitApplication_publicEntryPoint_refusesUnknownScholarshipAndUsersWithoutContact() {
        Scholarship__c scholarship = scholarshipByName(NAME_NO_QUESTIONS);
        Scholarship_Applicant__c applicant = createApplicant(scholarship, true);

        Test.startTest();
        ScholarshipAppPage2LwcController.SaveResult unknown = ScholarshipAppPage2LwcController.submitApplication(
                'does-not-exist', new Map<String, String>(), null, null, null);
        // The running test user has no Contact, so another contact's applicant must not be submitted.
        ScholarshipAppPage2LwcController.SaveResult noContact = ScholarshipAppPage2LwcController.submitApplication(
                scholarship.Scholarship_ID__c, new Map<String, String>(), null, null, null);
        Test.stopTest();

        System.assertEquals(ScholarshipLwcService.STATUS_NOT_FOUND, unknown.status);
        System.assertEquals(false, unknown.success);
        System.assertEquals(false, noContact.success);
        System.assertEquals(false, reload(applicant.Id).Scholarship_Complete__c);
    }

    @IsTest
    static void submitApplication_validSetup_sendsPendingRequestsAndTheConfirmation() {
        List<OrgWideEmailAddress> senders = [SELECT Id FROM OrgWideEmailAddress LIMIT 1];
        if (senders.isEmpty()) {
            return; // The org has no organization-wide email address to send from, so the sends cannot be tested.
        }
        EmailTemplate template = new EmailTemplate(
                Name = 'P2 Lwc Submit Test',
                DeveloperName = 'P2_Lwc_Submit_Test',
                TemplateType = 'text',
                FolderId = UserInfo.getUserId(),
                Subject = 'Test subject',
                Body = 'Test body'
        );
        insert template;
        Scholarship__c scholarship = scholarshipByName(NAME_RECOMMENDERS);
        update new Scholarship__c(Id = scholarship.Id,
                Recommender_Email_Template_Id__c = template.Id,
                Recommender2_Email_Template_Id__c = template.Id,
                Submit_Scholarship_Email_Template_Id__c = template.Id,
                Org_Wide_Email_Id__c = senders[0].Id);
        Scholarship_Applicant__c applicant = createApplicant(scholarship, true);

        Test.startTest();
        ScholarshipAppPage2LwcController.SaveResult result = submit(scholarship, new Map<String, String>(), null, new Map<String, String>{
                'name1' => 'Dr One', 'email1' => 'one@test.com', 'name2' => 'Prof Two', 'email2' => 'two@test.com'
        }, null);
        Test.stopTest();

        System.assertEquals(true, result.success, result.message);
        System.assertEquals(false, result.submitEmailFailed);
        System.assertEquals(3, Limits.getEmailInvocations(), 'Two recommender requests and the confirmation');
        Scholarship_Applicant__c saved = reload(applicant.Id);
        System.assertNotEquals(null, saved.Recommendation_Request_Date__c);
        System.assertNotEquals(null, saved.Recommendation2_Request_Date__c);
        System.assertEquals(true, saved.Scholarship_Complete__c);
        System.assertEquals('Submitted App', saved.Scholarship_Status__c);
    }
}