import {createElement} from "lwc";
import ScholarshipAppPage2Lwc from "c/scholarshipAppPage2Lwc";
import {CurrentPageReference} from "lightning/navigation";
import getPageData from "@salesforce/apex/ScholarshipAppPage2LwcController.getPageData";
import saveAnswers from "@salesforce/apex/ScholarshipAppPage2LwcController.saveAnswers";
import attachEssayFile from "@salesforce/apex/ScholarshipAppPage2LwcController.attachEssayFile";
import deleteEssayFile from "@salesforce/apex/ScholarshipAppPage2LwcController.deleteEssayFile";
import requestRecommendation from "@salesforce/apex/ScholarshipAppPage2LwcController.requestRecommendation";
import submitApplication from "@salesforce/apex/ScholarshipAppPage2LwcController.submitApplication";

// Replace the navigation stub with one that records Navigate calls.
jest.mock("lightning/navigation", () => {
    const Navigate = Symbol("Navigate");
    const mockNavigate = jest.fn();
    const NavigationMixin = (Base) => class extends Base {
        [Navigate](...args) {
            mockNavigate(...args);
        }
    };
    NavigationMixin.Navigate = Navigate;
    const {createTestWireAdapter} = require("@salesforce/wire-service-jest-util");
    return {
        NavigationMixin,
        CurrentPageReference: createTestWireAdapter(jest.fn()),
        __mockNavigate: mockNavigate
    };
}, {virtual: true});

jest.mock("@salesforce/apex/ScholarshipAppPage2LwcController.getPageData", () => ({default: jest.fn()}), {virtual: true});
jest.mock("@salesforce/apex/ScholarshipAppPage2LwcController.saveAnswers", () => ({default: jest.fn()}), {virtual: true});
jest.mock("@salesforce/apex/ScholarshipAppPage2LwcController.attachEssayFile", () => ({default: jest.fn()}), {virtual: true});
jest.mock("@salesforce/apex/ScholarshipAppPage2LwcController.deleteEssayFile", () => ({default: jest.fn()}), {virtual: true});
jest.mock("@salesforce/apex/ScholarshipAppPage2LwcController.requestRecommendation", () => ({default: jest.fn()}), {virtual: true});
jest.mock("@salesforce/apex/ScholarshipAppPage2LwcController.submitApplication", () => ({default: jest.fn()}), {virtual: true});

const {__mockNavigate: mockNavigate} = require("lightning/navigation");

const SID = "Scholarship-ABC";

const question = (questionNumber, overrides = {}) => ({
    questionNumber,
    promptHtml: `<p>Question ${questionNumber}</p>`,
    answer: null,
    maxLength: 7000,
    ...overrides
});

const openData = (overrides = {}) => ({
    status: "OPEN",
    scholarshipName: "Test Scholarship",
    applicantId: "a1Ehs000000EHgyEAG",
    allowedFileExtensions: [".pdf", ".doc", ".docx", ".txt", ".rtf"],
    questions: [question(1), question(3)],
    essays: [],
    recommenders: [],
    ...overrides
});

// eslint-disable-next-line @lwc/lwc/no-async-operation
const flushPromises = () => new Promise((resolve) => setTimeout(resolve, 0));

async function mountWith(data, sid = SID) {
    getPageData.mockResolvedValue(data);
    const element = createElement("c-scholarship-app-page2-lwc", {is: ScholarshipAppPage2Lwc});
    document.body.appendChild(element);
    CurrentPageReference.emit({state: sid ? {sid} : {}});
    await flushPromises();
    return element;
}

const q = (element, selector) => element.shadowRoot.querySelector(selector);
const qAll = (element, selector) => Array.from(element.shadowRoot.querySelectorAll(selector));

function typeAnswer(element, questionNumber, value) {
    q(element, `lightning-textarea[data-question="${questionNumber}"]`).dispatchEvent(new CustomEvent("change", {detail: {value}}));
}

async function clickButton(element, id) {
    q(element, `lightning-button[data-id="${id}"]`).click();
    await flushPromises();
}

async function clickRecommenderRequest(element, recommenderNumber) {
    q(element, `lightning-button[data-id="recommender-request"][data-recommender="${recommenderNumber}"]`).click();
    await flushPromises();
}

