@IsTest
private class ScholarshipPage1Lwc_TEST {

    private static final String NAME_OPEN = 'P1 Lwc Open';
    private static final String NAME_SELF_REPORT = 'P1 Lwc Self Report';
    private static final String NAME_STARTED_EMAIL = 'P1 Lwc Started Email';
    private static final String NAME_CLOSED = 'P1 Lwc Closed';

    @TestSetup
    static void setup() {
        insert new List<Scholarship__c>{
                new Scholarship__c(Name = NAME_OPEN, Open_Date__c = Date.today().addDays(-3), Close_Date__c = Date.today().addDays(3),
                        Description__c = '<p>Description</p>', Criteria_Statement__c = '<p>Criteria</p>'),
                new Scholarship__c(Name = NAME_SELF_REPORT, Open_Date__c = Date.today().addDays(-3), Close_Date__c = Date.today().addDays(3),
                        Self_Report_ACT_GPA_Criteria__c = true),
                // Send_Started_Scholarship_Email__c is on but no template is set, so building the email fails.
                new Scholarship__c(Name = NAME_STARTED_EMAIL, Open_Date__c = Date.today().addDays(-3), Close_Date__c = Date.today().addDays(3),
                        Send_Started_Scholarship_Email__c = true),
                new Scholarship__c(Name = NAME_CLOSED, Open_Date__c = Date.today().addDays(-3), Close_Date__c = Date.today().addDays(-2))
        };

        Account testAccount = new Account(Name = 'P1 Lwc Test Account');
        insert testAccount;

        insert new Contact(FirstName = 'P1', LastName = 'Student', Email = 'p1.student@test.com', AccountId = testAccount.Id);
    }

    private static Scholarship__c scholarshipByName(String name) {
        return [SELECT Id, Name, Scholarship_ID__c FROM Scholarship__c WHERE Name = :name LIMIT 1];
    }

    private static Contact student() {
        return [SELECT Id FROM Contact WHERE LastName = 'Student' LIMIT 1];
    }

    private static List<Scholarship_Applicant__c> applicantsFor(Id scholarshipId) {
        return [
                SELECT Id, Contact__c, Confirmed_Criteria__c, Declared_GPA__c, Declared_ACT_SAT__c,
                        Scholarship_Status__c, Scholarship_Date_Started__c
                FROM Scholarship_Applicant__c
                WHERE Scholarship__c = :scholarshipId
        ];
    }

    private static ScholarshipLwcService.AccessResult accessFor(Scholarship__c scholarship) {
        return ScholarshipLwcService.evaluateAccess(scholarship.Scholarship_ID__c, student().Id);
    }

    private static ScholarshipAppPage1LwcController.SaveResult save(Scholarship__c scholarship, Decimal gpa, Decimal actSat, Boolean confirmed) {
        return ScholarshipAppPage1LwcController.saveCriteriaForContact(
                scholarship.Scholarship_ID__c, gpa, actSat, confirmed, student().Id, accessFor(scholarship));
    }

    // ---- getPageData ----

    @IsTest
    static void getPageData_unknownSid_returnsNotFound() {
        Test.startTest();
        ScholarshipAppPage1LwcController.PageData data = ScholarshipAppPage1LwcController.getPageData('does-not-exist');
        Test.stopTest();

        System.assertEquals(ScholarshipLwcService.STATUS_NOT_FOUND, data.status);
        System.assertEquals(null, data.scholarshipName);
    }

    @IsTest
    static void getPageData_blankSid_returnsNotFound() {
        Test.startTest();
        ScholarshipAppPage1LwcController.PageData data = ScholarshipAppPage1LwcController.getPageData(null);
        Test.stopTest();

        System.assertEquals(ScholarshipLwcService.STATUS_NOT_FOUND, data.status);
    }

