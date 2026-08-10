/**
 * ScholarshipThankYouController_TEST
 * Test class for ScholarshipThankYouController.
 * All test data is fully isolated — no SeeAllData.
 *
 * Created: 2026-03-26
 */
@isTest
private class ScholarshipThankYouController_TEST {

    // ─────────────────────────────────────────────────────────────────────────
    // Test Setup
    // ─────────────────────────────────────────────────────────────────────────

    @TestSetup
    static void makeData() {
        // Create a donor Account
        Account donorAccount = new Account(Name = 'Test Donor Foundation');
        insert donorAccount;

        // Create a Scholarship with TY required
        Scholarship__c scholarship = new Scholarship__c(
            Name                  = 'Test TY Scholarship',
            Thank_You_Required__c = 'Yes',
            Financial_Aid_Code__c = 'FA001',
            Designation_Code__c   = 'DES001',
            Scholarship_Account__c = donorAccount.Id,
            Open_Date__c          = Date.today().addDays(-10),
            Close_Date__c         = Date.today().addDays(30)
        );
        insert scholarship;

        // Create a Scholarship with no TY required
        Scholarship__c scholarshipNoTY = new Scholarship__c(
            Name                  = 'Test No TY Scholarship',
            Thank_You_Required__c = 'No',
            Open_Date__c          = Date.today().addDays(-10),
            Close_Date__c         = Date.today().addDays(30)
        );
        insert scholarshipNoTY;

        // Create a Scholarship with Optional TY
        Scholarship__c scholarshipOptionalTY = new Scholarship__c(
            Name                  = 'Test Optional TY Scholarship',
            Thank_You_Required__c = 'Optional',
            Open_Date__c          = Date.today().addDays(-10),
            Close_Date__c         = Date.today().addDays(30)
        );
        insert scholarshipOptionalTY;

        // Create a Contact for the student
        Contact student = new Contact(
            FirstName = 'Test',
            LastName  = 'Student',
            Email     = 'test.student.ty@example.com'
        );
        insert student;

        // Create an Accepted applicant for TY-required scholarship
        Scholarship_Applicant__c acceptedApp = new Scholarship_Applicant__c(
            Contact__c        = student.Id,
            Scholarship__c    = scholarship.Id,
            Scholarship_Status__c = 'Accepted',
            Thank_You_Status__c   = 'Not Started'
        );
        insert acceptedApp;

        // Create an applicant for No-TY scholarship (should NOT appear in list)
        Scholarship_Applicant__c noTYApp = new Scholarship_Applicant__c(
            Contact__c        = student.Id,
            Scholarship__c    = scholarshipNoTY.Id,
            Scholarship_Status__c = 'Accepted'
        );
        insert noTYApp;

        // Create an applicant for Optional TY scholarship
        Scholarship_Applicant__c optionalApp = new Scholarship_Applicant__c(
            Contact__c        = student.Id,
            Scholarship__c    = scholarshipOptionalTY.Id,
            Scholarship_Status__c = 'Awarded',
            Thank_You_Status__c   = 'Not Started'
        );
        insert optionalApp;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Helper: get a test contact Id
    // ─────────────────────────────────────────────────────────────────────────

    private static Id getStudentContactId() {
        return [SELECT Id FROM Contact WHERE Email = 'test.student.ty@example.com' LIMIT 1].Id;
    }

    private static Scholarship_Applicant__c getAcceptedApp() {
        return [
            SELECT Id, Scholarship__r.Name, Thank_You_Status__c, Contact__c
            FROM Scholarship_Applicant__c
            WHERE Contact__r.Email = 'test.student.ty@example.com'
              AND Scholarship__r.Thank_You_Required__c = 'Yes'
            LIMIT 1
        ];
    }

    // ─────────────────────────────────────────────────────────────────────────
    // getThankYouItems — positive path
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void testGetThankYouItems_returnsTYRequired() {
        Id contactId = getStudentContactId();

        Test.startTest();
        List<ScholarshipThankYouController.ThankYouItem> items =
            ScholarshipThankYouController.getThankYouItems(contactId);
        Test.stopTest();

        // Should return Yes + Optional but NOT No
        System.assertNotEquals(null, items, 'Items list should not be null');
        System.assertEquals(2, items.size(), 'Expected 2 TY items (Yes + Optional)');
    }

    @isTest
    static void testGetThankYouItems_itemHasExpectedFields() {
        Id contactId = getStudentContactId();

        Test.startTest();
        List<ScholarshipThankYouController.ThankYouItem> items =
            ScholarshipThankYouController.getThankYouItems(contactId);
        Test.stopTest();

        // Find the Yes-required item
        ScholarshipThankYouController.ThankYouItem tyItem = null;
        for (ScholarshipThankYouController.ThankYouItem i : items) {
            if (i.thankYouRequired == 'Yes') {
                tyItem = i;
                break;
            }
        }
        System.assertNotEquals(null, tyItem, 'TY-required item should be present');
        System.assertEquals('Test TY Scholarship', tyItem.scholarshipName);
        System.assertEquals('Test Donor Foundation', tyItem.scholarshipAccountName);
        System.assertEquals('FA001', tyItem.financialAidCode);
        System.assertEquals('DES001', tyItem.designationCode);
        System.assertEquals('Not Started', tyItem.thankYouStatus);
        System.assertEquals(false, tyItem.hasDataWarning);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // getThankYouItems — data warning
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void testGetThankYouItems_dataWarningWhenMissingFACode() {
        // Create a scholarship missing FA code
        Scholarship__c s = new Scholarship__c(
            Name                  = 'No FA Code Scholarship',
            Thank_You_Required__c = 'Yes',
            Open_Date__c          = Date.today().addDays(-1),
            Close_Date__c         = Date.today().addDays(10)
        );
        insert s;

        Contact student = [SELECT Id FROM Contact WHERE Email = 'test.student.ty@example.com' LIMIT 1];
        Scholarship_Applicant__c app = new Scholarship_Applicant__c(
            Contact__c           = student.Id,
            Scholarship__c       = s.Id,
            Scholarship_Status__c = 'Accepted',
            Thank_You_Status__c  = 'Not Started'
        );
        insert app;

        Test.startTest();
        List<ScholarshipThankYouController.ThankYouItem> items =
            ScholarshipThankYouController.getThankYouItems(student.Id);
        Test.stopTest();

        // Find the no-FA-code item
        Boolean foundWarning = false;
        for (ScholarshipThankYouController.ThankYouItem i : items) {
            if (i.scholarshipName == 'No FA Code Scholarship') {
                foundWarning = i.hasDataWarning;
                break;
            }
        }
        System.assert(foundWarning, 'Should flag a data warning when FA code is missing');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // getThankYouItems — error path
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void testGetThankYouItems_blankContactIdThrows() {
        Boolean threw = false;
        Test.startTest();
        try {
            ScholarshipThankYouController.getThankYouItems('');
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();
        System.assert(threw, 'Should throw for blank contactId');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // getThankYouItem — positive path
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void testGetThankYouItem_returnsSingleItem() {
        Scholarship_Applicant__c app = getAcceptedApp();

        Test.startTest();
        ScholarshipThankYouController.ThankYouItem item =
            ScholarshipThankYouController.getThankYouItem(app.Id);
        Test.stopTest();

        System.assertNotEquals(null, item);
        System.assertEquals('Test TY Scholarship', item.scholarshipName);
        System.assertEquals('Not Started', item.thankYouStatus);
    }

    @isTest
    static void testGetThankYouItem_badIdThrows() {
        Boolean threw = false;
        Test.startTest();
        try {
            ScholarshipThankYouController.getThankYouItem('badId');
        } catch (Exception e) {
            threw = true;
        }
        Test.stopTest();
        System.assert(threw, 'Should throw for a bad applicant ID');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // saveThankYouDraft
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void testSaveThankYouDraft_setsInProgress() {
        Scholarship_Applicant__c app = getAcceptedApp();

        Test.startTest();
        ScholarshipThankYouController.ThankYouItem result =
            ScholarshipThankYouController.saveThankYouDraft(app.Id, 'This is my draft letter text for testing purposes.');
        Test.stopTest();

        System.assertEquals('In Progress', result.thankYouStatus);
        System.assertEquals('This is my draft letter text for testing purposes.', result.thankYouLetter);
    }

    @isTest
    static void testSaveThankYouDraft_doesNotRegressStatus() {
        // Pre-set to Submitted
        Scholarship_Applicant__c app = getAcceptedApp();
        app.Thank_You_Status__c = 'Submitted';
        update app;

        Test.startTest();
        ScholarshipThankYouController.ThankYouItem result =
            ScholarshipThankYouController.saveThankYouDraft(app.Id, 'Edited draft text for submitted record test.');
        Test.stopTest();

        // Status should remain Submitted, not regress
        System.assertEquals('Submitted', result.thankYouStatus);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // submitThankYouLetter
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void testSubmitThankYouLetter_setsSubmitted() {
        Scholarship_Applicant__c app = getAcceptedApp();
        String longLetter = 'Dear Donor, I am writing to express my sincere gratitude for your generous scholarship. '
            + 'Your support has made a tremendous difference in my academic journey. '
            + 'I am committed to making the most of this opportunity.';

        Test.startTest();
        ScholarshipThankYouController.ThankYouItem result =
            ScholarshipThankYouController.submitThankYouLetter(app.Id, longLetter, true);
        Test.stopTest();

        System.assertEquals('Submitted', result.thankYouStatus);
        System.assertEquals(true, result.photoRightsAccepted);
        System.assertNotEquals(null, result.submittedDate);
    }

    @isTest
    static void testSubmitThankYouLetter_tooShortThrows() {
        Scholarship_Applicant__c app = getAcceptedApp();
        Boolean threw = false;

        Test.startTest();
        try {
            ScholarshipThankYouController.submitThankYouLetter(app.Id, 'Too short.', false);
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();

        System.assert(threw, 'Should throw when letter is too short');
    }

    @isTest
    static void testSubmitThankYouLetter_blankThrows() {
        Scholarship_Applicant__c app = getAcceptedApp();
        Boolean threw = false;

        Test.startTest();
        try {
            ScholarshipThankYouController.submitThankYouLetter(app.Id, '', false);
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();

        System.assert(threw, 'Should throw for blank letter text');
    }

    @isTest
    static void testSubmitThankYouLetter_completeLockThrows() {
        Scholarship_Applicant__c app = getAcceptedApp();
        app.Thank_You_Status__c = 'Complete';
        update app;

        Boolean threw = false;
        String longLetter = 'Dear Donor, I am writing to express my sincere gratitude for your generous scholarship. '
            + 'Your support has made a tremendous difference in my academic journey. '
            + 'I am committed to making the most of this opportunity.';

        Test.startTest();
        try {
            ScholarshipThankYouController.submitThankYouLetter(app.Id, longLetter, false);
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();

        System.assert(threw, 'Should throw when status is Complete (DR lock)');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // getPreviousLetters
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void testGetPreviousLetters_returnsSubmittedLetters() {
        Id contactId = getStudentContactId();
        Scholarship_Applicant__c app = getAcceptedApp();

        // Pre-set a submitted letter to pull from
        app.Thank_You_Status__c = 'Submitted';
        app.Thank_You_Letter__c = 'A previously submitted thank you letter with sufficient content here.';
        app.Thank_You_Submitted_Date__c = Datetime.now().addDays(-5);
        update app;

        // Create a second applicant record to exclude
        Scholarship__c s2 = new Scholarship__c(
            Name                  = 'Second TY Scholarship',
            Thank_You_Required__c = 'Yes',
            Open_Date__c          = Date.today().addDays(-1),
            Close_Date__c         = Date.today().addDays(10)
        );
        insert s2;
        Contact student = [SELECT Id FROM Contact WHERE Email = 'test.student.ty@example.com' LIMIT 1];
        Scholarship_Applicant__c app2 = new Scholarship_Applicant__c(
            Contact__c           = student.Id,
            Scholarship__c       = s2.Id,
            Scholarship_Status__c = 'Accepted',
            Thank_You_Status__c  = 'Not Started'
        );
        insert app2;

        Test.startTest();
        List<ScholarshipThankYouController.PreviousLetterOption> options =
            ScholarshipThankYouController.getPreviousLetters(contactId, app2.Id);
        Test.stopTest();

        System.assertNotEquals(null, options);
        System.assert(options.size() >= 1, 'Should return at least one previous letter');
        System.assertEquals('A previously submitted thank you letter with sufficient content here.', options[0].letterText);
    }

    @isTest
    static void testGetPreviousLetters_blankContactReturnsEmpty() {
        Test.startTest();
        List<ScholarshipThankYouController.PreviousLetterOption> options =
            ScholarshipThankYouController.getPreviousLetters('', null);
        Test.stopTest();

        System.assertNotEquals(null, options);
        System.assertEquals(0, options.size());
    }

    // ─────────────────────────────────────────────────────────────────────────
    // uploadThankYouPhoto
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void testUploadThankYouPhoto_attachesContentVersion() {
        Scholarship_Applicant__c app = getAcceptedApp();
        String base64Data = EncodingUtil.base64Encode(Blob.valueOf('fake image bytes'));

        Test.startTest();
        ScholarshipThankYouController.uploadThankYouPhoto(app.Id, 'photo.png', base64Data);
        Test.stopTest();

        List<ContentDocumentLink> links = [
            SELECT Id, ContentDocument.Title
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :app.Id
        ];
        System.assertEquals(1, links.size(), 'Photo should be linked to the applicant record');
        System.assertEquals('photo', links[0].ContentDocument.Title);
    }

    @isTest
    static void testUploadThankYouPhoto_blankFileThrows() {
        Scholarship_Applicant__c app = getAcceptedApp();
        Boolean threw = false;

        Test.startTest();
        try {
            ScholarshipThankYouController.uploadThankYouPhoto(app.Id, '', '');
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();

        System.assert(threw, 'Should throw when no file data is supplied');
    }

    @isTest
    static void testUploadThankYouPhoto_completeLockThrows() {
        Scholarship_Applicant__c app = getAcceptedApp();
        app.Thank_You_Status__c = 'Complete';
        update app;
        String base64Data = EncodingUtil.base64Encode(Blob.valueOf('fake image bytes'));

        Boolean threw = false;
        Test.startTest();
        try {
            ScholarshipThankYouController.uploadThankYouPhoto(app.Id, 'photo.png', base64Data);
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();

        System.assert(threw, 'Should throw when status is Complete (DR lock)');
    }
}