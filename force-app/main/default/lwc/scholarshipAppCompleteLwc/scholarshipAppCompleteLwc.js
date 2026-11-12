import {api, LightningElement, wire} from "lwc";
import {CurrentPageReference, NavigationMixin} from "lightning/navigation";
import getPageData from "@salesforce/apex/ScholarshipAppCompleteLwcController.getPageData";

// Values returned by ScholarshipLwcService.getAccessStatus(). Only a submitted application (COMPLETE) is shown.
const STATUS_COMPLETE = "COMPLETE";
const STATUS_OPEN = "OPEN";
const STATUS_CLOSED = "CLOSED";
const STATUS_NOT_YET_OPEN = "NOT_YET_OPEN";

/**
 * Confirmation page shown after an application is submitted (LWC replacement for the ScholarshipApplicationComplete
 * VF page). The scholarship is identified by the "sid" URL parameter. The applicant is never chosen by the client:
 * the Apex controller derives it from the running user, and only returns the details for a submitted application.
 */
export default class ScholarshipAppCompleteLwc extends NavigationMixin(LightningElement) {

    // Experience Builder page API names. Editable in Experience Builder.
    @api applicationPageName = "Scholarship_Application_Page_Lwc_2__c";
    @api closedPageName = "Scholarship_Closed_Lwc__c";
    @api homePageName = "Scholarship_Home_Lwc__c";

    sid;
    pageData;
    isLoading = true;
    missingSid = false;
    loadError = "";

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

    get confirmationText() {
        return `Your application for the ${this.scholarshipName} has been received and is being reviewed.`;
    }

    get hasDescription() {
        return !!(this.pageData && this.pageData.reviewAwardProcessDescriptionHtml);
    }

    get descriptionHtml() {
        return this.pageData ? this.pageData.reviewAwardProcessDescriptionHtml : "";
    }

    get recommenders() {
        return this.pageData && this.pageData.recommenders ? this.pageData.recommenders : [];
    }

    get hasRecommenders() {
        return this.recommenders.length > 0;
    }

    // "Recommendation request sent to:" for one, "Recommendation requests sent to:" for two, as on the VF page.
    get recommendersHeading() {
        return `Recommendation request${this.recommenders.length > 1 ? "s" : ""} sent to:`;
    }

    get displayRecommenders() {
        return this.recommenders.map((recommender) => ({
            ...recommender,
            summary: `${recommender.name} (${recommender.email}) on ${recommender.requestedOn}`,
            statusText: `Status: ${recommender.status}`
        }));
    }

    async loadPageData() {
        this.loadError = "";
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
            if (data.status !== STATUS_COMPLETE) {
                redirected = this.redirectForStatus(data.status);
                return;
            }
            this.pageData = data;
        } catch (error) {
            this.loadError = this.reduceError(error);
        } finally {
            // Keep the spinner up while the browser navigates away.
            this.isLoading = redirected;
        }
    }

    handleGoHome() {
        this.navigateTo(this.homePageName, false);
    }

    /**
     * The confirmation is only for a submitted application. Anyone else goes where their application stands:
     * back to it if it is still open, to the Closed page if the scholarship is not open, otherwise Home.
     * Returns true when a navigation was started.
     */
    redirectForStatus(status) {
        if (status === STATUS_OPEN) {
            this.navigateTo(this.applicationPageName, true);
        } else if (status === STATUS_CLOSED || status === STATUS_NOT_YET_OPEN) {
            this.navigateTo(this.closedPageName, true);
        } else {
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

    reduceError(error) {
        if (error && error.body && error.body.message) {
            return error.body.message;
        }
        return (error && error.message) || "An unexpected error occurred. Please try again.";
    }
}