    @IsTest
    static void buildPageData_openScholarship_returnsContentAndNoApplicantValues() {
        Scholarship__c scholarship = scholarshipByName(NAME_OPEN);

        Test.startTest();
        ScholarshipAppPage1LwcController.PageData data = ScholarshipAppPage1LwcController.buildPageData(
                scholarship.Scholarship_ID__c, student().Id, accessFor(scholarship));
        Test.stopTest();

        System.assertEquals(ScholarshipLwcService.STATUS_OPEN, data.status);
        System.assertEquals(NAME_OPEN, data.scholarshipName);
        System.assertEquals('<p>Description</p>', data.description);
        System.assertEquals('<p>Criteria</p>', data.criteriaStatement);
        System.assertEquals(false, data.selfReportRequired);
        System.assertEquals(false, data.confirmedCriteria);
        System.assertEquals(null, data.declaredGpa);
        System.assertEquals(null, data.declaredActSat);
    }

    @IsTest
    static void buildPageData_selfReportScholarship_flagsSelfReport() {
        Scholarship__c scholarship = scholarshipByName(NAME_SELF_REPORT);

        Test.startTest();
        ScholarshipAppPage1LwcController.PageData data = ScholarshipAppPage1LwcController.buildPageData(
                scholarship.Scholarship_ID__c, student().Id, accessFor(scholarship));
        Test.stopTest();

        System.assertEquals(true, data.selfReportRequired);
    }

    @IsTest
    static void buildPageData_existingApplicant_returnsSavedValues() {
        Scholarship__c scholarship = scholarshipByName(NAME_SELF_REPORT);
        insert new Scholarship_Applicant__c(
                Scholarship__c = scholarship.Id,
                Contact__c = student().Id,
                Confirmed_Criteria__c = true,
                Declared_GPA__c = 3.5,
                Declared_ACT_SAT__c = 27
        );

        Test.startTest();
        ScholarshipAppPage1LwcController.PageData data = ScholarshipAppPage1LwcController.buildPageData(
                scholarship.Scholarship_ID__c, student().Id, accessFor(scholarship));
        Test.stopTest();

        System.assertEquals(true, data.confirmedCriteria);
        System.assertEquals(3.5, data.declaredGpa);
        System.assertEquals(27, data.declaredActSat);
    }

    @IsTest
    static void buildPageData_closedScholarship_returnsClosedWithoutApplicantValues() {
        Scholarship__c scholarship = scholarshipByName(NAME_CLOSED);

        Test.startTest();
        ScholarshipAppPage1LwcController.PageData data = ScholarshipAppPage1LwcController.buildPageData(
                scholarship.Scholarship_ID__c, student().Id, accessFor(scholarship));
        Test.stopTest();

        System.assertEquals(ScholarshipLwcService.STATUS_CLOSED, data.status);
        System.assertEquals(NAME_CLOSED, data.scholarshipName);
        System.assertEquals(0, data.configWarnings.size());
    }

    @IsTest
    static void buildPageData_completedApplication_returnsComplete() {
        Scholarship__c scholarship = scholarshipByName(NAME_OPEN);
        insert new Scholarship_Applicant__c(Scholarship__c = scholarship.Id, Contact__c = student().Id, Scholarship_Complete__c = true);

        Test.startTest();
        ScholarshipAppPage1LwcController.PageData data = ScholarshipAppPage1LwcController.buildPageData(
                scholarship.Scholarship_ID__c, student().Id, accessFor(scholarship));
        Test.stopTest();

        System.assertEquals(ScholarshipLwcService.STATUS_COMPLETE, data.status);
    }

    @IsTest
    static void buildPageData_noContact_doesNotLoadApplicantValues() {
        Scholarship__c scholarship = scholarshipByName(NAME_OPEN);
        // Another contact's applicant record must never be handed to a user who has no Contact.
        insert new Scholarship_Applicant__c(Scholarship__c = scholarship.Id, Contact__c = student().Id, Declared_GPA__c = 3.9, Confirmed_Criteria__c = true);

        Test.startTest();
        ScholarshipAppPage1LwcController.PageData data = ScholarshipAppPage1LwcController.buildPageData(
                scholarship.Scholarship_ID__c, null, accessFor(scholarship));
        Test.stopTest();

        System.assertEquals(false, data.confirmedCriteria);
        System.assertEquals(null, data.declaredGpa);
    }

