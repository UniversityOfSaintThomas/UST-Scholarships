@IsTest
private class ScholarshipCompleteLwc_TEST {

    private static final String NAME_OPEN = 'Complete Lwc Open';
    private static final String NAME_CLOSED = 'Complete Lwc Closed';
    private static final String NAME_NOT_YET_OPEN = 'Complete Lwc Not Yet Open';

    @TestSetup
    static void setup() {
        insert new List<Scholarship__c>{
                new Scholarship__c(Name = NAME_OPEN, Open_Date__c = Date.today().addDays(-3), Close_Date__c = Date.today().addDays(3),
                        Review_Award_Process_Description__c = '<p>We will review your application.</p>'),
                new Scholarship__c(Name = NAME_CLOSED, Open_Date__c = Date.today().addDays(-3), Close_Date__c = Date.today().addDays(-2),
                        Review_Award_Process_Description__c = '<p>Closed review text.</p>'),
                new Scholarship__c(Name = NAME_NOT_YET_OPEN, Open_Date__c = Date.today().addDays(2), Close_Date__c = Date.today().addDays(3))
        };

        Account testAccount = new Account(Name = 'Complete Lwc Test Account');
        insert testAccount;

        insert new Contact(FirstName = 'Complete', LastName = 'Student', Email = 'complete.student@test.com', AccountId = testAccount.Id);
    }

    private static Scholarship__c scholarshipByName(String name) {
        return [SELECT Id, Name, Scholarship_ID__c FROM Scholarship__c WHERE Name = :name LIMIT 1];
    }

    private static Contact student() {
        return [SELECT Id FROM Contact WHERE LastName = 'Student' LIMIT 1];
    }

    private static Scholarship_Applicant__c createApplicant(Scholarship__c scholarship, Boolean complete) {
        Scholarship_Applicant__c applicant = new Scholarship_Applicant__c(
                Scholarship__c = scholarship.Id,
                Contact__c = student().Id,
                Confirmed_Criteria__c = true,
                Scholarship_Complete__c = complete
        );
        insert applicant;
        return applicant;
    }

    private static ScholarshipAppCompleteLwcController.PageData pageData(Scholarship__c scholarship) {
        return ScholarshipAppCompleteLwcController.buildPageData(
                scholarship.Scholarship_ID__c, student().Id, ScholarshipLwcService.evaluateAccess(scholarship.Scholarship_ID__c, student().Id));
    }

    // ---- who gets the confirmation ----

    @IsTest
    static void getPageData_unknownSid_returnsNotFound() {
        Test.startTest();
        ScholarshipAppCompleteLwcController.PageData data = ScholarshipAppCompleteLwcController.getPageData('does-not-exist');
        Test.stopTest();

        System.assertEquals(ScholarshipLwcService.STATUS_NOT_FOUND, data.status);
        System.assertEquals(null, data.scholarshipName);
    }

    @IsTest
    static void buildPageData_submittedApplication_returnsTheConfirmation() {
        Scholarship__c scholarship = scholarshipByName(NAME_OPEN);
        createApplicant(scholarship, true);

        Test.startTest();
        ScholarshipAppCompleteLwcController.PageData data = pageData(scholarship);
        Test.stopTest();

        System.assertEquals(ScholarshipLwcService.STATUS_COMPLETE, data.status);
        System.assertEquals(NAME_OPEN, data.scholarshipName);
        System.assertEquals('<p>We will review your application.</p>', data.reviewAwardProcessDescriptionHtml);
        System.assertEquals(0, data.recommenders.size());
    }

    @IsTest
    static void buildPageData_submittedApplicationForAScholarshipThatHasSinceClosed_stillShowsTheConfirmation() {
        Scholarship__c scholarship = scholarshipByName(NAME_CLOSED);
        createApplicant(scholarship, true);

        Test.startTest();
        ScholarshipAppCompleteLwcController.PageData data = pageData(scholarship);
        Test.stopTest();

        System.assertEquals(ScholarshipLwcService.STATUS_COMPLETE, data.status);
        System.assertEquals('<p>Closed review text.</p>', data.reviewAwardProcessDescriptionHtml);
    }

    @IsTest
    static void buildPageData_applicationNotSubmittedYet_returnsOnlyTheStatus() {
        Scholarship__c scholarship = scholarshipByName(NAME_OPEN);
        createApplicant(scholarship, false);

        Test.startTest();
        ScholarshipAppCompleteLwcController.PageData data = pageData(scholarship);
        Test.stopTest();

        System.assertEquals(ScholarshipLwcService.STATUS_OPEN, data.status);
        System.assertEquals(NAME_OPEN, data.scholarshipName);
        System.assertEquals(null, data.reviewAwardProcessDescriptionHtml);
        System.assertEquals(0, data.recommenders.size());
    }

