@IsTest
private class ScholarshipRecommenderLwc_TEST {

    private static final String NAME_SCHOLARSHIP = 'Recommender Lwc Scholarship';

    @TestSetup
    static void setup() {
        Scholarship__c scholarship = new Scholarship__c(
                Name = NAME_SCHOLARSHIP,
                Open_Date__c = Date.today().addDays(-3),
                Close_Date__c = Date.today().addDays(3),
                Description__c = '<p>Scholarship description</p>',
                Recommender_Question__c = '<p>Question for recommender one</p>',
                Recommender2_Question__c = '<p>Question for recommender two</p>'
        );
        insert scholarship;

        Account testAccount = new Account(Name = 'Recommender Lwc Test Account');
        insert testAccount;
        Contact student = new Contact(FirstName = 'Ada', LastName = 'Student', Email = 'ada.student@test.com', AccountId = testAccount.Id);
        insert student;

        // Both requests were sent.
        insert new Scholarship_Applicant__c(
                Scholarship__c = scholarship.Id,
                Contact__c = student.Id,
                Recommender_Name__c = 'Dr One',
                Recommender_Email__c = 'one@test.com',
                Recommendation_Request_Date__c = Datetime.now().addDays(-2),
                Recommender2_Name__c = 'Prof Two',
                Recommender2_Email__c = 'two@test.com',
                Recommendation2_Request_Date__c = Datetime.now().addDays(-2)
        );
    }

    private static Scholarship_Applicant__c applicant() {
        return reload([SELECT Id FROM Scholarship_Applicant__c LIMIT 1].Id);
    }

    private static Scholarship_Applicant__c reload(Id applicantId) {
        return [
                SELECT Id, Recommender_Name__c, Recommender2_Name__c, Recommender_Email__c, Recommender2_Email__c,
                        Recommendation__c, Recommendation2__c, Recommendation_Received__c, Recommendation2_Received__c,
                        Recommendation_Request_Date__c, Recommendation2_Request_Date__c
                FROM Scholarship_Applicant__c
                WHERE Id = :applicantId
        ];
    }

    /**
     * The link the emails contain: the applicant's 18-character Id followed by the recommender number.
     *
     * @param applicant The applicant the request is for.
     * @param recommenderNumber 1 or 2.
     * @return The value of "recId" in the emailed link.
     */
    private static String linkFor(Scholarship_Applicant__c applicant, Integer recommenderNumber) {
        return String.valueOf(applicant.Id) + recommenderNumber;
    }

    // ---- opening the link ----

    @IsTest
    static void getRecommendationRequest_firstRecommender_returnsTheRequest() {
        Scholarship_Applicant__c applicant = applicant();

        Test.startTest();
        ScholarshipRecommenderLwcController.PageData data = ScholarshipRecommenderLwcController.getRecommendationRequest(linkFor(applicant, 1));
        Test.stopTest();

        System.assertEquals(ScholarshipRecommenderLwcController.STATUS_READY, data.status);
        System.assertEquals(NAME_SCHOLARSHIP, data.scholarshipName);
        System.assertEquals('Ada Student', data.applicantName);
        System.assertEquals('Dr One', data.recommenderName);
        System.assertEquals('<p>Scholarship description</p>', data.scholarshipDescriptionHtml);
        System.assertEquals('<p>Question for recommender one</p>', data.questionHtml);
        System.assertEquals(null, data.recommendationHtml);
    }

    @IsTest
    static void getRecommendationRequest_secondRecommender_returnsTheSecondRecommendersDetails() {
        Scholarship_Applicant__c applicant = applicant();

        Test.startTest();
        ScholarshipRecommenderLwcController.PageData data = ScholarshipRecommenderLwcController.getRecommendationRequest(linkFor(applicant, 2));
        Test.stopTest();

        System.assertEquals(ScholarshipRecommenderLwcController.STATUS_READY, data.status);
        System.assertEquals('Prof Two', data.recommenderName);
        System.assertEquals('<p>Question for recommender two</p>', data.questionHtml);
    }

    @IsTest
    static void getRecommendationRequest_fifteenCharacterId_worksToo() {
        Scholarship_Applicant__c applicant = applicant();
        String shortLink = String.valueOf(applicant.Id).substring(0, 15) + '1';

        Test.startTest();
        ScholarshipRecommenderLwcController.PageData data = ScholarshipRecommenderLwcController.getRecommendationRequest(shortLink);
        Test.stopTest();

        System.assertEquals(ScholarshipRecommenderLwcController.STATUS_READY, data.status);
    }