    // ---- saveCriteria ----

    @IsTest
    static void saveCriteria_unknownSid_returnsNotFound() {
        Test.startTest();
        ScholarshipAppPage1LwcController.SaveResult result = ScholarshipAppPage1LwcController.saveCriteria('does-not-exist', null, null, true);
        Test.stopTest();

        System.assertEquals(false, result.success);
        System.assertEquals(ScholarshipLwcService.STATUS_NOT_FOUND, result.status);
    }

    @IsTest
    static void saveCriteria_newApplicant_createsStartedApplicant() {
        Scholarship__c scholarship = scholarshipByName(NAME_OPEN);

        Test.startTest();
        ScholarshipAppPage1LwcController.SaveResult result = save(scholarship, null, null, true);
        Test.stopTest();

        System.assertEquals(true, result.success, result.message);
        System.assertEquals(ScholarshipLwcService.STATUS_OPEN, result.status);
        System.assertEquals(false, result.startedEmailFailed);

        List<Scholarship_Applicant__c> applicants = applicantsFor(scholarship.Id);
        System.assertEquals(1, applicants.size());
        System.assertEquals(student().Id, applicants[0].Contact__c);
        System.assertEquals(true, applicants[0].Confirmed_Criteria__c);
        System.assertEquals(ScholarshipAppPage1LwcController.APPLICANT_STATUS_STARTED, applicants[0].Scholarship_Status__c);
        System.assertNotEquals(null, applicants[0].Scholarship_Date_Started__c);
    }

    @IsTest
    static void saveCriteria_selfReport_savesDeclaredValues() {
        Scholarship__c scholarship = scholarshipByName(NAME_SELF_REPORT);

        Test.startTest();
        ScholarshipAppPage1LwcController.SaveResult result = save(scholarship, 3.5, 27, true);
        Test.stopTest();

        System.assertEquals(true, result.success, result.message);
        List<Scholarship_Applicant__c> applicants = applicantsFor(scholarship.Id);
        System.assertEquals(1, applicants.size());
        System.assertEquals(3.5, applicants[0].Declared_GPA__c);
        System.assertEquals(27, applicants[0].Declared_ACT_SAT__c);
    }

    @IsTest
    static void saveCriteria_selfReportNotRequired_ignoresDeclaredValuesFromClient() {
        Scholarship__c scholarship = scholarshipByName(NAME_OPEN);

        Test.startTest();
        ScholarshipAppPage1LwcController.SaveResult result = save(scholarship, 3.5, 27, true);
        Test.stopTest();

        System.assertEquals(true, result.success, result.message);
        List<Scholarship_Applicant__c> applicants = applicantsFor(scholarship.Id);
        System.assertEquals(null, applicants[0].Declared_GPA__c);
        System.assertEquals(null, applicants[0].Declared_ACT_SAT__c);
    }

    @IsTest
    static void saveCriteria_existingApplicant_updatesWithoutChangingStartDate() {
        Scholarship__c scholarship = scholarshipByName(NAME_SELF_REPORT);
        Datetime started = Datetime.now().addDays(-2);
        insert new Scholarship_Applicant__c(
                Scholarship__c = scholarship.Id,
                Contact__c = student().Id,
                Scholarship_Date_Started__c = started,
                Declared_GPA__c = 2.0,
                Declared_ACT_SAT__c = 20
        );

        Test.startTest();
        ScholarshipAppPage1LwcController.SaveResult result = save(scholarship, 3.8, 30, true);
        Test.stopTest();

        System.assertEquals(true, result.success, result.message);
        List<Scholarship_Applicant__c> applicants = applicantsFor(scholarship.Id);
        System.assertEquals(1, applicants.size(), 'The existing applicant must be updated, not duplicated');
        System.assertEquals(3.8, applicants[0].Declared_GPA__c);
        System.assertEquals(30, applicants[0].Declared_ACT_SAT__c);
        System.assertEquals(started, applicants[0].Scholarship_Date_Started__c);
    }

