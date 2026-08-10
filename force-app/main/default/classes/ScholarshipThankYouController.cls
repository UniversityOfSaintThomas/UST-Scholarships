/**
 * ScholarshipThankYouController
 * Apex controller for the scholarshipThankYousLwc component.
 * Handles both portal (list) mode and record-page (single) mode.
 *
 * Created: 2026-03-26
 */
public with sharing class ScholarshipThankYouController {

    // ─────────────────────────────────────────────────────────────────────────
    // Constants
    // ─────────────────────────────────────────────────────────────────────────
    private static final Integer MIN_LETTER_LENGTH = 100;
    private static final Set<String> AWARDED_STATUSES = new Set<String>{
        'Accepted', 'Awarded'
    };
    private static final Set<String> TY_REQUIRED_VALUES = new Set<String>{
        'Yes', 'Optional'
    };

    // ─────────────────────────────────────────────────────────────────────────
    // READ — Portal List Mode
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * Returns all thank-you items for a given contact.
     * Only includes applicant records where the scholarship requires (or makes
     * optional) a TY letter AND the student was awarded/accepted.
     */
    @AuraEnabled
    public static List<ThankYouItem> getThankYouItems(String contactId) {
        if (String.isBlank(contactId)) {
            throw new AuraHandledException('Contact ID is required.');
        }

        Id resolvedContactId = resolveContactId(contactId);
        assertContactOwnership(resolvedContactId);

        List<Scholarship_Applicant__c> applicants = [
            SELECT Id,
                   Name,
                   Contact__c,
                   Scholarship_Status__c,
                   Thank_You_Status__c,
                   Thank_You_Letter__c,
                   Thank_You_Submitted_Date__c,
                   Thank_You_Photo_Rights_Accepted__c,
                   Scholarship__r.Name,
                   Scholarship__r.Thank_You_Required__c,
                   Scholarship__r.Designation_Code__c,
                   Scholarship__r.Financial_Aid_Code__c,
                   Scholarship__r.Thank_You_Sample_Letter__c,
                   Scholarship__r.Scholarship_Account__r.Name
            FROM Scholarship_Applicant__c
            WHERE Contact__c = :resolvedContactId
              AND Scholarship__r.Thank_You_Required__c IN :TY_REQUIRED_VALUES
              AND Scholarship_Status__c IN :AWARDED_STATUSES

            ORDER BY Scholarship__r.Name ASC
        ];

        List<ThankYouItem> items = new List<ThankYouItem>();
        for (Scholarship_Applicant__c app : applicants) {
            items.add(buildItem(app));
        }
        return items;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // READ — Record Page Mode
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * Returns a single thank-you item by Scholarship_Applicant__c Id.
     * Used when the LWC is placed on the Scholarship_Applicant__c record page.
     */
    @AuraEnabled
    public static ThankYouItem getThankYouItem(String applicantId) {
        if (String.isBlank(applicantId)) {
            throw new AuraHandledException('Applicant ID is required.');
        }

        List<Scholarship_Applicant__c> results = [
            SELECT Id,
                   Name,
                   Contact__c,
                   Scholarship_Status__c,
                   Thank_You_Status__c,
                   Thank_You_Letter__c,
                   Thank_You_Submitted_Date__c,
                   Thank_You_Photo_Rights_Accepted__c,
                   Scholarship__r.Name,
                   Scholarship__r.Thank_You_Required__c,
                   Scholarship__r.Designation_Code__c,
                   Scholarship__r.Financial_Aid_Code__c,
                   Scholarship__r.Thank_You_Sample_Letter__c,
                   Scholarship__r.Scholarship_Account__r.Name
            FROM Scholarship_Applicant__c
            WHERE Id = :applicantId

            LIMIT 1
        ];

        if (results.isEmpty()) {
            throw new AuraHandledException('Scholarship applicant record not found.');
        }

        return buildItem(results[0]);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // WRITE — Save Draft
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * Saves a draft letter. Advances status from Not Started → In Progress.
     * Does NOT advance if already Submitted or Complete.
     */
    @AuraEnabled
    public static ThankYouItem saveThankYouDraft(String applicantId, String letterText) {
        Scholarship_Applicant__c app = getWritableApplicant(applicantId);

        app.Thank_You_Letter__c = letterText;
        if (app.Thank_You_Status__c == null || app.Thank_You_Status__c == 'Not Started') {
            app.Thank_You_Status__c = 'In Progress';
        }

        update app; // USER_MODE enforced via with sharing class

        return getThankYouItem(applicantId);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // WRITE — Submit Letter
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * Submits the final thank-you letter.
     * Enforces minimum length and sets status → Submitted with a timestamp.
     */
    @AuraEnabled
    public static ThankYouItem submitThankYouLetter(
        String applicantId,
        String letterText,
        Boolean photoRightsAccepted
    ) {
        if (String.isBlank(letterText) || letterText.trim().length() < MIN_LETTER_LENGTH) {
            throw new AuraHandledException(
                'Your thank-you letter must be at least ' + MIN_LETTER_LENGTH + ' characters.'
            );
        }

        Scholarship_Applicant__c app = getWritableApplicant(applicantId);

        app.Thank_You_Letter__c = letterText;
        app.Thank_You_Status__c = 'Submitted';
        app.Thank_You_Submitted_Date__c = Datetime.now();
        if (photoRightsAccepted != null) {
            app.Thank_You_Photo_Rights_Accepted__c = photoRightsAccepted;
        }

        update app;

        return getThankYouItem(applicantId);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // WRITE — Photo Upload
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * Uploads a thank-you photo and attaches it to the Scholarship_Applicant__c
     * record. Used by the portal (Lightning Out) editor, which cannot rely on
     * lightning-file-upload's built-in upload mechanism — that component never
     * fires its upload request when embedded via Lightning Out on a Visualforce
     * Site page, so the file is instead read client-side and sent here as base64.
     */
    @AuraEnabled
    public static void uploadThankYouPhoto(String applicantId, String fileName, String base64Data) {
        if (String.isBlank(fileName) || String.isBlank(base64Data)) {
            throw new AuraHandledException('A photo file is required.');
        }

        Scholarship_Applicant__c app = getWritableApplicant(applicantId);

        ContentVersion version = new ContentVersion();
        version.PathOnClient = fileName;
        version.VersionData = EncodingUtil.base64Decode(base64Data);
        version.FirstPublishLocationId = app.Id;
        insert version;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // READ — Previous Letters (for re-use feature)
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * Returns text snippets from the student's previously submitted/complete
     * TY letters so they can reuse content across multiple scholarships.
     */
    @AuraEnabled(cacheable=true)
    public static List<PreviousLetterOption> getPreviousLetters(
        String contactId,
        String excludeApplicantId
    ) {
        if (String.isBlank(contactId)) {
            return new List<PreviousLetterOption>();
        }

        Id resolvedContactId = resolveContactId(contactId);
        assertContactOwnership(resolvedContactId);

        List<Scholarship_Applicant__c> prior = [
            SELECT Id,
                   Scholarship__r.Name,
                   Thank_You_Letter__c,
                   Thank_You_Submitted_Date__c
            FROM Scholarship_Applicant__c
            WHERE Contact__c = :resolvedContactId
              AND Thank_You_Status__c IN ('Submitted', 'Complete')
              AND Id != :excludeApplicantId

            ORDER BY Thank_You_Submitted_Date__c DESC
            LIMIT 10
        ];

        List<PreviousLetterOption> options = new List<PreviousLetterOption>();
        for (Scholarship_Applicant__c app : prior) {
            // Long Text Area can't be filtered in SOQL — skip empty letters here
            if (String.isBlank(app.Thank_You_Letter__c)) continue;
            PreviousLetterOption opt = new PreviousLetterOption();
            opt.applicantId = app.Id;
            opt.scholarshipName = app.Scholarship__r.Name;
            opt.letterText = app.Thank_You_Letter__c;
            opt.submittedDate = app.Thank_You_Submitted_Date__c;
            options.add(opt);
        }
        return options;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Private Helpers
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * Fetches an applicant record for DML, enforcing:
     *  1. Record exists
     *  2. Current user owns the related contact (student), OR is an admin
     *  3. Status is not already Complete (DR lock)
     */
    private static Scholarship_Applicant__c getWritableApplicant(String applicantId) {
        if (String.isBlank(applicantId)) {
            throw new AuraHandledException('Applicant ID is required.');
        }

        List<Scholarship_Applicant__c> results = [
            SELECT Id,
                   Contact__c,
                   Thank_You_Status__c,
                   Thank_You_Letter__c,
                   Thank_You_Photo_Rights_Accepted__c
            FROM Scholarship_Applicant__c
            WHERE Id = :applicantId

            LIMIT 1
        ];

        if (results.isEmpty()) {
            throw new AuraHandledException('Scholarship applicant record not found.');
        }

        Scholarship_Applicant__c app = results[0];
        assertContactOwnership(app.Contact__c);

        if (app.Thank_You_Status__c == 'Complete') {
            throw new AuraHandledException(
                'This thank-you letter has been marked Complete and can no longer be edited.'
            );
        }

        return app;
    }

    /**
     * Builds a ThankYouItem wrapper from a Scholarship_Applicant__c record.
     */
    private static ThankYouItem buildItem(Scholarship_Applicant__c app) {
        ThankYouItem item = new ThankYouItem();
        item.applicantId            = app.Id;
        item.contactId              = app.Contact__c != null ? String.valueOf(app.Contact__c) : null;
        item.scholarshipName        = app.Scholarship__r.Name;
        item.thankYouRequired       = app.Scholarship__r.Thank_You_Required__c;
        item.designationCode        = app.Scholarship__r.Designation_Code__c;
        item.financialAidCode       = app.Scholarship__r.Financial_Aid_Code__c;
        item.thankYouStatus         = String.isBlank(app.Thank_You_Status__c)
                                        ? 'Not Started'
                                        : app.Thank_You_Status__c;
        item.thankYouLetter         = app.Thank_You_Letter__c;
        item.sampleLetter           = app.Scholarship__r.Thank_You_Sample_Letter__c;
        item.photoRightsAccepted    = app.Thank_You_Photo_Rights_Accepted__c == true;
        item.submittedDate          = app.Thank_You_Submitted_Date__c;

        // Donor name from Scholarship Account lookup
        if (app.Scholarship__r.Scholarship_Account__r != null) {
            item.scholarshipAccountName = app.Scholarship__r.Scholarship_Account__r.Name;
        }

        // Data completeness warning for student
        List<String> warnings = new List<String>();
        if (String.isBlank(app.Scholarship__r.Financial_Aid_Code__c)) {
            warnings.add('Financial Aid code is missing for this scholarship.');
        }
        if (app.Scholarship__r.Scholarship_Account__r == null) {
            warnings.add('Donor account is not linked to this scholarship.');
        }
        item.hasDataWarning     = !warnings.isEmpty();
        item.dataWarningMessage = warnings.isEmpty()
                                    ? null
                                    : String.join(warnings, ' ');

        return item;
    }

    /**
     * If contactId is a User Id (portal context), resolve it to the Contact Id.
     * Otherwise return as-is.
     */
    private static Id resolveContactId(String contactId) {
        if (String.isBlank(contactId)) return null;
        // If it looks like a Contact Id (starts with 003) just return it
        if (contactId.startsWith('003')) {
            return (Id) contactId;
        }
        // Could be a User Id — look up the linked Contact
        List<User> users = [
            SELECT ContactId FROM User WHERE Id = :contactId LIMIT 1
        ];
        if (!users.isEmpty() && users[0].ContactId != null) {
            return users[0].ContactId;
        }
        return (Id) contactId;
    }

    /**
     * Ensures the running user is either a Salesforce admin (System Admin profile)
     * or has a Contact matching the supplied contactId.
     * Throws AuraHandledException if the check fails.
     */
    private static void assertContactOwnership(Id contactId) {
        // Admins can view/edit any record
        if (isCurrentUserAdmin()) return;

        Id runningUserContactId = ScholarshipSharedUtilities.getActiveContactId();
        if (runningUserContactId == null || runningUserContactId != contactId) {
            throw new AuraHandledException(
                'You do not have permission to access this record.'
            );
        }
    }

    private static Boolean isCurrentUserAdmin() {
        User u = [
            SELECT Profile.Name FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1
        ];
        return u.Profile.Name == 'System Administrator';
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Inner / Wrapper Classes
    // ─────────────────────────────────────────────────────────────────────────

    public class ThankYouItem {
        @AuraEnabled public String   applicantId;
        @AuraEnabled public String   contactId;
        @AuraEnabled public String   scholarshipName;
        @AuraEnabled public String   scholarshipAccountName;
        @AuraEnabled public String   designationCode;
        @AuraEnabled public String   financialAidCode;
        @AuraEnabled public String   thankYouRequired;
        @AuraEnabled public String   thankYouStatus;
        @AuraEnabled public String   thankYouLetter;
        @AuraEnabled public String   sampleLetter;
        @AuraEnabled public Boolean  photoRightsAccepted;
        @AuraEnabled public Datetime submittedDate;
        @AuraEnabled public Boolean  hasDataWarning;
        @AuraEnabled public String   dataWarningMessage;
    }

    public class PreviousLetterOption {
        @AuraEnabled public String   applicantId;
        @AuraEnabled public String   scholarshipName;
        @AuraEnabled public String   letterText;
        @AuraEnabled public Datetime submittedDate;
    }
}