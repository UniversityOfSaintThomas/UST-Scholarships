@IsTest
private class ScholarshipLwcService_TEST {

    private static final String NAME_OPEN = 'LWC Svc Open';
    private static final String NAME_CLOSED = 'LWC Svc Closed';
    private static final String NAME_NOT_YET_OPEN = 'LWC Svc Not Yet Open';

    @TestSetup
    static void setup() {
        List<Scholarship__c> scholarships = new List<Scholarship__c>{
                new Scholarship__c(Name = NAME_OPEN, Open_Date__c = Date.today().addDays(-3), Close_Date__c = Date.today().addDays(3)),
                new Scholarship__c(Name = NAME_CLOSED, Open_Date__c = Date.today().addDays(-3), Close_Date__c = Date.today().addDays(-2)),
                new Scholarship__c(Name = NAME_NOT_YET_OPEN, Open_Date__c = Date.today().addDays(2), Close_Date__c = Date.today().addDays(3))
        };
        insert scholarships;

        Account testAccount = new Account(Name = 'LWC Svc Test Account');
        insert testAccount;

        insert new Contact(
                FirstName = 'Lwc',
                LastName = 'Student',
                Email = 'lwc.student@test.com',
                AccountId = testAccount.Id
        );
    }

    private static Scholarship__c scholarshipByName(String name) {
        return [SELECT Id, Name, Scholarship_ID__c FROM Scholarship__c WHERE Name = :name LIMIT 1];
    }

    private static Contact student() {
        return [SELECT Id FROM Contact WHERE LastName = 'Student' LIMIT 1];
    }

    private static Scholarship_Applicant__c createApplicant(Id scholarshipId, Id contactId, Boolean complete) {
        Scholarship_Applicant__c applicant = new Scholarship_Applicant__c(
                Scholarship__c = scholarshipId,
                Contact__c = contactId,
                Scholarship_Complete__c = complete
        );
        insert applicant;
        return applicant;
    }

    // ---- getScholarshipInfo ----

    @IsTest
    static void getScholarshipInfo_knownSid_returnsScholarship() {
        Scholarship__c expected = scholarshipByName(NAME_OPEN);

        Test.startTest();
        Scholarship__c actual = ScholarshipLwcService.getScholarshipInfo(expected.Scholarship_ID__c);
        Test.stopTest();

        System.assertNotEquals(null, actual);
        System.assertEquals(expected.Id, actual.Id);
    }

    @IsTest
    static void getScholarshipInfo_blankOrUnknownSid_returnsNull() {
        Test.startTest();
        System.assertEquals(null, ScholarshipLwcService.getScholarshipInfo(null));
        System.assertEquals(null, ScholarshipLwcService.getScholarshipInfo(''));
        System.assertEquals(null, ScholarshipLwcService.getScholarshipInfo('Scholarship-9999999'));
        Test.stopTest();
    }

    // ---- evaluateAccess / getAccessStatus ----

    @IsTest
    static void evaluateAccess_openScholarship_noApplicant_isOpen() {
        Scholarship__c scholarship = scholarshipByName(NAME_OPEN);

        Test.startTest();
        ScholarshipLwcService.AccessResult result = ScholarshipLwcService.evaluateAccess(scholarship.Scholarship_ID__c, student().Id);
        Test.stopTest();

        System.assertEquals(ScholarshipLwcService.STATUS_OPEN, result.status);
        System.assertEquals(scholarship.Id, result.scholarshipRecordId);
        System.assertEquals(NAME_OPEN, result.scholarshipName);
        System.assertNotEquals(null, result.displayOpenDateTime);
        System.assertNotEquals(null, result.displayCloseDateTime);
    }

    @IsTest
    static void evaluateAccess_openScholarship_incompleteApplicant_isOpen() {
        Scholarship__c scholarship = scholarshipByName(NAME_OPEN);
        createApplicant(scholarship.Id, student().Id, false);

        Test.startTest();
        ScholarshipLwcService.AccessResult result = ScholarshipLwcService.evaluateAccess(scholarship.Scholarship_ID__c, student().Id);
        Test.stopTest();

        System.assertEquals(ScholarshipLwcService.STATUS_OPEN, result.status);
    }

    @IsTest
    static void evaluateAccess_closedScholarship_isClosed() {
        Scholarship__c scholarship = scholarshipByName(NAME_CLOSED);

        Test.startTest();
        ScholarshipLwcService.AccessResult result = ScholarshipLwcService.evaluateAccess(scholarship.Scholarship_ID__c, student().Id);
        Test.stopTest();

        System.assertEquals(ScholarshipLwcService.STATUS_CLOSED, result.status);
    }

    @IsTest
    static void evaluateAccess_notYetOpenScholarship_isNotYetOpen() {
        Scholarship__c scholarship = scholarshipByName(NAME_NOT_YET_OPEN);

        Test.startTest();
        ScholarshipLwcService.AccessResult result = ScholarshipLwcService.evaluateAccess(scholarship.Scholarship_ID__c, student().Id);
        Test.stopTest();

        System.assertEquals(ScholarshipLwcService.STATUS_NOT_YET_OPEN, result.status);
    }

    @IsTest
    static void evaluateAccess_completeApplicant_isCompleteEvenWhenOpen() {
        Scholarship__c scholarship = scholarshipByName(NAME_OPEN);
        createApplicant(scholarship.Id, student().Id, true);

        Test.startTest();
        ScholarshipLwcService.AccessResult result = ScholarshipLwcService.evaluateAccess(scholarship.Scholarship_ID__c, student().Id);
        Test.stopTest();

        System.assertEquals(ScholarshipLwcService.STATUS_COMPLETE, result.status);
    }

