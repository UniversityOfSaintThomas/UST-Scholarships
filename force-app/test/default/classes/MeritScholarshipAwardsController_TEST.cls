/**
 * Test class for MeritScholarshipAwardsController
 */

@IsTest
private class MeritScholarshipAwardsController_TEST {
    // ── helpers ────────────────────────────────────────────────────────────────
    private static String createTerm() {
        Account universityAccount = new Account(
            Name = 'Test University',
            RecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByName().get('Administrative').getRecordTypeId()
        );
        insert universityAccount;

        hed__Term__c currentTerm = new hed__Term__c(
            hed__Start_Date__c = System.today().addMonths(-12),
            hed__End_Date__c = System.today().addMonths(12),
            Name = 'Fall 2027',
            hed__Account__c = universityAccount.Id
        );
        insert currentTerm;

        Academic_Term__c academicTerm = new Academic_Term__c(
            Name = 'Fall 2027',
            Term__c = currentTerm.Id
        );
        insert academicTerm;
        return academicTerm.Id;
    }

    private static String createScholarship(String name) {
        Scholarship__c scholarship = new Scholarship__c(
                Name = name
        );
        insert scholarship;
        return scholarship.Id;
    }

    private static Application__c createApp(String term) {
        Academic_Term__c termName = [
                SELECT Name
                FROM Academic_Term__c
                WHERE Id = :term
                LIMIT 1
        ];

        Application__c app = new Application__c(
                Intended_Term_of_Entry__c = term,
                Generic_Filter_4__c = termName.Name
        );
        insert app;
        return app;
    }

    private static Award__c createAward(Id appId, String scholarshipId) {
        Award__c a = new Award__c(
                Triggering_Application__c                = appId,
                Scholarship_Name__c                      = scholarshipId,
                Award_Status__c                          = 'Offered',
                Award_Amount__c                          = 10000,
                Adj_Award_Amount__c                      = 9500,
                Scholarship_Award_Adjust_Reason__c       = 'GPA - Missing Academic Work',
                Base_Merit_Amount__c                     = 5000,
                Adj_Base_Merit_Amount__c                 = 4800,
                Catholic_High_School_Scholarship__c      = 500,
                Adj_Catholic_High_School_Scholar__c      = 450,
                California_Pathway_Scholarship__c        = 200,
                Adj_California_Pathway_Scholarship__c    = 180,
                Colorado_Pathway_Scholarship__c          = 300,
                Adj_Colorado_Pathway_Scholarship__c      = 280,
                Cristo_Rey_Scholarship__c                = 400,
                Adj_Cristo_Rey_Scholarship__c            = 380,
                Illinois_Pathway_Scholarship__c          = 150,
                Adj_Illinois_Pathway_Scholarship__c      = 140,
                Kansas_Pathway_Scholarship__c            = 100,
                Adj_Kansas_Pathway_Scholarship__c        = 90,
                Milwaukee_Area_Pathway_Scholarship__c    = 250,
                Adj_Milwaukee_Area_Pathway_Scholar__c    = 230,
                Missouri_Pathway_Scholarship__c          = 175,
                Adj_Missouri_Pathway_Scholarship__c      = 160,
                Nebraska_Pathways_Scholarship__c         = 125,
                Adj_Nebraska_Pathways_Scholarship__c     = 115,
                Sauer_Cristo_Rey_Scholarship__c          = 350,
                Adj_Sauer_Cristo_Rey_Scholarship__c      = 330,
                Adj_Athletic_Revision__c                 = 200,
                Adj_Strategic_Aid_Deployment__c          = 600,
                Transfer_PTK_Scholarship__c              = 750,
                Adj_Transfer_PTK_Scholarship__c          = 700,
                INTL_Student_Scholarship_Percent__c      = 25,
                ADJ_INTL_Student_Scholarship_Percent__c  = 20,
                Out_of_State_Scholarship__c              = 100,
                Adj_Out_of_State_Scholarship__c          = 90
        );
        insert a;
        return a;
    }