    @IsTest
    static void saveCriteria_notConfirmed_doesNotSave() {
        Scholarship__c scholarship = scholarshipByName(NAME_OPEN);

        Test.startTest();
        ScholarshipAppPage1LwcController.SaveResult result = save(scholarship, null, null, false);
        Test.stopTest();

        System.assertEquals(false, result.success);
        System.assert(result.message.contains('confirm'), result.message);
        System.assertEquals(0, applicantsFor(scholarship.Id).size());
    }

    @IsTest
    static void saveCriteria_invalidSelfReportValues_doesNotSave() {
        Scholarship__c scholarship = scholarshipByName(NAME_SELF_REPORT);

        Test.startTest();
        ScholarshipAppPage1LwcController.SaveResult result = save(scholarship, 0.5, 5, true);
        Test.stopTest();

        System.assertEquals(false, result.success);
        System.assert(result.message.contains('GPA'), result.message);
        System.assert(result.message.contains('ACT/SAT'), result.message);
        System.assertEquals(0, applicantsFor(scholarship.Id).size());
    }

    @IsTest
    static void saveCriteria_closedScholarship_doesNotSave() {
        Scholarship__c scholarship = scholarshipByName(NAME_CLOSED);

        Test.startTest();
        ScholarshipAppPage1LwcController.SaveResult result = save(scholarship, null, null, true);
        Test.stopTest();

        System.assertEquals(false, result.success);
        System.assertEquals(ScholarshipLwcService.STATUS_CLOSED, result.status);
        System.assertEquals(0, applicantsFor(scholarship.Id).size());
    }

    @IsTest
    static void saveCriteria_completedApplication_doesNotSave() {
        Scholarship__c scholarship = scholarshipByName(NAME_OPEN);
        insert new Scholarship_Applicant__c(Scholarship__c = scholarship.Id, Contact__c = student().Id, Scholarship_Complete__c = true);

        Test.startTest();
        ScholarshipAppPage1LwcController.SaveResult result = save(scholarship, null, null, true);
        Test.stopTest();

        System.assertEquals(false, result.success);
        System.assertEquals(ScholarshipLwcService.STATUS_COMPLETE, result.status);
    }

    @IsTest
    static void saveCriteria_runningUserWithoutContact_doesNotSave() {
        Scholarship__c scholarship = scholarshipByName(NAME_OPEN);

        Test.startTest();
        // The running test user has no Contact, so the public entry point must refuse to save.
        ScholarshipAppPage1LwcController.SaveResult result = ScholarshipAppPage1LwcController.saveCriteria(
                scholarship.Scholarship_ID__c, null, null, true);
        Test.stopTest();

        System.assertEquals(false, result.success);
        System.assertEquals(0, applicantsFor(scholarship.Id).size());
    }

    @IsTest
    static void saveCriteria_startedEmailFailure_stillSavesAndFlagsFailure() {
        Scholarship__c scholarship = scholarshipByName(NAME_STARTED_EMAIL);

        Test.startTest();
        ScholarshipAppPage1LwcController.SaveResult result = save(scholarship, null, null, true);
        Test.stopTest();

        System.assertEquals(true, result.success, result.message);
        System.assertEquals(true, result.startedEmailFailed, 'No email template is set, so sending must fail without blocking the save');
        System.assertEquals(1, applicantsFor(scholarship.Id).size());
    }