    @IsTest
    static void evaluateAccess_completeApplicant_isCompleteEvenWhenClosed() {
        Scholarship__c scholarship = scholarshipByName(NAME_CLOSED);
        createApplicant(scholarship.Id, student().Id, true);

        Test.startTest();
        ScholarshipLwcService.AccessResult result = ScholarshipLwcService.evaluateAccess(scholarship.Scholarship_ID__c, student().Id);
        Test.stopTest();

        System.assertEquals(ScholarshipLwcService.STATUS_COMPLETE, result.status);
    }

    @IsTest
    static void evaluateAccess_otherContactsCompleteApplicant_doesNotAffectStatus() {
        Scholarship__c scholarship = scholarshipByName(NAME_OPEN);
        Contact other = new Contact(LastName = 'Other', AccountId = [SELECT Id FROM Account LIMIT 1].Id);
        insert other;
        createApplicant(scholarship.Id, other.Id, true);

        Test.startTest();
        ScholarshipLwcService.AccessResult result = ScholarshipLwcService.evaluateAccess(scholarship.Scholarship_ID__c, student().Id);
        Test.stopTest();

        System.assertEquals(ScholarshipLwcService.STATUS_OPEN, result.status);
    }

    @IsTest
    static void evaluateAccess_missingScholarship_isNotFound() {
        Test.startTest();
        ScholarshipLwcService.AccessResult unknown = ScholarshipLwcService.evaluateAccess('Scholarship-9999999', student().Id);
        ScholarshipLwcService.AccessResult blank = ScholarshipLwcService.evaluateAccess(null, student().Id);
        Test.stopTest();

        System.assertEquals(ScholarshipLwcService.STATUS_NOT_FOUND, unknown.status);
        System.assertEquals(null, unknown.scholarshipRecordId);
        System.assertEquals(ScholarshipLwcService.STATUS_NOT_FOUND, blank.status);
    }

    @IsTest
    static void getAccessStatus_runsAsCurrentUser() {
        // The test runner is not a community user, so there is no Contact and no applicant record.
        Scholarship__c scholarship = scholarshipByName(NAME_OPEN);

        Test.startTest();
        ScholarshipLwcService.AccessResult result = ScholarshipLwcService.getAccessStatus(scholarship.Scholarship_ID__c);
        Test.stopTest();

        System.assertEquals(ScholarshipLwcService.STATUS_OPEN, result.status);
    }

    // ---- getApplicantInfo ----

    @IsTest
    static void getApplicantForContact_existingRecord_returnsIt() {
        Scholarship__c scholarship = scholarshipByName(NAME_OPEN);
        Scholarship_Applicant__c created = createApplicant(scholarship.Id, student().Id, false);

        Test.startTest();
        Scholarship_Applicant__c actual = ScholarshipLwcService.getApplicantForContact(scholarship.Id, student().Id);
        Test.stopTest();

        System.assertEquals(created.Id, actual.Id);
        System.assertEquals(student().Id, actual.Contact__c);
    }

    @IsTest
    static void getApplicantForContact_noRecord_returnsNewUnsavedRecord() {
        Scholarship__c scholarship = scholarshipByName(NAME_OPEN);

        Test.startTest();
        Scholarship_Applicant__c actual = ScholarshipLwcService.getApplicantForContact(scholarship.Id, student().Id);
        Test.stopTest();

        System.assertNotEquals(null, actual);
        System.assertEquals(null, actual.Id);
    }

    @IsTest
    static void getApplicantForContact_nullScholarship_returnsNull() {
        Test.startTest();
        System.assertEquals(null, ScholarshipLwcService.getApplicantForContact(null, student().Id));
        Test.stopTest();
    }

    @IsTest
    static void getApplicantInfo_runningUserWithoutContact_returnsNewRecord() {
        Scholarship__c scholarship = scholarshipByName(NAME_OPEN);
        createApplicant(scholarship.Id, student().Id, false);

        Test.startTest();
        Scholarship_Applicant__c actual = ScholarshipLwcService.getApplicantInfo(scholarship.Id);
        Test.stopTest();

        // The running user has no Contact, so another contact's applicant record must not be returned.
        System.assertNotEquals(null, actual);
        System.assertEquals(null, actual.Id);
    }

    // ---- isScholarshipOpen ----

    @IsTest
    static void isScholarshipOpen_delegatesToSharedUtilities() {
        Scholarship__c open = scholarshipByName(NAME_OPEN);
        Scholarship__c closed = scholarshipByName(NAME_CLOSED);
        Scholarship__c notYetOpen = scholarshipByName(NAME_NOT_YET_OPEN);

        Test.startTest();
        System.assertEquals(true, ScholarshipLwcService.isScholarshipOpen(ScholarshipLwcService.getScholarshipInfo(open.Scholarship_ID__c)));
        System.assertEquals(false, ScholarshipLwcService.isScholarshipOpen(ScholarshipLwcService.getScholarshipInfo(closed.Scholarship_ID__c)));
        System.assertEquals(false, ScholarshipLwcService.isScholarshipOpen(ScholarshipLwcService.getScholarshipInfo(notYetOpen.Scholarship_ID__c)));
        System.assertEquals(false, ScholarshipLwcService.isScholarshipOpen(null));
        Test.stopTest();
    }
}