    @IsTest
    static void getRecommendationRequest_surroundingSpaces_areIgnored() {
        Scholarship_Applicant__c applicant = applicant();

        Test.startTest();
        ScholarshipRecommenderLwcController.PageData data = ScholarshipRecommenderLwcController.getRecommendationRequest('  ' + linkFor(applicant, 1) + ' ');
        Test.stopTest();

        System.assertEquals(ScholarshipRecommenderLwcController.STATUS_READY, data.status);
    }

    @IsTest
    static void getRecommendationRequest_alreadySubmitted_returnsReceivedWithoutAllowingAnotherSubmission() {
        Scholarship_Applicant__c applicant = applicant();
        applicant.Recommendation__c = '<p>Great student</p>';
        applicant.Recommendation_Received__c = Datetime.now().addDays(-1);
        update applicant;

        Test.startTest();
        ScholarshipRecommenderLwcController.PageData first = ScholarshipRecommenderLwcController.getRecommendationRequest(linkFor(applicant, 1));
        ScholarshipRecommenderLwcController.PageData second = ScholarshipRecommenderLwcController.getRecommendationRequest(linkFor(applicant, 2));
        Test.stopTest();

        System.assertEquals(ScholarshipRecommenderLwcController.STATUS_RECEIVED, first.status);
        System.assertEquals('Ada Student', first.applicantName, 'The thank-you message names the applicant');
        System.assertEquals(ScholarshipRecommenderLwcController.STATUS_READY, second.status, 'The other recommender is independent');
    }

    @IsTest
    static void getRecommendationRequest_malformedLinks_returnNothingAboutTheApplicant() {
        Scholarship_Applicant__c applicant = applicant();
        String id18 = String.valueOf(applicant.Id);
        Contact student = [SELECT Id FROM Contact LIMIT 1];

        List<String> badLinks = new List<String>{
                null, '', '   ', '1', 'x', id18, id18 + '0', id18 + '3', id18 + 'a', id18 + '12', 'not-an-id1',
                String.valueOf(student.Id) + '1', // a real Id, but not an applicant's
                id18.substring(0, 17) + '1'      // too short to be an Id
        };

        Test.startTest();
        List<ScholarshipRecommenderLwcController.PageData> results = new List<ScholarshipRecommenderLwcController.PageData>();
        for (String badLink : badLinks) {
            results.add(ScholarshipRecommenderLwcController.getRecommendationRequest(badLink));
        }
        Test.stopTest();

        for (Integer i = 0; i < badLinks.size(); i++) {
            System.assertEquals(ScholarshipRecommenderLwcController.STATUS_INVALID_LINK, results[i].status, 'Link: ' + badLinks[i]);
            System.assertEquals(null, results[i].scholarshipName, 'Link: ' + badLinks[i]);
            System.assertEquals(null, results[i].applicantName, 'Link: ' + badLinks[i]);
        }
    }

    @IsTest
    static void getRecommendationRequest_applicantThatDoesNotExist_isInvalid() {
        Scholarship_Applicant__c applicant = applicant();
        String link = linkFor(applicant, 1);
        delete applicant;

        Test.startTest();
        ScholarshipRecommenderLwcController.PageData data = ScholarshipRecommenderLwcController.getRecommendationRequest(link);
        Test.stopTest();

        System.assertEquals(ScholarshipRecommenderLwcController.STATUS_INVALID_LINK, data.status);
        System.assertEquals(null, data.scholarshipName);
    }

    @IsTest
    static void getRecommendationRequest_requestNeverSent_isInvalidAndRevealsNothing() {
        Scholarship_Applicant__c applicant = applicant();
        applicant.Recommendation2_Request_Date__c = null;
        update applicant;

        Test.startTest();
        ScholarshipRecommenderLwcController.PageData notSent = ScholarshipRecommenderLwcController.getRecommendationRequest(linkFor(applicant, 2));
        ScholarshipRecommenderLwcController.PageData sent = ScholarshipRecommenderLwcController.getRecommendationRequest(linkFor(applicant, 1));
        Test.stopTest();

        System.assertEquals(ScholarshipRecommenderLwcController.STATUS_INVALID_LINK, notSent.status);
        System.assertEquals(null, notSent.applicantName);
        System.assertEquals(null, notSent.recommenderName);
        System.assertEquals(ScholarshipRecommenderLwcController.STATUS_READY, sent.status);
    }

    // ---- submitting ----