    @IsTest
    static void buildPageData_noApplicationAtAll_returnsOpen() {
        Scholarship__c scholarship = scholarshipByName(NAME_OPEN);

        Test.startTest();
        ScholarshipAppCompleteLwcController.PageData data = pageData(scholarship);
        Test.stopTest();

        System.assertEquals(ScholarshipLwcService.STATUS_OPEN, data.status);
        System.assertEquals(null, data.reviewAwardProcessDescriptionHtml);
    }

    @IsTest
    static void buildPageData_unsubmittedApplicationOnAClosedOrFutureScholarship_returnsThatStatus() {
        Scholarship__c closed = scholarshipByName(NAME_CLOSED);
        Scholarship__c notYetOpen = scholarshipByName(NAME_NOT_YET_OPEN);
        createApplicant(closed, false);

        Test.startTest();
        ScholarshipAppCompleteLwcController.PageData closedData = pageData(closed);
        ScholarshipAppCompleteLwcController.PageData notYetOpenData = pageData(notYetOpen);
        Test.stopTest();

        System.assertEquals(ScholarshipLwcService.STATUS_CLOSED, closedData.status);
        System.assertEquals(null, closedData.reviewAwardProcessDescriptionHtml);
        System.assertEquals(ScholarshipLwcService.STATUS_NOT_YET_OPEN, notYetOpenData.status);
    }

    @IsTest
    static void buildPageData_contactIsNeverTakenFromTheClient_soNothingIsReturnedWithoutOne() {
        Scholarship__c scholarship = scholarshipByName(NAME_OPEN);
        Scholarship_Applicant__c applicant = createApplicant(scholarship, true);
        applicant.Recommender_Name__c = 'Dr One';
        applicant.Recommender_Email__c = 'one@test.com';
        applicant.Recommendation_Request_Date__c = Datetime.now().addDays(-1);
        update applicant;

        Test.startTest();
        // The running test user has no Contact, so another contact's confirmation must not be returned.
        ScholarshipAppCompleteLwcController.PageData data = ScholarshipAppCompleteLwcController.getPageData(scholarship.Scholarship_ID__c);
        // The same check with a COMPLETE access status but no Contact, which the real flow cannot produce.
        ScholarshipLwcService.AccessResult completeAccess = new ScholarshipLwcService.AccessResult();
        completeAccess.status = ScholarshipLwcService.STATUS_COMPLETE;
        ScholarshipAppCompleteLwcController.PageData forced = ScholarshipAppCompleteLwcController.buildPageData(scholarship.Scholarship_ID__c, null, completeAccess);
        Test.stopTest();

        System.assertNotEquals(ScholarshipLwcService.STATUS_COMPLETE, data.status);
        System.assertEquals(0, data.recommenders.size());
        System.assertEquals(null, data.reviewAwardProcessDescriptionHtml);
        System.assertEquals(ScholarshipLwcService.STATUS_OPEN, forced.status);
        System.assertEquals(0, forced.recommenders.size());
    }

    // ---- recommender request status (0, 1 or 2 requested) ----

    @IsTest
    static void buildPageData_noRecommenderRequestSent_listsNone() {
        Scholarship__c scholarship = scholarshipByName(NAME_OPEN);
        Scholarship_Applicant__c applicant = createApplicant(scholarship, true);
        // Names and emails were typed but no request was sent.
        applicant.Recommender_Name__c = 'Dr One';
        applicant.Recommender_Email__c = 'one@test.com';
        update applicant;

        Test.startTest();
        ScholarshipAppCompleteLwcController.PageData data = pageData(scholarship);
        Test.stopTest();

        System.assertEquals(0, data.recommenders.size());
    }

    @IsTest
    static void buildPageData_oneRecommenderRequested_listsOnlyThatOne() {
        Scholarship__c scholarship = scholarshipByName(NAME_OPEN);
        Scholarship_Applicant__c applicant = createApplicant(scholarship, true);
        applicant.Recommender_Name__c = 'Dr One';
        applicant.Recommender_Email__c = 'one@test.com';
        // 19:15 GMT on 3 May is 2:15 PM Central (daylight time), the same calendar day.
        applicant.Recommendation_Request_Date__c = Datetime.newInstanceGmt(2026, 5, 3, 19, 15, 0);
        applicant.Recommender2_Name__c = 'Prof Two';
        applicant.Recommender2_Email__c = 'two@test.com';
        update applicant;

        Test.startTest();
        ScholarshipAppCompleteLwcController.PageData data = pageData(scholarship);
        Test.stopTest();

        System.assertEquals(1, data.recommenders.size());
        ScholarshipAppCompleteLwcController.RecommenderStatus first = data.recommenders[0];
        System.assertEquals(1, first.recommenderNumber);
        System.assertEquals('Dr One', first.name);
        System.assertEquals('one@test.com', first.email);
        System.assertEquals('05/03/2026', first.requestedOn);
        System.assertEquals(ScholarshipAppCompleteLwcController.STATUS_UNOPENED, first.status);
    }

