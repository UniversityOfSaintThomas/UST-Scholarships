import {LightningElement, wire} from "lwc";
import {CurrentPageReference} from "lightning/navigation";
import getRecommendationRequest from "@salesforce/apex/ScholarshipRecommenderLwcController.getRecommendationRequest";
import submitRecommendation from "@salesforce/apex/ScholarshipRecommenderLwcController.submitRecommendation";

// Values returned by ScholarshipRecommenderLwcController.
const STATUS_READY = "READY";
const STATUS_RECEIVED = "RECEIVED";

/**
 * True when rich text contains something visible, so editor leftovers such as "<p><br></p>" count as empty.
 *
 * @param {string} html The rich text to check.
 * @returns {boolean} True when there is visible text or an image.
 */
function hasText(html) {
    if (!html) {
        return false;
    }
    if (/<img/i.test(html)) {
        return true;
    }
    return html.replace(/<[^>]*>/g, "").replace(/&nbsp;/gi, " ").trim() !== "";
}

/**
 * Page an outside recommender opens from the emailed link (LWC replacement for the ScholarshipRecommender VF
 * page). It has no login: the "recId" in the URL is the only credential, and the server decides what it may see
 * and do. This component never sends who the recommender is or which applicant to update, only the link's value
 * and the text.
 */
export default class ScholarshipRecommenderLwc extends LightningElement {

    recId;
    request;
    recommendation = "";
    isLoading = true;
    isSaving = false;
    missingRecId = false;
    invalidLink = false;
    submitted = false;
    loadError = "";
    submitError = "";
    recommendationError = "";

    _pageReferenceHandled = false;

    @wire(CurrentPageReference)
    handlePageReference(pageReference) {
        const recId = this.readRecId(pageReference);
        if (this._pageReferenceHandled && recId === this.recId) {
            return;
        }
        this._pageReferenceHandled = true;
        this.recId = recId;
        this.loadRequest();
    }

    /**
     * The link says "recId", but the page URL state may not keep that capitalisation, so any case is accepted.
     *
     * @param {Object} pageReference The current page reference.
     * @returns {(string|undefined)} The value of the recId parameter, if there is one.
     */
    readRecId(pageReference) {
        const state = pageReference && pageReference.state ? pageReference.state : {};
        const key = Object.keys(state).find((name) => name.toLowerCase() === "recid");
        return key ? state[key] : undefined;
    }

    get hasRequest() {
        return !!this.request && !this.submitted;
    }

    get scholarshipName() {
        return this.request ? this.request.scholarshipName : "";
    }

    get greeting() {
        return `Greetings ${this.request.recommenderName},`;
    }

    get requestText() {
        return `You have been requested by ${this.request.applicantName} to provide a recommendation towards the ${this.request.scholarshipName}.`;
    }

    get thankYouText() {
        return `Thank you for submitting your recommendation for ${this.request.applicantName}.`;
    }

    get hasDescription() {
        return !!(this.request && this.request.scholarshipDescriptionHtml);
    }

    get hasQuestion() {
        return !!(this.request && this.request.questionHtml);
    }

    async loadRequest() {
        this.loadError = "";
        this.invalidLink = false;
        this.submitted = false;
        if (!this.recId) {
            // No link in the URL (for example in the Experience Builder canvas): explain instead of failing.
            this.request = undefined;
            this.missingRecId = true;
            this.isLoading = false;
            return;
        }

        this.missingRecId = false;
        this.isLoading = true;
        try {
            const data = await getRecommendationRequest({recId: this.recId});
            if (data.status === STATUS_READY || data.status === STATUS_RECEIVED) {
                this.request = data;
                this.recommendation = data.recommendationHtml || "";
                this.submitted = data.status === STATUS_RECEIVED;
            } else {
                this.request = undefined;
                this.invalidLink = true;
            }
        } catch (error) {
            this.loadError = this.reduceError(error);
        } finally {
            this.isLoading = false;
        }
    }

    handleRecommendationChange(event) {
        this.recommendation = event.detail.value;
        this.recommendationError = "";
    }

    async handleSubmit() {
        if (this.isSaving) {
            return;
        }
        this.submitError = "";

        if (!hasText(this.recommendation)) {
            this.recommendationError = "Please enter your recommendation.";
            return;
        }
        this.recommendationError = "";

        this.isSaving = true;
        try {
            const result = await submitRecommendation({recId: this.recId, recommendationHtml: this.recommendation});

            if (result.success || result.status === STATUS_RECEIVED) {
                // Either it was just saved, or it had already been submitted: both end on the thank-you message.
                this.submitted = true;
            } else if (result.status === STATUS_READY) {
                this.submitError = result.message;
            } else {
                this.request = undefined;
                this.invalidLink = true;
            }
        } catch (error) {
            this.submitError = this.reduceError(error);
        } finally {
            this.isSaving = false;
        }
    }

    reduceError(error) {
        if (error && error.body && error.body.message) {
            return error.body.message;
        }
        return (error && error.message) || "An unexpected error occurred. Please try again.";
    }
}
