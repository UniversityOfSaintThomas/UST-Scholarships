import {api, LightningElement, wire} from "lwc";
import {CurrentPageReference, NavigationMixin} from "lightning/navigation";
import {ShowToastEvent} from "lightning/platformShowToastEvent";
import getPageData from "@salesforce/apex/ScholarshipAppPage2LwcController.getPageData";
import saveAnswers from "@salesforce/apex/ScholarshipAppPage2LwcController.saveAnswers";
import attachEssayFile from "@salesforce/apex/ScholarshipAppPage2LwcController.attachEssayFile";
import deleteEssayFile from "@salesforce/apex/ScholarshipAppPage2LwcController.deleteEssayFile";
import requestRecommendation from "@salesforce/apex/ScholarshipAppPage2LwcController.requestRecommendation";
import submitApplication from "@salesforce/apex/ScholarshipAppPage2LwcController.submitApplication";
import {countWords} from "./wordCount";
import {allowedExtensionsText, DELIVERY_INPUT, DELIVERY_OPTIONS, DELIVERY_UPLOAD, initialDelivery} from "./essayHelpers";
import {canRequestRecommendation} from "./recommenderHelpers";
import {errorsFromInvalidFields, validateForSubmit} from "./submitValidation";

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
 * currently covering the application questions, the essays and the recommender requests. The scholarship
 * is identified by the "sid" URL parameter. The applicant is never chosen by the client: the Apex
 * controller derives it from the running user. Essay files are stored by lightning-file-upload on the
 * applicant record, then confirmed with the server, which checks the file before marking the essay as
 * uploaded. A recommender's request email is sent by the server only when "Request Now" is used, or by
 * Save & Submit for any request still pending. Save & Submit checks the application in the browser first
 * (submitValidation.js), and the server checks it again before marking the application complete.
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
    recommenders = [];
    applicantId;
    allowedExtensions = [];
    isLoading = true;
    isSaving = false;
    missingSid = false;
    loadError = "";
    saveError = "";
    saveConfirmed = false;
    signature = "";
    completionStatementHtml = "";
    // Problems found by Save & Submit, keyed like the server names fields, for example "question:1" or "signature".
    submitErrors = {};

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
            wordCountLabel: `Word count: ${countWords(question.answer)}`,
            errorText: this.submitErrors[`question:${question.questionNumber}`]
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
            showInput: !essay.allowUpload || essay.delivery === DELIVERY_INPUT,
            errorText: this.submitErrors[`essay:${essay.essayNumber}`]
        }));
    }

    get displayRecommenders() {
        return this.recommenders.map((recommender) => {
            // Once the request was sent the name and email are locked, as on the VF page.
            const isLocked = !!recommender.requestedOn;
            return {
                ...recommender,
                heading: `Recommendation ${recommender.recommenderNumber}${recommender.required ? "" : " (Optional)"}`,
                hasDescription: !!recommender.descriptionHtml,
                isLocked,
                requestDisabled: recommender.isBusy || !canRequestRecommendation(recommender.name, recommender.email),
                sentText: `Recommendation request sent on ${recommender.requestedOn}.`,
                nameError: this.submitErrors[`recommender:${recommender.recommenderNumber}:name`],
                emailError: this.submitErrors[`recommender:${recommender.recommenderNumber}:email`]
            };
        });
    }

    get hasCompletionStatement() {
        return !!this.completionStatementHtml;
    }

    get signatureError() {
        return this.submitErrors.signature;
    }

    get hasSubmitErrors() {
        return Object.keys(this.submitErrors).length > 0;
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
            this.recommenders = (data.recommenders || []).map((recommender) => ({
                ...recommender,
                name: recommender.name || "",
                email: recommender.email || "",
                requestError: "",
                isBusy: false
            }));
            this.completionStatementHtml = data.completionStatementHtml || "";
            this.signature = data.signature || "";
            this.submitErrors = {};
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
        this.clearSubmitErrors(`question:${questionNumber}`);
        this.saveConfirmed = false;
    }

    handleSignatureChange(event) {
        this.signature = event.detail.value;
        this.clearSubmitErrors("signature");
        this.saveConfirmed = false;
    }

    /**
     * Removes the Save & Submit problems shown for fields the applicant has just changed.
     *
     * @param {...string} keys Field names such as "question:1" or "recommender:1:name".
     */
    clearSubmitErrors(...keys) {
        if (keys.some((key) => this.submitErrors[key])) {
            const remaining = {...this.submitErrors};
            keys.forEach((key) => delete remaining[key]);
            this.submitErrors = remaining;
        }
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
        // Choosing, typing, uploading or deleting changes what Save & Submit would find, so drop its old complaint.
        if ("delivery" in changes || "answerHtml" in changes || "uploaded" in changes) {
            this.clearSubmitErrors(`essay:${essayNumber}`);
        }
    }

    handleRecommenderChange(event) {
        const recommenderNumber = Number(event.target.dataset.recommender);
        this.updateRecommender(recommenderNumber, {[event.target.dataset.field]: event.detail.value, requestError: ""});
        this.saveConfirmed = false;
    }

    /**
     * Counterpart of "Request Now" in the VF page. The server saves the name and email, sends the email and
     * records when it was sent; the inputs lock once it has been sent.
     */
    async handleRequestRecommendation(event) {
        const recommenderNumber = Number(event.target.dataset.recommender);
        const recommender = this.recommenders.find((candidate) => candidate.recommenderNumber === recommenderNumber);
        if (!recommender) {
            return;
        }

        this.updateRecommender(recommenderNumber, {isBusy: true, requestError: ""});
        try {
            const result = await requestRecommendation({
                sid: this.sid,
                recommenderNumber,
                name: recommender.name,
                email: recommender.email
            });

            if (result.success) {
                this.updateRecommender(recommenderNumber, {requestedOn: result.requestedOn});
                this.saveConfirmed = false;
                this.dispatchEvent(new ShowToastEvent({
                    title: "Recommendation request sent",
                    message: `A recommendation request was sent to ${recommender.email.trim()}.`,
                    variant: "success"
                }));
            } else if (result.requestedOn) {
                // A request was already sent (for example from another tab), so lock it.
                this.updateRecommender(recommenderNumber, {requestedOn: result.requestedOn});
            } else if (result.status !== STATUS_OPEN) {
                this.redirectForStatus(result.status);
            } else {
                this.updateRecommender(recommenderNumber, {requestError: result.message});
            }
        } catch (error) {
            this.updateRecommender(recommenderNumber, {requestError: this.reduceError(error)});
        } finally {
            this.updateRecommender(recommenderNumber, {isBusy: false});
        }
    }

    updateRecommender(recommenderNumber, changes) {
        this.recommenders = this.recommenders.map((recommender) => {
            return recommender.recommenderNumber === recommenderNumber ? {...recommender, ...changes} : recommender;
        });
        if ("name" in changes) {
            this.clearSubmitErrors(`recommender:${recommenderNumber}:name`);
        }
        if ("email" in changes) {
            this.clearSubmitErrors(`recommender:${recommenderNumber}:email`);
        }
    }

    /**
     * What Save & Finish Later and Save & Submit send to the server. The parameters are maps of number to text;
     * see ScholarshipAppPage2LwcController.saveAnswers().
     *
     * @returns {{sid: string, answers: Object, essayAnswers: Object, recommenders: Object, signature: (string|undefined)}}
     *          The initials are only included when the scholarship has a completion statement.
     */
    buildSavePayload() {
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
        // Recommenders whose request was already sent are locked, so only the others are sent.
        const recommenders = {};
        this.recommenders.forEach((recommender) => {
            if (!recommender.requestedOn) {
                recommenders[`name${recommender.recommenderNumber}`] = recommender.name;
                recommenders[`email${recommender.recommenderNumber}`] = recommender.email;
            }
        });
        const payload = {sid: this.sid, answers, essayAnswers, recommenders};
        if (this.hasCompletionStatement) {
            payload.signature = this.signature;
        }
        return payload;
    }

    /**
     * Counterpart of "Save & Submit" (SaveComplete in the VF controller). The application is checked here first,
     * as the VF page's script did, and again on the server, which then sends any recommender requests still
     * pending, marks the application complete and sends the confirmation email.
     */
    async handleSubmit() {
        if (this.isSaving) {
            return;
        }
        this.saveError = "";
        this.saveConfirmed = false;

        const validation = validateForSubmit({
            questions: this.questions,
            essays: this.essays,
            recommenders: this.recommenders,
            completionStatementHtml: this.completionStatementHtml,
            signature: this.signature
        });
        this.submitErrors = validation.errors;
        if (!validation.isValid) {
            return;
        }

        this.isSaving = true;
        let navigating = false;
        try {
            const result = await submitApplication(this.buildSavePayload());

            if (result.success) {
                if (result.submitEmailFailed) {
                    this.dispatchEvent(new ShowToastEvent({
                        title: "Confirmation email not sent",
                        message: "Your application was submitted, but the confirmation email could not be sent.",
                        variant: "warning",
                        mode: "sticky"
                    }));
                }
                this.navigateTo(this.completePageName, true);
                navigating = true;
                return;
            }

            if (result.status !== STATUS_OPEN) {
                navigating = this.redirectForStatus(result.status);
                if (navigating) {
                    return;
                }
            }
            // The server found something the browser check did not: show it on the fields it names.
            this.submitErrors = errorsFromInvalidFields(result.invalidFields);
            this.saveError = result.message;
        } catch (error) {
            this.saveError = this.reduceError(error);
        } finally {
            this.isSaving = navigating;
        }
    }

    async handleSaveFinishLater() {
        if (this.isSaving) {
            return;
        }
        this.saveError = "";
        this.saveConfirmed = false;
        this.submitErrors = {};
        this.isSaving = true;
        let navigating = false;
        try {
            const result = await saveAnswers(this.buildSavePayload());

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