    private static Opportunity createOpportunity(Id appId, String stageName, Boolean fafsa, Boolean mnDream, Date notifDate) {
        Opportunity opp = new Opportunity(
                Name                        = 'Test Opp',
                StageName                   = stageName,
                CloseDate                   = Date.today().addDays(30),
                Admissions_Application__c   = appId,
                FAFSA_Filed__c              = fafsa,
                MN_Dream_Act_Filed__c       = mnDream,
                Notification_of_Award_Date__c = notifDate
        );
        insert opp;
        return opp;
    }

    // ── tests ──────────────────────────────────────────────────────────────────
    @IsTest
    static void testUGMeritScholarship_StThomasScholarship() {
        Application__c app = createApp(createTerm());
        createAward(app.Id, createScholarship('UG Merit Scholarship - Academic'));
        createOpportunity(app.Id, 'Admit', true, false, Date.today());

        Test.startTest();
        MeritScholarshipAwardsController.MeritScholarshipWrapper result =
                MeritScholarshipAwardsController.getMeritAwards(app.Id);
        System.debug('testUGMeritScholarship_StThomasScholarship Result: ' + result);
        Test.stopTest();

        // AwardInfo
        Assert.areEqual('Offered', result.AwardInfo.awardStatus, 'Award status should be Offered');
        Assert.areEqual(10000, result.AwardInfo.awardAmount, 'Award amount should be 10000');
        Assert.areEqual(9500, result.AwardInfo.awardAdjAmount, 'Adj award amount should be 9500');
        Assert.areEqual('GPA - Missing Academic Work', result.AwardInfo.awardAdjReason, 'Adj reason should match');

        // Base scholarship name -> St. Thomas Scholarship
        Assert.areEqual('St. Thomas Scholarship', result.DomesticScholarshipsList[0].scholarshipName,
                'Base scholarship should be St. Thomas Scholarship for UG Merit');
        Assert.areEqual(5000, result.DomesticScholarshipsList[0].scholarshipAmount);
        Assert.areEqual(4800, result.DomesticScholarshipsList[0].scholarshipAdjAmount);

        // 14 domestic scholarship entries total
        Assert.areEqual(15, result.DomesticScholarshipsList.size(), 'Should have 14 domestic scholarship entries');

        // Opportunity FAFSA
        Assert.isTrue(result.OpportunityFafsa.fafsaFiled, 'FAFSA should be filed');
        Assert.isFalse(result.OpportunityFafsa.mnDreamActFiled, 'MN Dream Act should not be filed');
        Assert.isTrue(result.OpportunityFafsa.notificationOfAward, 'Notification of award should be set');
    }

    @IsTest
    static void testUGTRMeritScholarship_USTTransferAward() {
        Application__c app = createApp(createTerm());
        createAward(app.Id, createScholarship('UG TR Merit Scholarship - Transfer'));
        createOpportunity(app.Id, 'Confirmed', false, true, null);

        Test.startTest();
        MeritScholarshipAwardsController.MeritScholarshipWrapper result =
                MeritScholarshipAwardsController.getMeritAwards(app.Id);
        System.debug('testUGTRMeritScholarship_USTTransferAward Result: ' + result);
        Test.stopTest();

        // Base scholarship name -> UST Transfer Award
        Assert.areEqual('UST Transfer Award', result.DomesticScholarshipsList[0].scholarshipName,
                'Base scholarship should be UST Transfer Award for UG TR Merit');

        // Opportunity
        Assert.isFalse(result.OpportunityFafsa.fafsaFiled);
        Assert.isTrue(result.OpportunityFafsa.mnDreamActFiled);
        Assert.isFalse(result.OpportunityFafsa.notificationOfAward, 'No notification date means false');
    }

