@IsTest
private class ScholarshipPage2Lwc_TEST {

    private static final String NAME_QUESTIONS = 'P2 Lwc Questions';
    private static final String NAME_NO_QUESTIONS = 'P2 Lwc No Questions';
    private static final String NAME_CLOSED = 'P2 Lwc Closed';

    @TestSetup
    static void setup() {
        insert new List<Scholarship__c>{
                // Questions 1 and 3 are configured; 2 and 4 are not.
                new Scholarship__c(Name = NAME_QUESTIONS, Open_Date__c = Date.today().addDays(-3), Close_Date__c = Date.today().addDays(3),
                        Question_1_Text__c = '<p>Why do you deserve it?</p>', Question_3_Text__c = '<p>Tell us more.</p>'),
                new Scholarship__c(Name = NAME_NO_QUESTIONS, Open_Date__c = Date.today().addDays(-3), Close_Date__c = Date.today().addDays(3)),
                new Scholarship__c(Name = NAME_CLOSED, Open_Date__c = Date.today().addDays(-3), Close_Date__c = Date.today().addDays(-2),
                        Question_1_Text__c = '<p>Closed question</p>')
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
                        Essay_1_Answer__c, Recommender_Name__c, Declared_GPA__c, Scholarship_Status__c
                FROM Scholarship_Applicant__c
                WHERE Id = :applicantId
        ];
    }

    private static ScholarshipLwcService.AccessResult accessFor(Scholarship__c scholarship) {
        return ScholarshipLwcService.evaluateAccess(scholarship.Scholarship_ID__c, student().Id);
    }

    private static ScholarshipAppPage2LwcController.PageData pageData(Scholarship__c scholarship) {
        return ScholarshipAppPage2LwcController.buildPageData(scholarship.Scholarship_ID__c, student().Id, accessFor(scholarship));
    }

    private static ScholarshipAppPage2LwcController.SaveResult save(Scholarship__c scholarship, Map<String, String> answers) {
        return ScholarshipAppPage2LwcController.saveAnswersForContact(scholarship.Scholarship_ID__c, answers, student().Id, accessFor(scholarship));
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
        ScholarshipAppPage2LwcController.SaveResult result = ScholarshipAppPage2LwcController.saveAnswers('does-not-exist', new Map<String, String>{'1' => 'x'});
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
                scholarship.Scholarship_ID__c, new Map<String, String>{'1' => 'Not mine'});
        Test.stopTest();

        System.assertEquals(false, result.success);
        System.assertEquals(null, reload(applicant.Id).Question_1_Answer__c);
    }
}
