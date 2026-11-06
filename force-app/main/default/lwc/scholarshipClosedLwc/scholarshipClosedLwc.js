import {LightningElement, wire} from "lwc";
import {CurrentPageReference} from "lightning/navigation";
import getAccessStatus from "@salesforce/apex/ScholarshipLwcService.getAccessStatus";

// Values returned by ScholarshipLwcService.getAccessStatus()
const STATUS_CLOSED = "CLOSED";
const STATUS_NOT_YET_OPEN = "NOT_YET_OPEN";

/**
 * LWC replacement for the ScholarshipClosed VF page. The scholarship is identified by the "sid" URL parameter.
 * The page only explains why the scholarship is unavailable; it never redirects. Anything that is not
 * clearly "closed" or "not yet open" gets the generic "currently closed" message, as in the VF page.
 */
export default class ScholarshipClosedLwc extends LightningElement {

    sid;
    access;
    isLoading = true;
    errorMessage = "";

    _pageReferenceHandled = false;

    @wire(CurrentPageReference)
    handlePageReference(pageReference) {
        const sid = pageReference && pageReference.state ? pageReference.state.sid : undefined;
        if (this._pageReferenceHandled && sid === this.sid) {
            return;
        }
        this._pageReferenceHandled = true;
        this.sid = sid;
        this.loadAccessStatus();
    }

    get hasData() {
        return !!this.access;
    }

    get scholarshipName() {
        return this.access && this.access.scholarshipName ? this.access.scholarshipName : "";
    }

    get hasScholarshipName() {
        return !!this.scholarshipName;
    }

    get message() {
        if (!this.access) {
            return "";
        }
        const name = this.scholarshipName ? `The ${this.scholarshipName}` : "This scholarship";
        const {status, displayOpenDateTime, displayCloseDateTime} = this.access;

        if (status === STATUS_CLOSED && displayCloseDateTime) {
            return `We're sorry. ${name} closed on ${displayCloseDateTime}. Thank you for your interest.`;
        }
        if (status === STATUS_NOT_YET_OPEN && displayOpenDateTime) {
            return `We're sorry. ${name} has not opened yet. It will open on ${displayOpenDateTime}. ` +
                "Please return after the open date and fill out your application then. Thank you for your interest!";
        }
        return `We're sorry. ${name} is currently closed. Thank you for your interest!`;
    }

    async loadAccessStatus() {
        this.errorMessage = "";
        if (!this.sid) {
            // No scholarship to describe: show the generic message instead of an error.
            this.access = {};
            this.isLoading = false;
            return;
        }

        this.isLoading = true;
        try {
            this.access = await getAccessStatus({sid: this.sid});
        } catch (error) {
            this.errorMessage = this.reduceError(error);
        } finally {
            this.isLoading = false;
        }
    }

    reduceError(error) {
        if (error && error.body && error.body.message) {
            return error.body.message;
        }
        return (error && error.message) || "An unexpected error occurred. Please try again.";
    }
}