    @IsTest
    static void saveCriteria_startedEmailOnlyAttemptedOnFirstSave() {
        Scholarship__c scholarship = scholarshipByName(NAME_STARTED_EMAIL);

        Test.startTest();
        ScholarshipAppPage1LwcController.SaveResult first = save(scholarship, null, null, true);
        ScholarshipAppPage1LwcController.SaveResult second = save(scholarship, null, null, true);
        Test.stopTest();

        System.assertEquals(true, first.startedEmailFailed, 'First save attempts the started email');
        System.assertEquals(false, second.startedEmailFailed, 'Later saves must not attempt the started email again');
        System.assertEquals(1, applicantsFor(scholarship.Id).size());
    }

    // ---- validate ----

    @IsTest
    static void validate_noSelfReport_onlyRequiresConfirmation() {
        System.assertEquals(0, ScholarshipAppPage1LwcController.validate(false, null, null, true).size());
        System.assertEquals(1, ScholarshipAppPage1LwcController.validate(false, null, null, false).size());
        System.assertEquals(1, ScholarshipAppPage1LwcController.validate(false, null, null, null).size());
    }

    @IsTest
    static void validate_selfReport_enforcesRanges() {
        System.assertEquals(0, ScholarshipAppPage1LwcController.validate(true, 3.5, 27, true).size());
        System.assertEquals(0, ScholarshipAppPage1LwcController.validate(true, 1.0, 10, true).size(), 'Lower bounds are inclusive');

        System.assertEquals(1, ScholarshipAppPage1LwcController.validate(true, null, 27, true).size());
        System.assertEquals(1, ScholarshipAppPage1LwcController.validate(true, 0.99, 27, true).size());
        System.assertEquals(1, ScholarshipAppPage1LwcController.validate(true, 10.0, 27, true).size());
        System.assertEquals(1, ScholarshipAppPage1LwcController.validate(true, 3.5, null, true).size());
        System.assertEquals(1, ScholarshipAppPage1LwcController.validate(true, 3.5, 9, true).size());
        System.assertEquals(1, ScholarshipAppPage1LwcController.validate(true, 3.5, 27.5, true).size());
        System.assertEquals(1, ScholarshipAppPage1LwcController.validate(true, 3.5, 10000, true).size());
        System.assertEquals(3, ScholarshipAppPage1LwcController.validate(true, null, null, false).size());
    }

    // ---- configWarnings ----

    @IsTest
    static void configWarnings_scholarshipRecordType_reportsMissingSetup() {
        List<RecordType> recordTypes = [
                SELECT Id
                FROM RecordType
                WHERE SobjectType = 'Scholarship__c' AND DeveloperName = 'Scholarship'
                LIMIT 1
        ];
        if (recordTypes.isEmpty()) {
            return; // The org has no 'Scholarship' record type, so there is nothing to check.
        }

        Scholarship__c incomplete = new Scholarship__c(
                RecordTypeId = recordTypes[0].Id,
                Send_Started_Scholarship_Email__c = true,
                Recommender_Option__c = 'Recommender Required',
                Recommender2_Option__c = 'Recommender2 Optional'
        );
        Scholarship__c complete = new Scholarship__c(
                RecordTypeId = recordTypes[0].Id,
                Org_Wide_Email_Id__c = 'x',
                Submit_Scholarship_Email_Template_Id__c = 'x'
        );

        Test.startTest();
        List<String> incompleteWarnings = ScholarshipAppPage1LwcController.configWarnings(incomplete);
        List<String> completeWarnings = ScholarshipAppPage1LwcController.configWarnings(complete);
        Test.stopTest();

        System.assertEquals(new List<String>{
                'Org Wide Email Not Set',
                'Started Email Template Not Set',
                'Submit Email Template Not Set',
                'Recommender 1 Email Template Not Set',
                'Recommender 2 Email Template Not Set'
        }, incompleteWarnings);
        System.assertEquals(0, completeWarnings.size());
    }

    @IsTest
    static void configWarnings_otherRecordType_returnsNoWarnings() {
        Test.startTest();
        List<String> warnings = ScholarshipAppPage1LwcController.configWarnings(new Scholarship__c());
        Test.stopTest();

        System.assertEquals(0, warnings.size());
    }
}