    @IsTest
    static void testUGINTLMeritScholarship_InternationalScholarship() {
        Application__c app = createApp(createTerm());
        createAward(app.Id, createScholarship('UG INTL Merit Scholarship - International'));
        // No opportunity inserted - should default to false/false/false

        Test.startTest();
        MeritScholarshipAwardsController.MeritScholarshipWrapper result =
                MeritScholarshipAwardsController.getMeritAwards(app.Id);
        System.debug('testUGINTLMeritScholarship_InternationalScholarship Result: ' + result);
        Test.stopTest();

        // International scholarship percentages
        Assert.areEqual(25, result.InternationalScholarship.scholarshipPercent,
                'INTL scholarship percent should be 25');
        Assert.areEqual(20, result.InternationalScholarship.scholarshipAdjPercent,
                'INTL adj scholarship percent should be 20');

        // Opportunity defaults (no opp inserted)
        Assert.isFalse(result.OpportunityFafsa.fafsaFiled);
        Assert.isFalse(result.OpportunityFafsa.mnDreamActFiled);
        Assert.isFalse(result.OpportunityFafsa.notificationOfAward);
    }

    @IsTest
    static void testNoAwardFound_ReturnsEmptyWrapper() {
        Application__c app = createApp(createTerm());
        // No Award__c inserted — list stays empty

        Test.startTest();
        MeritScholarshipAwardsController.MeritScholarshipWrapper result =
                MeritScholarshipAwardsController.getMeritAwards(app.Id);
        System.debug('testNoAwardFound_ReturnsEmptyWrapper Result: ' + result);
        Test.stopTest();

        Assert.areEqual(0, result.DomesticScholarshipsList.size(), 'Domestic list should be empty');
        Assert.isNull(result.AwardInfo.awardStatus, 'Award status should be null when no app found');
    }

    @IsTest
    static void testNoApplicationFound_ReturnsDefaultWrapper() {
        // Pass a random valid-format Id that doesn't exist in the org
        String fakeId = Application__c.SObjectType.getDescribe().getKeyPrefix() + '000000000001AAA';

        Test.startTest();
        MeritScholarshipAwardsController.MeritScholarshipWrapper result =
                MeritScholarshipAwardsController.getMeritAwards(fakeId);
        System.debug('testNoApplicationFound_ReturnsDefaultWrapper Result: ' + result);
        Test.stopTest();

        Assert.isNull(result.AwardInfo.awardStatus, 'Award status should be null when no app found');
        Assert.areEqual(0, result.DomesticScholarshipsList.size(), 'Domestic list should be empty');
        Assert.isFalse(result.OpportunityFafsa.fafsaFiled);
        Assert.isFalse(result.OpportunityFafsa.mnDreamActFiled);
        Assert.isFalse(result.OpportunityFafsa.notificationOfAward);
    }

    @IsTest
    static void testNullAmounts_DefaultToZero() {
        Application__c app = createApp(createTerm());
        String scholarshipId = createScholarship('UG Merit Scholarship - Academic');
        // Insert award with all amounts null
        Award__c a = new Award__c(
                Triggering_Application__c       = app.Id,
                Scholarship_Name__c     = scholarshipId,
                Award_Amount__c                 = null,
                Adj_Award_Amount__c             = null,
                Base_Merit_Amount__c            = null,
                Adj_Base_Merit_Amount__c        = null
                // all other amount fields left null
        );
        insert a;
        System.debug('Award: ' + a.Id);

        Test.startTest();
        MeritScholarshipAwardsController.MeritScholarshipWrapper result =
                MeritScholarshipAwardsController.getMeritAwards(app.Id);
        System.debug('testNullAmounts_DefaultToZero Result: ' + result);
        Test.stopTest();

        Assert.areEqual(0, result.AwardInfo.awardAmount, 'Null award amount should default to 0');
        Assert.areEqual(0, result.AwardInfo.awardAdjAmount, 'Null adj award amount should default to 0');
        Assert.areEqual(0, result.DomesticScholarshipsList[0].scholarshipAmount, 'Null base merit should default to 0');
        Assert.areEqual(0, result.DomesticScholarshipsList[0].scholarshipAdjAmount, 'Null adj base merit should default to 0');
        Assert.areEqual(0, result.InternationalScholarship.scholarshipPercent);
        Assert.areEqual(0, result.InternationalScholarship.scholarshipAdjPercent);
    }
}