    @IsTest
    static void buildPageData_onlyTheSecondRecommenderRequested_listsOnlyTheSecond() {
        Scholarship__c scholarship = scholarshipByName(NAME_OPEN);
        Scholarship_Applicant__c applicant = createApplicant(scholarship, true);
        applicant.Recommender2_Name__c = 'Prof Two';
        applicant.Recommender2_Email__c = 'two@test.com';
        applicant.Recommendation2_Request_Date__c = Datetime.newInstanceGmt(2026, 1, 15, 18, 0, 0);
        update applicant;

        Test.startTest();
        ScholarshipAppCompleteLwcController.PageData data = pageData(scholarship);
        Test.stopTest();

        System.assertEquals(1, data.recommenders.size());
        System.assertEquals(2, data.recommenders[0].recommenderNumber);
        System.assertEquals('Prof Two', data.recommenders[0].name);
        System.assertEquals('01/15/2026', data.recommenders[0].requestedOn);
    }

    @IsTest
    static void buildPageData_bothRecommendersRequested_listsBothInOrder() {
        Scholarship__c scholarship = scholarshipByName(NAME_OPEN);
        Scholarship_Applicant__c applicant = createApplicant(scholarship, true);
        applicant.Recommender_Name__c = 'Dr One';
        applicant.Recommender_Email__c = 'one@test.com';
        applicant.Recommendation_Request_Date__c = Datetime.newInstanceGmt(2026, 5, 3, 19, 15, 0);
        applicant.Recommender2_Name__c = 'Prof Two';
        applicant.Recommender2_Email__c = 'two@test.com';
        applicant.Recommendation2_Request_Date__c = Datetime.newInstanceGmt(2026, 5, 4, 19, 15, 0);
        update applicant;

        Test.startTest();
        ScholarshipAppCompleteLwcController.PageData data = pageData(scholarship);
        Test.stopTest();

        System.assertEquals(2, data.recommenders.size());
        System.assertEquals(1, data.recommenders[0].recommenderNumber);
        System.assertEquals('05/03/2026', data.recommenders[0].requestedOn);
        System.assertEquals(2, data.recommenders[1].recommenderNumber);
        System.assertEquals('05/04/2026', data.recommenders[1].requestedOn);
        System.assertEquals(ScholarshipAppCompleteLwcController.STATUS_UNOPENED, data.recommenders[0].status);
        System.assertEquals(ScholarshipAppCompleteLwcController.STATUS_UNOPENED, data.recommenders[1].status);
    }

    @IsTest
    static void buildPageData_requestSentButNoEmailStored_isUnopened() {
        Scholarship__c scholarship = scholarshipByName(NAME_OPEN);
        Scholarship_Applicant__c applicant = createApplicant(scholarship, true);
        applicant.Recommender_Name__c = 'Dr One';
        applicant.Recommendation_Request_Date__c = Datetime.newInstanceGmt(2026, 5, 3, 19, 15, 0);
        update applicant;

        Test.startTest();
        ScholarshipAppCompleteLwcController.PageData data = pageData(scholarship);
        Test.stopTest();

        System.assertEquals(1, data.recommenders.size());
        System.assertEquals(ScholarshipAppCompleteLwcController.STATUS_UNOPENED, data.recommenders[0].status);
    }

    @IsTest
    static void buildPageData_noDescription_returnsNullDescription() {
        Scholarship__c scholarship = scholarshipByName(NAME_NOT_YET_OPEN);
        update new Scholarship__c(Id = scholarship.Id, Open_Date__c = Date.today().addDays(-1));
        createApplicant(scholarship, true);

        Test.startTest();
        ScholarshipAppCompleteLwcController.PageData data = pageData(scholarship);
        Test.stopTest();

        System.assertEquals(ScholarshipLwcService.STATUS_COMPLETE, data.status);
        System.assertEquals(null, data.reviewAwardProcessDescriptionHtml);
    }
}
