import {api, LightningElement, wire} from "lwc";
import {CurrentPageReference, NavigationMixin} from "lightning/navigation";
import {ShowToastEvent} from "lightning/platformShowToastEvent";
import getPageData from "@salesforce/apex/ScholarshipAppPage2LwcController.getPageData";
import saveAnswers from "@salesforce/apex/ScholarshipAppPage2LwcController.saveAnswers";
import attachEssayFile from "@salesforce/apex/ScholarshipAppPage2LwcController.attachEssayFile";
import deleteEssayFile from "@salesforce/apex/ScholarshipAppPage2LwcController.deleteEssayFile";
import {countWords} from "./wordCount";
import {allowedExtensionsText, DELIVERY_INPUT, DELIVERY_OPTIONS, DELIVERY_UPLOAD, initialDelivery} from "./essayHelpers";

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
 * currently covering the application questions and the essays. The scholarship is identified by the "sid"
 * URL parameter. The applicant is never chosen by the client: the Apex controller derives it from the
 * running user. Essay files are stored by lightning-file-upload on the applicant record, then confirmed
 * with the server, which checks the file before marking the essay as uploaded.
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
    essays = [];
    applicantId;
    allowedExtensions = [];
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

    get deliveryOptions() {
        return DELIVERY_OPTIONS;
    }

    get uploadHelpText() {
        return `Please upload a ${allowedExtensionsText(this.allowedExtensions)} file.`;
    }

    get displayEssays() {
        return this.essays.map((essay) => ({
            ...essay,
            label: `Essay ${essay.essayNumber}`,
            // Only essays that allow uploads offer the choice; the others are always typed.
            showDeliveryChoice: essay.allowUpload,
            showUpload: essay.allowUpload && essay.delivery === DELIVERY_UPLOAD,
            showInput: !essay.allowUpload || essay.delivery === DELIVERY_INPUT
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
            this.applicantId = data.applicantId;
            this.allowedExtensions = data.allowedFileExtensions || [];
            this.essays = (data.essays || []).map((essay) => ({
                ...essay,
                delivery: initialDelivery(essay),
                uploadError: "",
                isBusy: false
            }));
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

    handleDeliveryChange(event) {
        this.updateEssay(Number(event.target.dataset.essay), {delivery: event.detail.value, uploadError: ""});
        this.saveConfirmed = false;
    }

    handleEssayChange(event) {
        this.updateEssay(Number(event.target.dataset.essay), {answerHtml: event.detail.value});
        this.saveConfirmed = false;
    }

    /**
     * lightning-file-upload has already stored the file on the applicant record. The server checks it (owner,
     * link, file type, one file per essay) before the essay counts as uploaded, and removes it if it fails.
     */
    async handleUploadFinished(event) {
        const essayNumber = Number(event.target.dataset.essay);
        const files = event.detail.files || [];
        if (files.length === 0) {
            return;
        }

        this.updateEssay(essayNumber, {isBusy: true, uploadError: ""});
        try {
            const result = await attachEssayFile({
                sid: this.sid,
                essayNumber,
                contentDocumentId: files[0].documentId
            });

            if (result.success) {
                this.updateEssay(essayNumber, {
                    uploaded: true,
                    uploadedFilename: result.uploadedFilename,
                    delivery: DELIVERY_UPLOAD
                });
                this.saveConfirmed = false;
            } else if (result.status !== STATUS_OPEN) {
                this.redirectForStatus(result.status);
            } else {
                this.updateEssay(essayNumber, {uploadError: result.message});
            }
        } catch (error) {
            this.updateEssay(essayNumber, {uploadError: this.reduceError(error)});
        } finally {
            this.updateEssay(essayNumber, {isBusy: false});
        }
    }

    /**
     * Counterpart of DeleteEssay1/2 in the VF page ("Delete and re-upload").
     */
    async handleDeleteEssayFile(event) {
        const essayNumber = Number(event.target.dataset.essay);

        this.updateEssay(essayNumber, {isBusy: true, uploadError: ""});
        try {
            const result = await deleteEssayFile({sid: this.sid, essayNumber});

            if (result.success) {
                this.updateEssay(essayNumber, {uploaded: false, uploadedFilename: ""});
                this.saveConfirmed = false;
            } else if (result.status !== STATUS_OPEN) {
                this.redirectForStatus(result.status);
            } else {
                this.updateEssay(essayNumber, {uploadError: result.message});
            }
        } catch (error) {
            this.updateEssay(essayNumber, {uploadError: this.reduceError(error)});
        } finally {
            this.updateEssay(essayNumber, {isBusy: false});
        }
    }

    updateEssay(essayNumber, changes) {
        this.essays = this.essays.map((essay) => {
            return essay.essayNumber === essayNumber ? {...essay, ...changes} : essay;
        });
    }

    async handleSaveFinishLater() {
        this.saveError = "";
        this.saveConfirmed = false;
        this.isSaving = true;
        let navigating = false;
        try {
            // Sent as maps of question/essay number to answer; see ScholarshipAppPage2LwcController.saveAnswers().
            const answers = {};
            this.questions.forEach((question) => {
                answers[String(question.questionNumber)] = question.answer;
            });
            // Only essays whose text editor is showing are sent, so an essay typed earlier is never
            // overwritten while the applicant is using the upload option instead.
            const essayAnswers = {};
            this.essays.forEach((essay) => {
                if (!essay.allowUpload || essay.delivery === DELIVERY_INPUT) {
                    essayAnswers[String(essay.essayNumber)] = essay.answerHtml;
                }
            });
            const result = await saveAnswers({sid: this.sid, answers, essayAnswers});

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
