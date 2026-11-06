import {api, LightningElement, wire} from "lwc";
import {CurrentPageReference, NavigationMixin} from "lightning/navigation";
import {ShowToastEvent} from "lightning/platformShowToastEvent";
import getPageData from "@salesforce/apex/ScholarshipAppPage1LwcController.getPageData";
import saveCriteria from "@salesforce/apex/ScholarshipAppPage1LwcController.saveCriteria";
import {parseNumber, validateCriteria} from "./criteriaValidation";

// Values returned by ScholarshipLwcService.getAccessStatus()
const STATUS_OPEN = "OPEN";
const STATUS_COMPLETE = "COMPLETE";
const STATUS_CLOSED = "CLOSED";
const STATUS_NOT_YET_OPEN = "NOT_YET_OPEN";

const NO_ERRORS = {gpa: null, actSat: null, confirmed: null};

/**
 * Page 1 of the scholarship application (LWC replacement for the ScholarshipApplicationPage1 VF page).
 * The scholarship is identified by the "sid" URL parameter. The applicant is never sent by the client:
 * the Apex controller derives it from the running user.
 */
export default class ScholarshipCriteriaLwc extends NavigationMixin(LightningElement) {

    // Experience Builder page API names. Editable in Experience Builder, so they can be corrected
    // without a code change if the site's page names differ from these defaults.
    @api nextPageName = "Scholarship_Application_Page_2__c";
    @api closedPageName = "Scholarship_Closed__c";
    @api completePageName = "Scholarship_Application_Complete__c";
    @api homePageName = "Scholarship_Home_Lwc__c";

    sid;
    pageData;
    isLoading = true;
    isSaving = false;
    errorMessage = "";
    missingSid = false;
    fieldErrors = NO_ERRORS;

    gpa = "";
    actSat = "";
    confirmed = false;

    _pageReferenceHandled = false;

    @wire(CurrentPageReference)
    handlePageReference(pageReference) {
        const sid = pageReference && pageReference.state ? pageReference.state.sid : undefined;
        if (this._pageReferenceHandled && sid === this.sid) {
            return;
        }
        this._pageReferenceHandled = true;
        this.sid = sid;
        this.loadPageData();
    }

    get hasData() {
        return !!this.pageData;
    }

    get scholarshipName() {
        return this.pageData ? this.pageData.scholarshipName : "";
    }

    get hasDescription() {
        return !!(this.pageData && this.pageData.description);
    }

    get hasCriteria() {
        return !!(this.pageData && this.pageData.criteriaStatement);
    }

    get selfReportRequired() {
        return !!(this.pageData && this.pageData.selfReportRequired);
    }

    get configWarnings() {
        return this.pageData && this.pageData.configWarnings ? this.pageData.configWarnings : [];
    }

    get hasConfigWarnings() {
        return this.configWarnings.length > 0;
    }

    get confirmLabel() {
        return `I confirm that I meet the eligibility criteria for the ${this.scholarshipName}.`;
    }

    get gpaError() {
        return this.fieldErrors.gpa;
    }

    get actSatError() {
        return this.fieldErrors.actSat;
    }

    get confirmedError() {
        return this.fieldErrors.confirmed;
    }

    get gpaWrapperClass() {
        return this.fieldErrors.gpa ? "slds-form-element slds-has-error" : "slds-form-element";
    }

    get actSatWrapperClass() {
        return this.fieldErrors.actSat ? "slds-form-element slds-has-error" : "slds-form-element";
    }

    get confirmWrapperClass() {
        return this.fieldErrors.confirmed ? "slds-form-element slds-has-error" : "slds-form-element";
    }

    async loadPageData() {
        this.errorMessage = "";
        if (!this.sid) {
            // No scholarship in the URL (for example in the Experience Builder canvas). Explain instead of
            // redirecting, so the component can be placed and previewed without leaving the page.
            this.pageData = undefined;
            this.missingSid = true;
            this.isLoading = false;
            return;
        }

        this.missingSid = false;
        this.isLoading = true;
        let redirected = false;
        try {
            const data = await getPageData({sid: this.sid});
            if (data.status !== STATUS_OPEN) {
                redirected = this.redirectForStatus(data.status);
                return;
            }
            this.pageData = data;
            this.confirmed = !!data.confirmedCriteria;
            this.gpa = this.toInputValue(data.declaredGpa);
            this.actSat = this.toInputValue(data.declaredActSat);
        } catch (error) {
            this.errorMessage = this.reduceError(error);
        } finally {
            // Keep the spinner up while the browser navigates away.
            this.isLoading = redirected;
        }
    }

    handleGoHome() {
        this.navigateTo(this.homePageName, false);
    }

    handleChange(event) {
        const field = event.target.dataset.field;
        if (field === "confirmed") {
            this.confirmed = event.detail.checked;
        } else if (field === "gpa") {
            this.gpa = event.detail.value;
        } else if (field === "actSat") {
            this.actSat = event.detail.value;
        }
        if (this.fieldErrors[field]) {
            this.fieldErrors = {...this.fieldErrors, [field]: null};
        }
    }

    async handleSave() {
        this.errorMessage = "";

        const validation = validateCriteria({
            confirmed: this.confirmed,
            selfReportRequired: this.selfReportRequired,
            gpa: this.gpa,
            actSat: this.actSat
        });
        this.fieldErrors = validation.errors;
        if (!validation.isValid) {
            return;
        }

        this.isSaving = true;
        let navigating = false;
        try {
            const result = await saveCriteria({
                sid: this.sid,
                declaredGpa: this.selfReportRequired ? parseNumber(this.gpa) : null,
                declaredActSat: this.selfReportRequired ? parseNumber(this.actSat) : null,
                confirmed: this.confirmed
            });

            if (result.success) {
                if (result.startedEmailFailed) {
                    this.dispatchEvent(new ShowToastEvent({
                        title: "Confirmation email not sent",
                        message: "Your scholarship was saved, but the started-application confirmation email could not be sent.",
                        variant: "warning"
                    }));
                }
                this.navigateTo(this.nextPageName, true);
                navigating = true;
                return;
            }

            if (result.status !== STATUS_OPEN) {
                navigating = this.redirectForStatus(result.status);
                if (navigating) {
                    return;
                }
            }
            this.errorMessage = result.message;
        } catch (error) {
            this.errorMessage = this.reduceError(error);
        } finally {
            this.isSaving = navigating;
        }
    }

    /**
     * Counterpart of the PageReference returned by checkScholarshipAccess() in the VF flow.
     * Returns true when a navigation was started.
     */
    redirectForStatus(status) {
        if (status === STATUS_COMPLETE) {
            this.navigateTo(this.completePageName, true);
        } else if (status === STATUS_CLOSED || status === STATUS_NOT_YET_OPEN) {
            this.navigateTo(this.closedPageName, true);
        } else {
            // Unknown scholarship: back to the scholarship list, as the VF page did.
            this.navigateTo(this.homePageName, false);
        }
        return true;
    }

    navigateTo(pageName, carrySid) {
        this[NavigationMixin.Navigate]({
            type: "comm__namedPage",
            attributes: {name: pageName},
            state: carrySid && this.sid ? {sid: this.sid} : {}
        }, true);
    }

    toInputValue(value) {
        return value === null || value === undefined ? "" : String(value);
    }

    reduceError(error) {
        if (error && error.body && error.body.message) {
            return error.body.message;
        }
        return (error && error.message) || "An unexpected error occurred. Please try again.";
    }
}
