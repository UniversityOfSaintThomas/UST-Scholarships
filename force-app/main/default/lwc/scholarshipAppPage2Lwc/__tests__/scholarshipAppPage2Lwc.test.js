import {createElement} from "lwc";
import ScholarshipAppPage2Lwc from "c/scholarshipAppPage2Lwc";
import {CurrentPageReference} from "lightning/navigation";
import getPageData from "@salesforce/apex/ScholarshipAppPage2LwcController.getPageData";
import saveAnswers from "@salesforce/apex/ScholarshipAppPage2LwcController.saveAnswers";

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
    questions: [question(1), question(3)],
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
                answers: {1: "First answer", 3: null}
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
});