    @IsTest
    static void submitRecommendation_firstRecommender_savesTheTextAndTheReceivedTime() {
        Scholarship_Applicant__c applicant = applicant();

        Test.startTest();
        ScholarshipRecommenderLwcController.SaveResult result = ScholarshipRecommenderLwcController.submitRecommendation(
                linkFor(applicant, 1), '<p>An excellent student.</p>');
        Test.stopTest();

        System.assertEquals(true, result.success, result.message);
        System.assertEquals(ScholarshipRecommenderLwcController.STATUS_RECEIVED, result.status);
        Scholarship_Applicant__c saved = reload(applicant.Id);
        System.assertEquals('<p>An excellent student.</p>', saved.Recommendation__c);
        System.assertNotEquals(null, saved.Recommendation_Received__c);
        System.assertEquals(null, saved.Recommendation2__c, 'The other recommender is untouched');
        System.assertEquals(null, saved.Recommendation2_Received__c);
    }

    @IsTest
    static void submitRecommendation_secondRecommender_savesOnlyTheSecondRecommendersFields() {
        Scholarship_Applicant__c applicant = applicant();

        Test.startTest();
        ScholarshipRecommenderLwcController.SaveResult result = ScholarshipRecommenderLwcController.submitRecommendation(
                linkFor(applicant, 2), '<p>Hard working.</p>');
        Test.stopTest();

        System.assertEquals(true, result.success, result.message);
        Scholarship_Applicant__c saved = reload(applicant.Id);
        System.assertEquals('<p>Hard working.</p>', saved.Recommendation2__c);
        System.assertNotEquals(null, saved.Recommendation2_Received__c);
        System.assertEquals(null, saved.Recommendation__c);
        System.assertEquals(null, saved.Recommendation_Received__c);
    }

    @IsTest
    static void submitRecommendation_bothRecommenders_areIndependent() {
        Scholarship_Applicant__c applicant = applicant();

        Test.startTest();
        ScholarshipRecommenderLwcController.SaveResult first = ScholarshipRecommenderLwcController.submitRecommendation(linkFor(applicant, 1), '<p>One</p>');
        ScholarshipRecommenderLwcController.SaveResult second = ScholarshipRecommenderLwcController.submitRecommendation(linkFor(applicant, 2), '<p>Two</p>');
        Test.stopTest();

        System.assertEquals(true, first.success, first.message);
        System.assertEquals(true, second.success, second.message);
        Scholarship_Applicant__c saved = reload(applicant.Id);
        System.assertEquals('<p>One</p>', saved.Recommendation__c);
        System.assertEquals('<p>Two</p>', saved.Recommendation2__c);
    }

    @IsTest
    static void submitRecommendation_doesNotChangeAnythingElseOnTheApplicant() {
        Scholarship_Applicant__c applicant = applicant();

        Test.startTest();
        ScholarshipRecommenderLwcController.submitRecommendation(linkFor(applicant, 1), '<p>Text</p>');
        Test.stopTest();

        Scholarship_Applicant__c saved = reload(applicant.Id);
        System.assertEquals('Dr One', saved.Recommender_Name__c);
        System.assertEquals('one@test.com', saved.Recommender_Email__c);
        System.assertEquals('Prof Two', saved.Recommender2_Name__c);
        System.assertEquals(applicant.Recommendation_Request_Date__c, saved.Recommendation_Request_Date__c);
        System.assertEquals(applicant.Recommendation2_Request_Date__c, saved.Recommendation2_Request_Date__c);
    }

    @IsTest
    static void submitRecommendation_secondAttempt_isRefusedAndKeepsTheFirstText() {
        Scholarship_Applicant__c applicant = applicant();
        String link = linkFor(applicant, 1);

        Test.startTest();
        ScholarshipRecommenderLwcController.SaveResult first = ScholarshipRecommenderLwcController.submitRecommendation(link, '<p>First version</p>');
        Datetime receivedAt = reload(applicant.Id).Recommendation_Received__c;
        ScholarshipRecommenderLwcController.SaveResult second = ScholarshipRecommenderLwcController.submitRecommendation(link, '<p>Overwritten</p>');
        Test.stopTest();

        System.assertEquals(true, first.success, first.message);
        System.assertEquals(false, second.success);
        System.assertEquals(ScholarshipRecommenderLwcController.STATUS_RECEIVED, second.status);
        System.assert(second.message.contains('already been submitted'), second.message);
        Scholarship_Applicant__c saved = reload(applicant.Id);
        System.assertEquals('<p>First version</p>', saved.Recommendation__c);
        System.assertEquals(receivedAt, saved.Recommendation_Received__c);
    }

