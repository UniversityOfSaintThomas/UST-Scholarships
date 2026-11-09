import {api, LightningElement, wire} from "lwc";
import {CurrentPageReference, NavigationMixin} from "lightning/navigation";
import {ShowToastEvent} from "lightning/platformShowToastEvent";
import getPageData from "@salesforce/apex/ScholarshipAppPage2LwcController.getPageData";
import saveAnswers from "@salesforce/apex/ScholarshipAppPage2LwcController.saveAnswers";
import {countWords} from "./wordCount";

// Values returned by ScholarshipLwcService.getAccessStatus() plus the Page 2 specific CRITERIA_REQUIRED.
const STATUS_OPEN = "OPEN";
const STATUS_COMPLETE = "COMPLETE";
const STATUS_CLOSED = "CLOSED";
const STATUS_NOT_YET_OPEN = "NOT_YET_OPEN";
const STATUS_CRITERIA_REQUIRED = "CRITERIA_REQUIRED";

// Same wording as the inline confirmation (without its bold "Saved:" lead-in, which is the toast title).
const SAVED_MESSAGE = "Your scholarship application has been saved and you can return to it at any time. " +
    "Your scholarship will not be submitted until you click “Save & Submit” below.";

/**
 * Page 2 of the scholarship application (LWC replacement for the ScholarshipApplicationPage2 VF page),
 * currently covering the application questions only. The scholarship is identified by the "sid" URL
 * parameter. The applicant is never sent by the client: the Apex controller derives it from the running user.
 */
export default class ScholarshipAppPage2Lwc extends NavigationMixin(LightningElement) {

    // Experience Builder page API names. Editable in Experience Builder.
    @api previousPageName = "Scholarship_Application_Page_Lwc_1__c";
    @api closedPageName = "Scholarship_Closed_Lwc__c";
    @api completePageName = "Scholarship_Application_Complete_Lwc__c";
    @api homePageName = "Scholarship_Home_Lwc__c";

    sid;
    pageData;
    questions = [];
    isLoading = true;
    isSaving = false;
    missingSid = false;
    loadError = "";
    saveError = "";
    saveConfirmed = false;

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

    get displayQuestions() {
        return this.questions.map((question) => ({
            ...question,
            label: `Answer to question ${question.questionNumber}`,
            wordCountLabel: `Word count: ${countWords(question.answer)}`
        }));
    }

    async loadPageData() {
        this.loadError = "";
        this.saveError = "";
        this.saveConfirmed = false;
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
            this.questions = (data.questions || []).map((question) => ({...question}));
        } catch (error) {
            this.loadError = this.reduceError(error);
        } finally {
            // Keep the spinner up while the browser navigates away.
            this.isLoading = redirected;
        }
    }

    handleAnswerChange(event) {
        const questionNumber = Number(event.target.dataset.question);
        const answer = event.detail.value;
        this.questions = this.questions.map((question) => {
            return question.questionNumber === questionNumber ? {...question, answer} : question;
        });
        this.saveConfirmed = false;
    }

    async handleSaveFinishLater() {
        this.saveError = "";
        this.saveConfirmed = false;
        this.isSaving = true;
        let navigating = false;
        try {
            // Sent as a map of question number to answer; see ScholarshipAppPage2LwcController.saveAnswers().
            const answers = {};
            this.questions.forEach((question) => {
                answers[String(question.questionNumber)] = question.answer;
            });
            const result = await saveAnswers({sid: this.sid, answers});

            if (result.success) {
                this.saveConfirmed = true;
                this.dispatchEvent(new ShowToastEvent({
                    title: "Saved",
                    message: SAVED_MESSAGE,
                    variant: "success",
                    mode: "sticky"
                }));
                return;
            }

            if (result.status !== STATUS_OPEN) {
                navigating = this.redirectForStatus(result.status);
                if (navigating) {
                    return;
                }
            }
            this.saveError = result.message;
        } catch (error) {
            this.saveError = this.reduceError(error);
        } finally {
            this.isSaving = navigating;
        }
    }

    /**
     * Counterpart of GoCriteria() in the VF controller. Does not save, as in the VF page.
     */
    handlePreviousPage() {
        this.navigateTo(this.previousPageName, true);
    }

    handleGoHome() {
        this.navigateTo(this.homePageName, false);
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
        } else if (status === STATUS_CRITERIA_REQUIRED) {
            this.navigateTo(this.previousPageName, true);
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

    reduceError(error) {
        if (error && error.body && error.body.message) {
            return error.body.message;
        }
        return (error && error.message) || "An unexpected error occurred. Please try again.";
    }
}