describe("c-scholarship-app-page2-lwc", () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    describe("loading and conditional questions", () => {
        it("loads the scholarship for the sid in the URL and shows its name", async () => {
            const element = await mountWith(openData());

            expect(getPageData).toHaveBeenCalledWith({sid: SID});
            expect(q(element, '[data-id="heading"]').textContent).toBe("Test Scholarship");
            expect(mockNavigate).not.toHaveBeenCalled();
        });

        it("renders only the questions the scholarship has", async () => {
            const element = await mountWith(openData({questions: [question(1), question(3)]}));

            expect(qAll(element, '[data-id="question"]')).toHaveLength(2);
            expect(q(element, 'lightning-textarea[data-question="1"]')).not.toBeNull();
            expect(q(element, 'lightning-textarea[data-question="2"]')).toBeNull();
            expect(q(element, 'lightning-textarea[data-question="3"]')).not.toBeNull();
            expect(q(element, 'lightning-textarea[data-question="4"]')).toBeNull();
        });

        it("renders all four questions when all are configured", async () => {
            const element = await mountWith(openData({questions: [question(1), question(2), question(3), question(4)]}));

            expect(qAll(element, '[data-id="question"]')).toHaveLength(4);
        });

        it("renders no question boxes when the scholarship has none", async () => {
            const element = await mountWith(openData({questions: []}));

            expect(qAll(element, '[data-id="question"]')).toHaveLength(0);
            expect(q(element, 'lightning-button[data-id="save-finish-later"]')).not.toBeNull();
        });

        it("restores saved answers and limits each answer to the field length", async () => {
            const element = await mountWith(openData({questions: [question(1, {answer: "Saved answer"})]}));

            const textarea = q(element, 'lightning-textarea[data-question="1"]');
            expect(textarea.value).toBe("Saved answer");
            expect(textarea.maxLength).toBe(7000);
        });

        it("shows an error when loading fails", async () => {
            getPageData.mockRejectedValue({body: {message: "Boom"}});
            const element = createElement("c-scholarship-app-page2-lwc", {is: ScholarshipAppPage2Lwc});
            document.body.appendChild(element);
            CurrentPageReference.emit({state: {sid: SID}});
            await flushPromises();

            expect(q(element, '[data-id="load-error"]').textContent).toContain("Boom");
            expect(q(element, '[data-id="heading"]')).toBeNull();
        });
    });

    describe("word count", () => {
        it("shows the word count of each saved answer", async () => {
            const element = await mountWith(openData({questions: [question(1, {answer: "one two three"}), question(3)]}));

            expect(qAll(element, '[data-id="word-count"]').map((div) => div.textContent)).toEqual(["Word count: 3", "Word count: 0"]);
        });

        it("updates the word count while typing, counting any whitespace", async () => {
            const element = await mountWith(openData());

            typeAnswer(element, 1, "  one\ntwo   three\tfour ");
            await flushPromises();

            expect(qAll(element, '[data-id="word-count"]')[0].textContent).toBe("Word count: 4");
        });
    });

    describe("redirects (sanity check)", () => {
        it.each([
            ["COMPLETE", "Scholarship_Application_Complete_Lwc__c", {sid: SID}],
            ["CLOSED", "Scholarship_Closed_Lwc__c", {sid: SID}],
            ["NOT_YET_OPEN", "Scholarship_Closed_Lwc__c", {sid: SID}],
            ["CRITERIA_REQUIRED", "Scholarship_Application_Page_Lwc_1__c", {sid: SID}],
            ["NOT_FOUND", "Scholarship_Home_Lwc__c", {}]
        ])("navigates away when the status is %s", async (status, pageName, state) => {
            await mountWith({status, questions: []});

            expect(mockNavigate).toHaveBeenCalledWith(
                {type: "comm__namedPage", attributes: {name: pageName}, state},
                true
            );
        });

        it("explains instead of redirecting when there is no sid in the URL (e.g. Experience Builder)", async () => {
            const element = await mountWith(openData(), null);

            expect(getPageData).not.toHaveBeenCalled();
            expect(mockNavigate).not.toHaveBeenCalled();
            expect(q(element, '[data-id="missing-sid"]')).not.toBeNull();
            expect(q(element, '[data-id="heading"]')).toBeNull();
        });

        it("offers a button to the scholarship list when there is no sid", async () => {
            const element = await mountWith(openData(), null);

            await clickButton(element, "go-home");

            expect(mockNavigate).toHaveBeenCalledWith(
                {type: "comm__namedPage", attributes: {name: "Scholarship_Home_Lwc__c"}, state: {}},
                true
            );
        });

        it("uses page names configured on the component", async () => {
            getPageData.mockResolvedValue({status: "CLOSED", questions: []});
            const element = createElement("c-scholarship-app-page2-lwc", {is: ScholarshipAppPage2Lwc});
            element.closedPageName = "Custom_Closed__c";
            document.body.appendChild(element);
            CurrentPageReference.emit({state: {sid: SID}});
            await flushPromises();

            expect(mockNavigate.mock.calls[0][0].attributes.name).toBe("Custom_Closed__c");
        });
    });

    describe("Previous Page", () => {
        it("goes back to Page 1 with the sid preserved and does not save", async () => {
            const element = await mountWith(openData());

            await clickButton(element, "previous-page");

            expect(saveAnswers).not.toHaveBeenCalled();
            expect(mockNavigate).toHaveBeenCalledWith(
                {type: "comm__namedPage", attributes: {name: "Scholarship_Application_Page_Lwc_1__c"}, state: {sid: SID}},
                true
            );
        });
    });

    describe("Save & Finish Later", () => {
        it("saves every question's answer by number and shows the saved confirmation", async () => {
            saveAnswers.mockResolvedValue({success: true, status: "OPEN"});
            const element = await mountWith(openData());
            typeAnswer(element, 1, "First answer");

            await clickButton(element, "save-finish-later");

            expect(saveAnswers).toHaveBeenCalledWith({
                sid: SID,
                answers: {1: "First answer", 3: null},
                essayAnswers: {},
                recommenders: {}
            });
            const confirmation = q(element, '[data-id="save-confirmation"]');
            expect(confirmation.textContent).toContain("Saved:");
            expect(confirmation.textContent).toContain("Your scholarship application has been saved and you can return to it at any time.");
            expect(confirmation.textContent).toContain("Your scholarship will not be submitted until you click “Save & Submit” below.");
            expect(mockNavigate).not.toHaveBeenCalled();
        });

        it("also shows a success toast with the saved message", async () => {
            saveAnswers.mockResolvedValue({success: true, status: "OPEN"});
            const element = await mountWith(openData());
            const toastHandler = jest.fn();
            element.addEventListener("lightning__showtoast", toastHandler);

            await clickButton(element, "save-finish-later");

            expect(toastHandler).toHaveBeenCalledTimes(1);
            const toast = toastHandler.mock.calls[0][0].detail;
            expect(toast.variant).toBe("success");
            expect(toast.mode).toBe("sticky");
            expect(toast.title).toBe("Saved");
            expect(toast.message).toBe(
                "Your scholarship application has been saved and you can return to it at any time. " +
                "Your scholarship will not be submitted until you click “Save & Submit” below."
            );
        });

        it("does not show a success toast when the save is rejected", async () => {
            saveAnswers.mockResolvedValue({success: false, status: "OPEN", message: "nope"});
            const element = await mountWith(openData());
            const toastHandler = jest.fn();
            element.addEventListener("lightning__showtoast", toastHandler);

            await clickButton(element, "save-finish-later");

            expect(toastHandler).not.toHaveBeenCalled();
        });

        it("does not require any answer to save", async () => {
            saveAnswers.mockResolvedValue({success: true, status: "OPEN"});
            const element = await mountWith(openData());

            await clickButton(element, "save-finish-later");

            expect(saveAnswers).toHaveBeenCalledTimes(1);
            expect(q(element, '[data-id="save-error"]')).toBeNull();
        });

        it("keeps the entered answers after saving", async () => {
            saveAnswers.mockResolvedValue({success: true, status: "OPEN"});
            const element = await mountWith(openData());
            typeAnswer(element, 3, "Third answer");

            await clickButton(element, "save-finish-later");

            expect(q(element, 'lightning-textarea[data-question="3"]').value).toBe("Third answer");
        });

        it("hides the saved confirmation once the applicant edits an answer again", async () => {
            saveAnswers.mockResolvedValue({success: true, status: "OPEN"});
            const element = await mountWith(openData());
            await clickButton(element, "save-finish-later");
            expect(q(element, '[data-id="save-confirmation"]')).not.toBeNull();

            typeAnswer(element, 1, "More text");
            await flushPromises();

            expect(q(element, '[data-id="save-confirmation"]')).toBeNull();
        });

        it("shows the server message and no confirmation when the save is rejected", async () => {
            saveAnswers.mockResolvedValue({success: false, status: "OPEN", message: "The answer to question 3 is too long"});
            const element = await mountWith(openData());

            await clickButton(element, "save-finish-later");

            expect(q(element, '[data-id="save-error"]').textContent).toContain("too long");
            expect(q(element, '[data-id="save-confirmation"]')).toBeNull();
            expect(mockNavigate).not.toHaveBeenCalled();
        });

        it("redirects when the scholarship closed between loading and saving", async () => {
            saveAnswers.mockResolvedValue({success: false, status: "CLOSED", message: "closed"});
            const element = await mountWith(openData());

            await clickButton(element, "save-finish-later");

            expect(mockNavigate.mock.calls[0][0].attributes.name).toBe("Scholarship_Closed_Lwc__c");
        });

        it("sends the applicant back to Page 1 when the criteria are no longer confirmed", async () => {
            saveAnswers.mockResolvedValue({success: false, status: "CRITERIA_REQUIRED", message: "confirm first"});
            const element = await mountWith(openData());

            await clickButton(element, "save-finish-later");

            expect(mockNavigate.mock.calls[0][0].attributes.name).toBe("Scholarship_Application_Page_Lwc_1__c");
        });

        it("shows an error when the Apex call throws", async () => {
            saveAnswers.mockRejectedValue({body: {message: "Server exploded"}});
            const element = await mountWith(openData());

            await clickButton(element, "save-finish-later");

            expect(q(element, '[data-id="save-error"]').textContent).toContain("Server exploded");
            expect(mockNavigate).not.toHaveBeenCalled();
        });
    });

    describe("essays", () => {
        const DOCUMENT_ID = "069000000000001AAA";

        const essay = (essayNumber, overrides = {}) => ({
            essayNumber,
            promptHtml: `<p>Essay ${essayNumber} prompt</p>`,
            allowUpload: true,
            answerHtml: null,
            uploaded: false,
            uploadedFilename: null,
            ...overrides
        });

        const essayData = (essays, overrides = {}) => openData({questions: [], essays, ...overrides});

        const combobox = (element, essayNumber) => q(element, `lightning-combobox[data-essay="${essayNumber}"]`);
        const fileUpload = (element, essayNumber) => q(element, `lightning-file-upload[data-essay="${essayNumber}"]`);
        const richText = (element, essayNumber) => q(element, `lightning-input-rich-text[data-essay="${essayNumber}"]`);
        const deleteButton = (element, essayNumber) => q(element, `lightning-button[data-id="essay-delete"][data-essay="${essayNumber}"]`);

        function chooseDelivery(element, essayNumber, value) {
            combobox(element, essayNumber).dispatchEvent(new CustomEvent("change", {detail: {value}}));
        }

        function typeEssay(element, essayNumber, value) {
            richText(element, essayNumber).dispatchEvent(new CustomEvent("change", {detail: {value}}));
        }

        async function finishUpload(element, essayNumber, files = [{documentId: DOCUMENT_ID, name: "essay.pdf"}]) {
            fileUpload(element, essayNumber).dispatchEvent(new CustomEvent("uploadfinished", {detail: {files}}));
            await flushPromises();
        }

        describe("which controls show", () => {
            it("shows each essay's prompt", async () => {
                const element = await mountWith(essayData([essay(1), essay(2)]));

                expect(qAll(element, '[data-id="essay"]')).toHaveLength(2);
            });

            it("offers the upload or type choice only for essays that allow uploads", async () => {
                const element = await mountWith(essayData([essay(1, {allowUpload: true}), essay(2, {allowUpload: false})]));

                expect(combobox(element, 1)).not.toBeNull();
                expect(combobox(element, 2)).toBeNull();
                expect(combobox(element, 1).options.map((option) => option.value)).toEqual(["upload", "input"]);
            });

            it("always shows the text editor for an essay that cannot be uploaded", async () => {
                const element = await mountWith(essayData([essay(1, {allowUpload: false, answerHtml: "<p>Typed</p>"})]));

                expect(richText(element, 1)).not.toBeNull();
                expect(richText(element, 1).value).toBe("<p>Typed</p>");
                expect(fileUpload(element, 1)).toBeNull();
            });

            it("shows neither the editor nor the uploader until a choice is made", async () => {
                const element = await mountWith(essayData([essay(1)]));

                expect(richText(element, 1)).toBeNull();
                expect(fileUpload(element, 1)).toBeNull();
            });

            it("starts on the text editor when text was already typed", async () => {
                const element = await mountWith(essayData([essay(1, {answerHtml: "<p>Draft</p>"})]));

                expect(combobox(element, 1).value).toBe("input");
                expect(richText(element, 1).value).toBe("<p>Draft</p>");
                expect(fileUpload(element, 1)).toBeNull();
            });

            it("starts on the upload option with the filename when a file was already uploaded", async () => {
                const element = await mountWith(essayData([essay(1, {uploaded: true, uploadedFilename: "my essay.pdf"})]));

                expect(combobox(element, 1).value).toBe("upload");
                expect(q(element, '[data-id="essay-uploaded"]').textContent).toContain("my essay.pdf");
                expect(q(element, '[data-id="essay-uploaded"]').textContent).toContain("has been uploaded to your application.");
                expect(deleteButton(element, 1)).not.toBeNull();
                expect(fileUpload(element, 1)).toBeNull();
            });

            it("switches between the uploader and the editor with the choice", async () => {
                const element = await mountWith(essayData([essay(1)]));

                chooseDelivery(element, 1, "upload");
                await flushPromises();
                expect(fileUpload(element, 1)).not.toBeNull();
                expect(richText(element, 1)).toBeNull();

                chooseDelivery(element, 1, "input");
                await flushPromises();
                expect(fileUpload(element, 1)).toBeNull();
                expect(richText(element, 1)).not.toBeNull();
            });

            it("keeps typed text when the applicant switches to upload and back", async () => {
                const element = await mountWith(essayData([essay(1, {answerHtml: "<p>Draft</p>"})]));
                typeEssay(element, 1, "<p>Longer draft</p>");

                chooseDelivery(element, 1, "upload");
                await flushPromises();
                chooseDelivery(element, 1, "input");
                await flushPromises();

                expect(richText(element, 1).value).toBe("<p>Longer draft</p>");
            });

            it("points the uploader at the applicant record and limits the file types", async () => {
                const element = await mountWith(essayData([essay(1)]));
                chooseDelivery(element, 1, "upload");
                await flushPromises();

                expect(fileUpload(element, 1).recordId).toBe("a1Ehs000000EHgyEAG");
                expect(fileUpload(element, 1).accept).toEqual([".pdf", ".doc", ".docx", ".txt", ".rtf"]);
                expect(q(element, '[data-id="essay-upload-help"]').textContent).toBe("Please upload a .pdf, .doc, .docx, .txt, or .rtf file.");
            });
        });

        describe("uploading a file", () => {
            async function mountOnUpload() {
                const element = await mountWith(essayData([essay(1)]));
                chooseDelivery(element, 1, "upload");
                await flushPromises();
                return element;
            }

            it("confirms the uploaded file with the server by its document id only", async () => {
                attachEssayFile.mockResolvedValue({success: true, status: "OPEN", uploaded: true, uploadedFilename: "essay.pdf"});
                const element = await mountOnUpload();

                await finishUpload(element, 1);

                expect(attachEssayFile).toHaveBeenCalledWith({sid: SID, essayNumber: 1, contentDocumentId: DOCUMENT_ID});
            });

            it("shows the original filename and a delete button once the server accepts the file", async () => {
                attachEssayFile.mockResolvedValue({success: true, status: "OPEN", uploaded: true, uploadedFilename: "essay.pdf"});
                const element = await mountOnUpload();

                await finishUpload(element, 1);

                expect(q(element, '[data-id="essay-uploaded"]').textContent).toContain("essay.pdf");
                expect(deleteButton(element, 1)).not.toBeNull();
                expect(fileUpload(element, 1)).toBeNull();
                expect(q(element, '[data-id="essay-upload-error"]')).toBeNull();
            });

            it("shows an inline error and keeps the uploader when the server rejects the file", async () => {
                attachEssayFile.mockResolvedValue({
                    success: false,
                    status: "OPEN",
                    message: "Invalid file type. Please upload a .pdf, .doc, .docx, .txt, or .rtf file."
                });
                const element = await mountOnUpload();

                await finishUpload(element, 1, [{documentId: DOCUMENT_ID, name: "setup.exe"}]);

                expect(q(element, '[data-id="essay-upload-error"]').textContent).toBe(
                    "Invalid file type. Please upload a .pdf, .doc, .docx, .txt, or .rtf file."
                );
                expect(fileUpload(element, 1)).not.toBeNull();
                expect(q(element, '[data-id="essay-uploaded"]')).toBeNull();
                expect(mockNavigate).not.toHaveBeenCalled();
            });

            it("clears the error when the applicant tries again", async () => {
                attachEssayFile.mockResolvedValueOnce({success: false, status: "OPEN", message: "Bad file"});
                attachEssayFile.mockResolvedValueOnce({success: true, status: "OPEN", uploaded: true, uploadedFilename: "good.pdf"});
                const element = await mountOnUpload();
                await finishUpload(element, 1);
                expect(q(element, '[data-id="essay-upload-error"]')).not.toBeNull();

                await finishUpload(element, 1);

                expect(q(element, '[data-id="essay-upload-error"]')).toBeNull();
                expect(q(element, '[data-id="essay-uploaded"]').textContent).toContain("good.pdf");
            });

            it("redirects when the scholarship closed during the upload", async () => {
                attachEssayFile.mockResolvedValue({success: false, status: "CLOSED", message: "closed"});
                const element = await mountOnUpload();

                await finishUpload(element, 1);

                expect(mockNavigate.mock.calls[0][0].attributes.name).toBe("Scholarship_Closed_Lwc__c");
            });

            it("shows an error when the Apex call throws", async () => {
                attachEssayFile.mockRejectedValue({body: {message: "Server exploded"}});
                const element = await mountOnUpload();

                await finishUpload(element, 1);

                expect(q(element, '[data-id="essay-upload-error"]').textContent).toContain("Server exploded");
            });

            it("ignores an upload event that carries no files", async () => {
                const element = await mountOnUpload();

                await finishUpload(element, 1, []);

                expect(attachEssayFile).not.toHaveBeenCalled();
            });

            it("hides the saved confirmation once a file is uploaded", async () => {
                saveAnswers.mockResolvedValue({success: true, status: "OPEN"});
                attachEssayFile.mockResolvedValue({success: true, status: "OPEN", uploaded: true, uploadedFilename: "essay.pdf"});
                const element = await mountOnUpload();
                await clickButton(element, "save-finish-later");
                expect(q(element, '[data-id="save-confirmation"]')).not.toBeNull();

                await finishUpload(element, 1);

                expect(q(element, '[data-id="save-confirmation"]')).toBeNull();
            });
        });

        describe("deleting a file", () => {
            const uploadedEssay = () => essay(1, {uploaded: true, uploadedFilename: "essay.pdf"});

            it("deletes through the server and offers the uploader again", async () => {
                deleteEssayFile.mockResolvedValue({success: true, status: "OPEN", uploaded: false});
                const element = await mountWith(essayData([uploadedEssay()]));

                deleteButton(element, 1).click();
                await flushPromises();

                expect(deleteEssayFile).toHaveBeenCalledWith({sid: SID, essayNumber: 1});
                expect(q(element, '[data-id="essay-uploaded"]')).toBeNull();
                expect(fileUpload(element, 1)).not.toBeNull();
            });

            it("shows an inline error and keeps the file when the delete fails", async () => {
                deleteEssayFile.mockResolvedValue({success: false, status: "OPEN", message: "The essay file could not be deleted."});
                const element = await mountWith(essayData([uploadedEssay()]));

                deleteButton(element, 1).click();
                await flushPromises();

                expect(q(element, '[data-id="essay-upload-error"]').textContent).toContain("could not be deleted");
                expect(q(element, '[data-id="essay-uploaded"]')).not.toBeNull();
            });

            it("only changes the essay whose delete button was used", async () => {
                deleteEssayFile.mockResolvedValue({success: true, status: "OPEN", uploaded: false});
                const element = await mountWith(essayData([uploadedEssay(), essay(2, {uploaded: true, uploadedFilename: "second.pdf"})]));

                deleteButton(element, 1).click();
                await flushPromises();

                expect(fileUpload(element, 1)).not.toBeNull();
                expect(fileUpload(element, 2)).toBeNull();
                expect(q(element, '[data-id="essay-uploaded"]').textContent).toContain("second.pdf");
            });

            it("redirects when the scholarship closed", async () => {
                deleteEssayFile.mockResolvedValue({success: false, status: "CLOSED", message: "closed"});
                const element = await mountWith(essayData([uploadedEssay()]));

                deleteButton(element, 1).click();
                await flushPromises();

                expect(mockNavigate.mock.calls[0][0].attributes.name).toBe("Scholarship_Closed_Lwc__c");
            });

            it("shows an error when the Apex call throws", async () => {
                deleteEssayFile.mockRejectedValue({body: {message: "Server exploded"}});
                const element = await mountWith(essayData([uploadedEssay()]));

                deleteButton(element, 1).click();
                await flushPromises();

                expect(q(element, '[data-id="essay-upload-error"]').textContent).toContain("Server exploded");
            });
        });

        describe("Save & Finish Later with essays", () => {
            it("sends the typed essays together with the question answers", async () => {
                saveAnswers.mockResolvedValue({success: true, status: "OPEN"});
                const element = await mountWith(openData({
                    questions: [question(1)],
                    essays: [essay(1, {allowUpload: false}), essay(2, {allowUpload: false})]
                }));
                typeAnswer(element, 1, "Short answer");
                typeEssay(element, 1, "<p>First essay</p>");
                typeEssay(element, 2, "<p>Second essay</p>");

                await clickButton(element, "save-finish-later");

                expect(saveAnswers).toHaveBeenCalledWith({
                    sid: SID,
                    answers: {1: "Short answer"},
                    essayAnswers: {1: "<p>First essay</p>", 2: "<p>Second essay</p>"},
                    recommenders: {}
                });
            });

            it("leaves out an essay the applicant is giving as an upload, or has not chosen yet", async () => {
                saveAnswers.mockResolvedValue({success: true, status: "OPEN"});
                const element = await mountWith(essayData([
                    essay(1, {answerHtml: "<p>Typed before choosing upload</p>"}),
                    essay(2)
                ]));
                chooseDelivery(element, 1, "upload");
                await flushPromises();

                await clickButton(element, "save-finish-later");

                expect(saveAnswers).toHaveBeenCalledWith({sid: SID, answers: {}, essayAnswers: {}, recommenders: {}});
            });

            it("includes a typed essay for an essay that allows upload when typing was chosen", async () => {
                saveAnswers.mockResolvedValue({success: true, status: "OPEN"});
                const element = await mountWith(essayData([essay(1)]));
                chooseDelivery(element, 1, "input");
                await flushPromises();
                typeEssay(element, 1, "<p>Pasted essay</p>");

                await clickButton(element, "save-finish-later");

                expect(saveAnswers).toHaveBeenCalledWith({sid: SID, answers: {}, essayAnswers: {1: "<p>Pasted essay</p>"}, recommenders: {}});
            });

            it("hides the saved confirmation once an essay is edited", async () => {
                saveAnswers.mockResolvedValue({success: true, status: "OPEN"});
                const element = await mountWith(essayData([essay(1, {allowUpload: false})]));
                await clickButton(element, "save-finish-later");
                expect(q(element, '[data-id="save-confirmation"]')).not.toBeNull();

                typeEssay(element, 1, "<p>More</p>");
                await flushPromises();

                expect(q(element, '[data-id="save-confirmation"]')).toBeNull();
            });
        });
    });

    describe("recommenders", () => {
        const recommender = (recommenderNumber, overrides = {}) => ({
            recommenderNumber,
            required: false,
            descriptionHtml: `<p>Recommender ${recommenderNumber} description</p>`,
            name: null,
            email: null,
            requestedOn: null,
            ...overrides
        });

        const recommenderData = (recommenders) => openData({questions: [], recommenders});

        const nameInput = (element, number) => q(element, `lightning-input[data-recommender="${number}"][data-field="name"]`);
        const emailInput = (element, number) => q(element, `lightning-input[data-recommender="${number}"][data-field="email"]`);
        const requestButton = (element, number) => q(element, `lightning-button[data-id="recommender-request"][data-recommender="${number}"]`);

        function typeRecommender(element, number, field, value) {
            q(element, `lightning-input[data-recommender="${number}"][data-field="${field}"]`)
                .dispatchEvent(new CustomEvent("change", {detail: {value}}));
        }

        async function fillIn(element, number, name = "Dr One", email = "one@example.com") {
            typeRecommender(element, number, "name", name);
            typeRecommender(element, number, "email", email);
            await flushPromises();
        }

        describe("which controls show", () => {
            it("shows nothing when the scholarship asks for no recommenders", async () => {
                const element = await mountWith(recommenderData([]));

                expect(qAll(element, '[data-id="recommender"]')).toHaveLength(0);
            });

            it("numbers the headings and marks optional recommenders", async () => {
                const element = await mountWith(recommenderData([recommender(1, {required: true}), recommender(2)]));

                expect(qAll(element, '[data-id="recommender-heading"]').map((heading) => heading.textContent))
                    .toEqual(["Recommendation 1", "Recommendation 2 (Optional)"]);
            });

            it("shows only the recommenders the scholarship asks for", async () => {
                const element = await mountWith(recommenderData([recommender(2, {required: true})]));

                expect(nameInput(element, 1)).toBeNull();
                expect(nameInput(element, 2)).not.toBeNull();
                expect(q(element, '[data-id="recommender-heading"]').textContent).toBe("Recommendation 2");
            });

            it("shows the description, and skips it when there is none", async () => {
                const element = await mountWith(recommenderData([recommender(1), recommender(2, {descriptionHtml: null})]));

                const sections = qAll(element, '[data-id="recommender"]');
                expect(sections[0].querySelector("lightning-formatted-rich-text")).not.toBeNull();
                expect(sections[1].querySelector("lightning-formatted-rich-text")).toBeNull();
            });

            it("fills in the saved name and email", async () => {
                const element = await mountWith(recommenderData([recommender(1, {name: "Dr One", email: "one@example.com"})]));

                expect(nameInput(element, 1).value).toBe("Dr One");
                expect(emailInput(element, 1).value).toBe("one@example.com");
                expect(nameInput(element, 1).disabled).toBeFalsy();
                expect(emailInput(element, 1).disabled).toBeFalsy();
            });

            it("limits the name to the field length", async () => {
                const element = await mountWith(recommenderData([recommender(1)]));

                expect(String(nameInput(element, 1).maxLength)).toBe("80");
            });
        });

        describe("Request Now is only enabled for a name and a valid email", () => {
            it("is disabled while the fields are empty", async () => {
                const element = await mountWith(recommenderData([recommender(1)]));

                expect(requestButton(element, 1).disabled).toBe(true);
            });

            it("stays disabled with a name but no email, or an invalid email", async () => {
                const element = await mountWith(recommenderData([recommender(1)]));

                typeRecommender(element, 1, "name", "Dr One");
                await flushPromises();
                expect(requestButton(element, 1).disabled).toBe(true);

                typeRecommender(element, 1, "email", "not an email");
                await flushPromises();
                expect(requestButton(element, 1).disabled).toBe(true);
            });

            it("stays disabled with a valid email but a blank name", async () => {
                const element = await mountWith(recommenderData([recommender(1)]));

                await fillIn(element, 1, "   ", "one@example.com");

                expect(requestButton(element, 1).disabled).toBe(true);
            });

            it("is enabled once both are valid, and is checked per recommender", async () => {
                const element = await mountWith(recommenderData([recommender(1), recommender(2)]));

                await fillIn(element, 1);

                expect(requestButton(element, 1).disabled).toBe(false);
                expect(requestButton(element, 2).disabled).toBe(true);
            });

            it("is already enabled when valid values were saved earlier", async () => {
                const element = await mountWith(recommenderData([recommender(1, {name: "Dr One", email: "one@example.com"})]));

                expect(requestButton(element, 1).disabled).toBe(false);
            });
        });

        describe("after the request was sent", () => {
            const sent = () => recommender(1, {name: "Dr One", email: "one@example.com", requestedOn: "May 3, 2026 02:15 PM"});

            it("shows when it was sent and removes the Request Now button", async () => {
                const element = await mountWith(recommenderData([sent()]));

                expect(q(element, '[data-id="recommender-sent"]').textContent).toBe("Recommendation request sent on May 3, 2026 02:15 PM.");
                expect(requestButton(element, 1)).toBeNull();
            });

            it("disables the name and email", async () => {
                const element = await mountWith(recommenderData([sent()]));

                expect(nameInput(element, 1).disabled).toBe(true);
                expect(emailInput(element, 1).disabled).toBe(true);
            });

            it("leaves the other recommender editable", async () => {
                const element = await mountWith(recommenderData([sent(), recommender(2)]));

                expect(nameInput(element, 2).disabled).toBeFalsy();
                expect(requestButton(element, 2)).not.toBeNull();
            });
        });

        describe("clicking Request Now", () => {
            it("sends the typed name and email for that recommender", async () => {
                requestRecommendation.mockResolvedValue({success: true, status: "OPEN", requestedOn: "May 3, 2026 02:15 PM"});
                const element = await mountWith(recommenderData([recommender(1), recommender(2)]));
                await fillIn(element, 2, "Prof Two", "two@example.com");

                await clickRecommenderRequest(element, 2);

                expect(requestRecommendation).toHaveBeenCalledTimes(1);
                expect(requestRecommendation).toHaveBeenCalledWith({
                    sid: SID,
                    recommenderNumber: 2,
                    name: "Prof Two",
                    email: "two@example.com"
                });
            });

            it("locks the recommender and shows the sent date when the server sends the request", async () => {
                requestRecommendation.mockResolvedValue({success: true, status: "OPEN", requestedOn: "May 3, 2026 02:15 PM"});
                const element = await mountWith(recommenderData([recommender(1)]));
                await fillIn(element, 1);

                await clickRecommenderRequest(element, 1);

                expect(q(element, '[data-id="recommender-sent"]').textContent).toBe("Recommendation request sent on May 3, 2026 02:15 PM.");
                expect(requestButton(element, 1)).toBeNull();
                expect(nameInput(element, 1).disabled).toBe(true);
                expect(emailInput(element, 1).disabled).toBe(true);
                expect(q(element, '[data-id="recommender-error"]')).toBeNull();
            });

            it("shows a success toast naming the recipient", async () => {
                requestRecommendation.mockResolvedValue({success: true, status: "OPEN", requestedOn: "May 3, 2026 02:15 PM"});
                const element = await mountWith(recommenderData([recommender(1)]));
                const toastHandler = jest.fn();
                element.addEventListener("lightning__showtoast", toastHandler);
                await fillIn(element, 1, "Dr One", " one@example.com ");

                await clickRecommenderRequest(element, 1);

                expect(toastHandler).toHaveBeenCalledTimes(1);
                const toast = toastHandler.mock.calls[0][0].detail;
                expect(toast.variant).toBe("success");
                expect(toast.title).toBe("Recommendation request sent");
                expect(toast.message).toBe("A recommendation request was sent to one@example.com.");
            });

            it("does not save the rest of the application", async () => {
                requestRecommendation.mockResolvedValue({success: true, status: "OPEN", requestedOn: "May 3, 2026 02:15 PM"});
                const element = await mountWith(recommenderData([recommender(1)]));
                await fillIn(element, 1);

                await clickRecommenderRequest(element, 1);

                expect(saveAnswers).not.toHaveBeenCalled();
            });

            it("shows the server's message and keeps the form usable when the email was not sent", async () => {
                requestRecommendation.mockResolvedValue({success: false, status: "OPEN", message: "Recommendation saved. No request email sent."});
                const element = await mountWith(recommenderData([recommender(1)]));
                const toastHandler = jest.fn();
                element.addEventListener("lightning__showtoast", toastHandler);
                await fillIn(element, 1);

                await clickRecommenderRequest(element, 1);

                expect(q(element, '[data-id="recommender-error"]').textContent).toBe("Recommendation saved. No request email sent.");
                expect(requestButton(element, 1)).not.toBeNull();
                expect(requestButton(element, 1).disabled).toBe(false);
                expect(nameInput(element, 1).disabled).toBeFalsy();
                expect(q(element, '[data-id="recommender-sent"]')).toBeNull();
                expect(toastHandler).not.toHaveBeenCalled();
            });

            it("clears the error once the applicant edits the recommender", async () => {
                requestRecommendation.mockResolvedValue({success: false, status: "OPEN", message: "Some failure"});
                const element = await mountWith(recommenderData([recommender(1)]));
                await fillIn(element, 1);
                await clickRecommenderRequest(element, 1);
                expect(q(element, '[data-id="recommender-error"]')).not.toBeNull();

                typeRecommender(element, 1, "email", "other@example.com");
                await flushPromises();

                expect(q(element, '[data-id="recommender-error"]')).toBeNull();
            });

            it("locks the recommender when the server says a request was already sent", async () => {
                requestRecommendation.mockResolvedValue({
                    success: false,
                    status: "OPEN",
                    message: "A request has already been sent for this recommendation.",
                    requestedOn: "May 1, 2026 09:00 AM"
                });
                const element = await mountWith(recommenderData([recommender(1)]));
                await fillIn(element, 1);

                await clickRecommenderRequest(element, 1);

                expect(q(element, '[data-id="recommender-sent"]').textContent).toBe("Recommendation request sent on May 1, 2026 09:00 AM.");
                expect(requestButton(element, 1)).toBeNull();
            });

            it("redirects when the scholarship closed", async () => {
                requestRecommendation.mockResolvedValue({success: false, status: "CLOSED", message: "closed"});
                const element = await mountWith(recommenderData([recommender(1)]));
                await fillIn(element, 1);

                await clickRecommenderRequest(element, 1);

                expect(mockNavigate.mock.calls[0][0].attributes.name).toBe("Scholarship_Closed_Lwc__c");
            });

            it("shows an error when the Apex call throws", async () => {
                requestRecommendation.mockRejectedValue({body: {message: "Server exploded"}});
                const element = await mountWith(recommenderData([recommender(1)]));
                await fillIn(element, 1);

                await clickRecommenderRequest(element, 1);

                expect(q(element, '[data-id="recommender-error"]').textContent).toContain("Server exploded");
                expect(requestButton(element, 1)).not.toBeNull();
            });

            it("disables the button while the request is in progress so it cannot be sent twice", async () => {
                let finish;
                requestRecommendation.mockReturnValue(new Promise((resolve) => {
                    finish = resolve;
                }));
                const element = await mountWith(recommenderData([recommender(1)]));
                await fillIn(element, 1);

                requestButton(element, 1).click();
                await flushPromises();
                expect(requestButton(element, 1).disabled).toBe(true);

                finish({success: true, status: "OPEN", requestedOn: "May 3, 2026 02:15 PM"});
                await flushPromises();
                expect(requestRecommendation).toHaveBeenCalledTimes(1);
                expect(q(element, '[data-id="recommender-sent"]')).not.toBeNull();
            });
        });

        describe("Save & Finish Later with recommenders", () => {
            it("sends the typed names and emails of recommenders not yet requested", async () => {
                saveAnswers.mockResolvedValue({success: true, status: "OPEN"});
                const element = await mountWith(recommenderData([recommender(1), recommender(2)]));
                await fillIn(element, 1, "Dr One", "one@example.com");
                typeRecommender(element, 2, "name", "Prof Two");
                await flushPromises();

                await clickButton(element, "save-finish-later");

                expect(saveAnswers).toHaveBeenCalledWith({
                    sid: SID,
                    answers: {},
                    essayAnswers: {},
                    recommenders: {name1: "Dr One", email1: "one@example.com", name2: "Prof Two", email2: ""}
                });
            });

            it("leaves out a recommender whose request was already sent", async () => {
                saveAnswers.mockResolvedValue({success: true, status: "OPEN"});
                const element = await mountWith(recommenderData([
                    recommender(1, {name: "Dr One", email: "one@example.com", requestedOn: "May 3, 2026 02:15 PM"}),
                    recommender(2)
                ]));
                await fillIn(element, 2, "Prof Two", "two@example.com");

                await clickButton(element, "save-finish-later");

                expect(saveAnswers).toHaveBeenCalledWith({
                    sid: SID,
                    answers: {},
                    essayAnswers: {},
                    recommenders: {name2: "Prof Two", email2: "two@example.com"}
                });
            });

            it("does not send a recommendation request", async () => {
                saveAnswers.mockResolvedValue({success: true, status: "OPEN"});
                const element = await mountWith(recommenderData([recommender(1)]));
                await fillIn(element, 1);

                await clickButton(element, "save-finish-later");

                expect(requestRecommendation).not.toHaveBeenCalled();
            });

            it("shows the server message when a recommender's value is rejected", async () => {
                saveAnswers.mockResolvedValue({success: false, status: "OPEN", message: "Please enter a valid email address for recommendation 1."});
                const element = await mountWith(recommenderData([recommender(1)]));

                await clickButton(element, "save-finish-later");

                expect(q(element, '[data-id="save-error"]').textContent).toContain("recommendation 1");
            });

            it("hides the saved confirmation once a recommender field is edited", async () => {
                saveAnswers.mockResolvedValue({success: true, status: "OPEN"});
                const element = await mountWith(recommenderData([recommender(1)]));
                await clickButton(element, "save-finish-later");
                expect(q(element, '[data-id="save-confirmation"]')).not.toBeNull();

                typeRecommender(element, 1, "name", "Dr One");
                await flushPromises();

                expect(q(element, '[data-id="save-confirmation"]')).toBeNull();
            });
        });
    });

    describe("Save & Submit", () => {
        const COMPLETE_PAGE = {type: "comm__namedPage", attributes: {name: "Scholarship_Application_Complete_Lwc__c"}, state: {sid: SID}};

        const submitButton = (element) => q(element, 'lightning-button[data-id="save-submit"]');
        const signatureInput = (element) => q(element, 'lightning-input[data-id="signature"]');
        const richTextField = (element, number) => q(element, `lightning-input-rich-text[data-essay="${number}"]`);

        async function clickSubmit(element) {
            submitButton(element).click();
            await flushPromises();
        }

        function typeAnswerFor(element, number, value) {
            q(element, `lightning-textarea[data-question="${number}"]`).dispatchEvent(new CustomEvent("change", {detail: {value}}));
        }

        function typeInitials(element, value) {
            signatureInput(element).dispatchEvent(new CustomEvent("change", {detail: {value}}));
        }

        function typeRecommenderField(element, number, field, value) {
            q(element, `lightning-input[data-recommender="${number}"][data-field="${field}"]`)
                .dispatchEvent(new CustomEvent("change", {detail: {value}}));
        }

        function chooseDeliveryFor(element, number, value) {
            q(element, `lightning-combobox[data-essay="${number}"]`).dispatchEvent(new CustomEvent("change", {detail: {value}}));
        }

        const uploadableEssay = (overrides = {}) => ({
            essayNumber: 1,
            promptHtml: "<p>Essay 1</p>",
            allowUpload: true,
            answerHtml: null,
            uploaded: false,
            uploadedFilename: null,
            ...overrides
        });

        const requiredRecommender = (overrides = {}) => ({
            recommenderNumber: 1,
            required: true,
            descriptionHtml: null,
            name: null,
            email: null,
            requestedOn: null,
            ...overrides
        });

        const emptyApplication = () => openData({questions: []});

        beforeEach(() => {
            submitApplication.mockResolvedValue({success: true, status: "OPEN", submitEmailFailed: false, invalidFields: []});
        });

        describe("the controls", () => {
            it("shows the Save & Submit button and the note about recommendation requests", async () => {
                const element = await mountWith(emptyApplication());

                expect(submitButton(element).label).toBe("Save & Submit");
                expect(q(element, '[data-id="submit-note"]').textContent).toBe("Save & Submit will send any unsent recommendation requests.");
            });

            it("shows the completion statement and the initials only when the scholarship has a statement", async () => {
                const withStatement = await mountWith(openData({questions: [], completionStatementHtml: "<p>I agree</p>", signature: "AB"}));
                expect(q(withStatement, '[data-id="completion"]')).not.toBeNull();
                expect(q(withStatement, '[data-id="completion"] h2').textContent).toBe("Digital Consent & Submit");
                expect(signatureInput(withStatement).label).toBe("By initialing here you agree to the above statement.");
                expect(signatureInput(withStatement).value).toBe("AB");
                expect(String(signatureInput(withStatement).maxLength)).toBe("30");
                document.body.removeChild(withStatement);

                const without = await mountWith(emptyApplication());
                expect(q(without, '[data-id="completion"]')).toBeNull();
            });
        });

        describe("Save & Finish Later and the initials", () => {
            it("sends the initials when there is a completion statement", async () => {
                saveAnswers.mockResolvedValue({success: true, status: "OPEN"});
                const element = await mountWith(openData({questions: [], completionStatementHtml: "<p>I agree</p>"}));
                typeInitials(element, "AB");
                await flushPromises();

                await clickButton(element, "save-finish-later");

                expect(saveAnswers).toHaveBeenCalledWith({sid: SID, answers: {}, essayAnswers: {}, recommenders: {}, signature: "AB"});
            });

            it("does not send initials when there is no completion statement", async () => {
                saveAnswers.mockResolvedValue({success: true, status: "OPEN"});
                const element = await mountWith(emptyApplication());

                await clickButton(element, "save-finish-later");

                expect(Object.keys(saveAnswers.mock.calls[0][0])).not.toContain("signature");
            });

            it("does not ask for anything to be submitted", async () => {
                saveAnswers.mockResolvedValue({success: true, status: "OPEN"});
                const element = await mountWith(emptyApplication());

                await clickButton(element, "save-finish-later");

                expect(submitApplication).not.toHaveBeenCalled();
            });
        });

        describe("when the application is complete", () => {
            it("submits and goes to the Complete page with the sid", async () => {
                const element = await mountWith(emptyApplication());

                await clickSubmit(element);

                expect(submitApplication).toHaveBeenCalledTimes(1);
                expect(mockNavigate).toHaveBeenCalledWith(COMPLETE_PAGE, true);
            });

            it("sends everything the application holds, as Save & Finish Later does", async () => {
                const element = await mountWith(openData({
                    questions: [question(1)],
                    essays: [uploadableEssay({uploaded: true, uploadedFilename: "essay.pdf"}), uploadableEssay({essayNumber: 2, allowUpload: false})],
                    recommenders: [requiredRecommender({name: "Dr One", email: "one@example.com"})],
                    completionStatementHtml: "<p>I agree</p>"
                }));
                typeAnswerFor(element, 1, "My answer");
                richTextField(element, 2).dispatchEvent(new CustomEvent("change", {detail: {value: "<p>Typed essay</p>"}}));
                typeInitials(element, "AB");
                await flushPromises();

                await clickSubmit(element);

                expect(submitApplication).toHaveBeenCalledWith({
                    sid: SID,
                    answers: {1: "My answer"},
                    essayAnswers: {2: "<p>Typed essay</p>"},
                    recommenders: {name1: "Dr One", email1: "one@example.com"},
                    signature: "AB"
                });
                expect(mockNavigate).toHaveBeenCalledWith(COMPLETE_PAGE, true);
            });

            it("leaves out a recommender whose request was already sent", async () => {
                const element = await mountWith(openData({
                    questions: [],
                    recommenders: [requiredRecommender({name: "Dr One", email: "one@example.com", requestedOn: "May 3, 2026 02:15 PM"})]
                }));

                await clickSubmit(element);

                expect(submitApplication.mock.calls[0][0].recommenders).toEqual({});
                expect(mockNavigate).toHaveBeenCalledWith(COMPLETE_PAGE, true);
            });

            it("shows no toast when everything worked", async () => {
                const element = await mountWith(emptyApplication());
                const toastHandler = jest.fn();
                element.addEventListener("lightning__showtoast", toastHandler);

                await clickSubmit(element);

                expect(toastHandler).not.toHaveBeenCalled();
            });

            it("shows a sticky warning toast, and still goes on, when the confirmation email was not sent", async () => {
                submitApplication.mockResolvedValue({success: true, status: "OPEN", submitEmailFailed: true, invalidFields: []});
                const element = await mountWith(emptyApplication());
                const toastHandler = jest.fn();
                element.addEventListener("lightning__showtoast", toastHandler);

                await clickSubmit(element);

                expect(toastHandler).toHaveBeenCalledTimes(1);
                const toast = toastHandler.mock.calls[0][0].detail;
                expect(toast.variant).toBe("warning");
                expect(toast.mode).toBe("sticky");
                expect(toast.message).toBe("Your application was submitted, but the confirmation email could not be sent.");
                expect(mockNavigate).toHaveBeenCalledWith(COMPLETE_PAGE, true);
            });

            it("keeps the button disabled while submitting, so it cannot be sent twice", async () => {
                let finish;
                submitApplication.mockReturnValue(new Promise((resolve) => {
                    finish = resolve;
                }));
                const element = await mountWith(emptyApplication());

                submitButton(element).click();
                await flushPromises();
                expect(submitButton(element).disabled).toBe(true);
                submitButton(element).click();
                await flushPromises();

                finish({success: true, status: "OPEN", invalidFields: []});
                await flushPromises();
                expect(submitApplication).toHaveBeenCalledTimes(1);
            });
        });

        describe("when something is missing, found in the browser", () => {
            it("does not call the server, and shows what is missing", async () => {
                const element = await mountWith(openData({questions: [question(1), question(3)]}));
                typeAnswerFor(element, 3, "Answered");
                await flushPromises();

                await clickSubmit(element);

                expect(submitApplication).not.toHaveBeenCalled();
                expect(mockNavigate).not.toHaveBeenCalled();
                const errors = qAll(element, '[data-id="question-error"]');
                expect(errors).toHaveLength(1);
                expect(errors[0].textContent).toBe("This field is required.");
                expect(q(element, '[data-id="submit-summary"]').textContent).toContain("Please complete the required fields shown above before submitting.");
            });

            it("asks for the essay option, then for what the chosen option needs", async () => {
                const element = await mountWith(openData({questions: [], essays: [uploadableEssay()]}));

                await clickSubmit(element);
                expect(q(element, '[data-id="essay-error"]').textContent).toBe("Please choose how you will enter your answer.");

                chooseDeliveryFor(element, 1, "upload");
                await flushPromises();
                expect(q(element, '[data-id="essay-error"]')).toBeNull();
                await clickSubmit(element);
                expect(q(element, '[data-id="essay-error"]').textContent).toBe("Please upload your essay file.");

                chooseDeliveryFor(element, 1, "input");
                await flushPromises();
                await clickSubmit(element);
                expect(q(element, '[data-id="essay-error"]').textContent).toBe("Please enter your essay.");
                expect(submitApplication).not.toHaveBeenCalled();
            });

            it("does not require an essay that can only be typed", async () => {
                const element = await mountWith(openData({questions: [], essays: [uploadableEssay({allowUpload: false})]}));

                await clickSubmit(element);

                expect(q(element, '[data-id="essay-error"]')).toBeNull();
                expect(submitApplication).toHaveBeenCalledTimes(1);
            });

            it("asks for a required recommender's name and a valid email, but not an optional one's", async () => {
                const element = await mountWith(openData({
                    questions: [],
                    recommenders: [requiredRecommender(), requiredRecommender({recommenderNumber: 2, required: false})]
                }));

                await clickSubmit(element);

                expect(qAll(element, '[data-id="recommender-name-error"]')).toHaveLength(1);
                expect(qAll(element, '[data-id="recommender-email-error"]')).toHaveLength(1);
                expect(q(element, '[data-id="recommender-name-error"]').textContent).toBe("This field is required.");

                typeRecommenderField(element, 1, "name", "Dr One");
                typeRecommenderField(element, 1, "email", "not an email");
                await flushPromises();
                await clickSubmit(element);
                expect(q(element, '[data-id="recommender-name-error"]')).toBeNull();
                expect(q(element, '[data-id="recommender-email-error"]').textContent).toBe("Please enter a valid email address.");
                expect(submitApplication).not.toHaveBeenCalled();
            });

            it("asks for the initials when there is a completion statement", async () => {
                const element = await mountWith(openData({questions: [], completionStatementHtml: "<p>I agree</p>"}));

                await clickSubmit(element);

                expect(q(element, '[data-id="signature-error"]').textContent).toBe("This field is required.");
                expect(submitApplication).not.toHaveBeenCalled();
            });

            it("clears each problem as soon as that field is fixed, and the summary with the last one", async () => {
                const element = await mountWith(openData({
                    questions: [question(1)],
                    recommenders: [requiredRecommender()],
                    completionStatementHtml: "<p>I agree</p>"
                }));
                await clickSubmit(element);
                expect(q(element, '[data-id="submit-summary"]')).not.toBeNull();

                typeAnswerFor(element, 1, "Answer");
                typeRecommenderField(element, 1, "name", "Dr One");
                typeRecommenderField(element, 1, "email", "one@example.com");
                await flushPromises();
                expect(q(element, '[data-id="question-error"]')).toBeNull();
                expect(q(element, '[data-id="recommender-name-error"]')).toBeNull();
                expect(q(element, '[data-id="recommender-email-error"]')).toBeNull();
                expect(q(element, '[data-id="signature-error"]')).not.toBeNull();
                expect(q(element, '[data-id="submit-summary"]')).not.toBeNull();

                typeInitials(element, "AB");
                await flushPromises();
                expect(q(element, '[data-id="signature-error"]')).toBeNull();
                expect(q(element, '[data-id="submit-summary"]')).toBeNull();
            });

            it("submits once everything is filled in", async () => {
                const element = await mountWith(openData({questions: [question(1)], completionStatementHtml: "<p>I agree</p>"}));
                await clickSubmit(element);
                expect(submitApplication).not.toHaveBeenCalled();

                typeAnswerFor(element, 1, "Answer");
                typeInitials(element, "AB");
                await flushPromises();
                await clickSubmit(element);

                expect(submitApplication).toHaveBeenCalledTimes(1);
                expect(mockNavigate).toHaveBeenCalledWith(COMPLETE_PAGE, true);
            });

            it("drops the old problems when Save & Finish Later is used", async () => {
                saveAnswers.mockResolvedValue({success: true, status: "OPEN"});
                const element = await mountWith(openData({questions: [question(1)]}));
                await clickSubmit(element);
                expect(q(element, '[data-id="question-error"]')).not.toBeNull();

                await clickButton(element, "save-finish-later");

                expect(q(element, '[data-id="question-error"]')).toBeNull();
                expect(q(element, '[data-id="submit-summary"]')).toBeNull();
            });
        });

        describe("when the server says no", () => {
            it("shows the fields the server named, with its message, and stays on the page", async () => {
                submitApplication.mockResolvedValue({
                    success: false,
                    status: "OPEN",
                    message: "Please answer question 1. Essay 1 needs an uploaded file or a typed answer.",
                    invalidFields: ["question:1", "essay:1"]
                });
                // The browser check passes here (the essay option chosen has what it needs), so only the server objects.
                const element = await mountWith(openData({questions: [question(1, {answer: "Looks answered"})], essays: [uploadableEssay({answerHtml: "<p>Text</p>"})]}));

                await clickSubmit(element);

                expect(submitApplication).toHaveBeenCalledTimes(1);
                expect(q(element, '[data-id="question-error"]').textContent).toBe("This field is required.");
                expect(q(element, '[data-id="essay-error"]').textContent).toBe("Please upload your essay file or enter your essay.");
                expect(q(element, '[data-id="save-error"]').textContent).toContain("Please answer question 1.");
                expect(mockNavigate).not.toHaveBeenCalled();
                expect(submitButton(element).disabled).toBeFalsy();
            });

            it("shows a message with no field, for example when a recommender request could not be sent", async () => {
                submitApplication.mockResolvedValue({
                    success: false,
                    status: "OPEN",
                    message: "Recommendation saved. No request email sent. Your application has not been submitted.",
                    invalidFields: []
                });
                const element = await mountWith(emptyApplication());

                await clickSubmit(element);

                expect(q(element, '[data-id="save-error"]').textContent).toContain("has not been submitted");
                expect(q(element, '[data-id="submit-summary"]')).toBeNull();
                expect(mockNavigate).not.toHaveBeenCalled();
            });

            it.each([
                ["CLOSED", "Scholarship_Closed_Lwc__c"],
                ["NOT_YET_OPEN", "Scholarship_Closed_Lwc__c"],
                ["COMPLETE", "Scholarship_Application_Complete_Lwc__c"],
                ["CRITERIA_REQUIRED", "Scholarship_Application_Page_Lwc_1__c"]
            ])("redirects when the status is %s", async (status, pageName) => {
                submitApplication.mockResolvedValue({success: false, status, message: "x", invalidFields: []});
                const element = await mountWith(emptyApplication());

                await clickSubmit(element);

                expect(mockNavigate.mock.calls[0][0].attributes.name).toBe(pageName);
            });

            it("shows an error, and lets the applicant try again, when the Apex call throws", async () => {
                submitApplication.mockRejectedValue({body: {message: "Server exploded"}});
                const element = await mountWith(emptyApplication());

                await clickSubmit(element);

                expect(q(element, '[data-id="save-error"]').textContent).toContain("Server exploded");
                expect(mockNavigate).not.toHaveBeenCalled();
                expect(submitButton(element).disabled).toBeFalsy();
            });
        });
    });
});