    @IsTest
    static void submitRecommendation_emptyRecommendation_isRefusedAndLeavesTheRequestOpen() {
        Scholarship_Applicant__c applicant = applicant();
        String link = linkFor(applicant, 1);

        Test.startTest();
        List<ScholarshipRecommenderLwcController.SaveResult> results = new List<ScholarshipRecommenderLwcController.SaveResult>{
                ScholarshipRecommenderLwcController.submitRecommendation(link, null),
                ScholarshipRecommenderLwcController.submitRecommendation(link, ''),
                ScholarshipRecommenderLwcController.submitRecommendation(link, '   '),
                ScholarshipRecommenderLwcController.submitRecommendation(link, '<p><br></p>'),
                ScholarshipRecommenderLwcController.submitRecommendation(link, '<p>&nbsp;</p>')
        };
        Test.stopTest();

        for (ScholarshipRecommenderLwcController.SaveResult result : results) {
            System.assertEquals(false, result.success);
            System.assertEquals(ScholarshipRecommenderLwcController.STATUS_READY, result.status);
            System.assert(result.message.contains('enter your recommendation'), result.message);
        }
        System.assertEquals(null, reload(applicant.Id).Recommendation_Received__c, 'An empty submission must not use up the one chance');
    }

    @IsTest
    static void submitRecommendation_tooLong_isRefused() {
        Scholarship_Applicant__c applicant = applicant();

        Test.startTest();
        ScholarshipRecommenderLwcController.SaveResult result = ScholarshipRecommenderLwcController.submitRecommendation(
                linkFor(applicant, 1), 'a'.repeat(ScholarshipRecommenderLwcController.MAX_RECOMMENDATION_LENGTH + 1));
        ScholarshipRecommenderLwcController.SaveResult atLimit = ScholarshipRecommenderLwcController.submitRecommendation(
                linkFor(applicant, 2), 'a'.repeat(ScholarshipRecommenderLwcController.MAX_RECOMMENDATION_LENGTH));
        Test.stopTest();

        System.assertEquals(false, result.success);
        System.assert(result.message.contains('too long'), result.message);
        System.assertEquals(null, reload(applicant.Id).Recommendation__c);
        System.assertEquals(true, atLimit.success, atLimit.message);
    }

    @IsTest
    static void submitRecommendation_invalidLink_savesNothing() {
        Scholarship_Applicant__c applicant = applicant();
        String id18 = String.valueOf(applicant.Id);

        Test.startTest();
        ScholarshipRecommenderLwcController.SaveResult nullLink = ScholarshipRecommenderLwcController.submitRecommendation(null, '<p>Text</p>');
        ScholarshipRecommenderLwcController.SaveResult noNumber = ScholarshipRecommenderLwcController.submitRecommendation(id18, '<p>Text</p>');
        ScholarshipRecommenderLwcController.SaveResult badNumber = ScholarshipRecommenderLwcController.submitRecommendation(id18 + '3', '<p>Text</p>');
        Test.stopTest();

        for (ScholarshipRecommenderLwcController.SaveResult result : new List<ScholarshipRecommenderLwcController.SaveResult>{nullLink, noNumber, badNumber}) {
            System.assertEquals(false, result.success);
            System.assertEquals(ScholarshipRecommenderLwcController.STATUS_INVALID_LINK, result.status);
        }
        Scholarship_Applicant__c saved = reload(applicant.Id);
        System.assertEquals(null, saved.Recommendation__c);
        System.assertEquals(null, saved.Recommendation2__c);
    }

    @IsTest
    static void submitRecommendation_requestNeverSent_isRefused() {
        Scholarship_Applicant__c applicant = applicant();
        applicant.Recommendation_Request_Date__c = null;
        update applicant;

        Test.startTest();
        ScholarshipRecommenderLwcController.SaveResult result = ScholarshipRecommenderLwcController.submitRecommendation(
                linkFor(applicant, 1), '<p>Unsolicited</p>');
        Test.stopTest();

        System.assertEquals(false, result.success);
        System.assertEquals(ScholarshipRecommenderLwcController.STATUS_INVALID_LINK, result.status);
        System.assertEquals(null, reload(applicant.Id).Recommendation__c);
    }

    // ---- reading the link ----

    @IsTest
    static void parseLink_splitsTheApplicantIdFromTheRecommenderNumber() {
        Scholarship_Applicant__c applicant = applicant();

        ScholarshipRecommenderLwcController.RecommendationLink one = ScholarshipRecommenderLwcController.parseLink(linkFor(applicant, 1));
        ScholarshipRecommenderLwcController.RecommendationLink two = ScholarshipRecommenderLwcController.parseLink(linkFor(applicant, 2));

        System.assertEquals(applicant.Id, one.applicantId);
        System.assertEquals(1, one.recommenderNumber);
        System.assertEquals(2, two.recommenderNumber);
        System.assertEquals(null, ScholarshipRecommenderLwcController.parseLink('garbage'));
    }
}
