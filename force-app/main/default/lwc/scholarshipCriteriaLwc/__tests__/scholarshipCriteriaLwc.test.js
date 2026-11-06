import {createElement} from "lwc";
import ScholarshipCriteriaLwc from "c/scholarshipCriteriaLwc";
import {CurrentPageReference} from "lightning/navigation";
import getPageData from "@salesforce/apex/ScholarshipAppPage1LwcController.getPageData";
import saveCriteria from "@salesforce/apex/ScholarshipAppPage1LwcController.saveCriteria";

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

jest.mock("@salesforce/apex/ScholarshipAppPage1LwcController.getPageData", () => ({default: jest.fn()}), {virtual: true});
jest.mock("@salesforce/apex/ScholarshipAppPage1LwcController.saveCriteria", () => ({default: jest.fn()}), {virtual: true});

const {__mockNavigate: mockNavigate} = require("lightning/navigation");

const SID = "Scholarship-ABC";

const openData = (overrides = {}) => ({
    status: "OPEN",
    scholarshipName: "Test Scholarship",
    description: "<p>Description</p>",
    criteriaStatement: "<p>Criteria</p>",
    selfReportRequired: false,
    declaredGpa: null,
    declaredActSat: null,
    confirmedCriteria: false,
    configWarnings: [],
    ...overrides
});

// eslint-disable-next-line @lwc/lwc/no-async-operation
const flushPromises = () => new Promise((resolve) => setTimeout(resolve, 0));

async function mountWith(data, sid = SID) {
    getPageData.mockResolvedValue(data);
    const element = createElement("c-scholarship-criteria-lwc", {is: ScholarshipCriteriaLwc});
    document.body.appendChild(element);
    CurrentPageReference.emit({state: sid ? {sid} : {}});
    await flushPromises();
    return element;
}

const q = (element, selector) => element.shadowRoot.querySelector(selector);

function changeField(element, field, detail) {
    q(element, `lightning-input[data-field="${field}"]`).dispatchEvent(new CustomEvent("change", {detail}));
}

async function clickContinue(element) {
    q(element, 'lightning-button[data-id="continue"]').click();
    await flushPromises();
}

describe("c-scholarship-criteria-lwc", () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    describe("loading", () => {
        it("loads the scholarship for the sid in the URL and renders it", async () => {
            const element = await mountWith(openData());

            expect(getPageData).toHaveBeenCalledWith({sid: SID});
            expect(q(element, "h2 strong").textContent).toBe("Test Scholarship");
            expect(q(element, '[data-id="description"]')).not.toBeNull();
            expect(q(element, '[data-id="criteria"]')).not.toBeNull();
            expect(mockNavigate).not.toHaveBeenCalled();
        });

        it("hides description and eligibility sections when they are empty", async () => {
            const element = await mountWith(openData({description: null, criteriaStatement: null}));

            expect(q(element, '[data-id="description"]')).toBeNull();
            expect(q(element, '[data-id="criteria"]')).toBeNull();
        });

        it("shows the self report inputs only when the scholarship requires them", async () => {
            const without = await mountWith(openData());
            expect(q(without, 'lightning-input[data-field="gpa"]')).toBeNull();
            expect(q(without, 'lightning-input[data-field="actSat"]')).toBeNull();
            document.body.removeChild(without);

            const withSelfReport = await mountWith(openData({selfReportRequired: true, declaredGpa: 3.5, declaredActSat: 27}));
            expect(q(withSelfReport, 'lightning-input[data-field="gpa"]').value).toBe("3.5");
            expect(q(withSelfReport, 'lightning-input[data-field="actSat"]').value).toBe("27");
        });

        it("restores a previously confirmed checkbox", async () => {
            const element = await mountWith(openData({confirmedCriteria: true}));
            expect(q(element, 'lightning-input[data-field="confirmed"]').checked).toBe(true);
        });

        it("shows setup warnings to the applicant", async () => {
            const element = await mountWith(openData({configWarnings: ["Org Wide Email Not Set", "Submit Email Template Not Set"]}));

            const items = element.shadowRoot.querySelectorAll('[data-id="config-warnings"] li');
            expect(Array.from(items).map((li) => li.textContent)).toEqual(["Org Wide Email Not Set", "Submit Email Template Not Set"]);
        });

        it("shows an error when loading fails", async () => {
            getPageData.mockRejectedValue({body: {message: "Boom"}});
            const element = createElement("c-scholarship-criteria-lwc", {is: ScholarshipCriteriaLwc});
            document.body.appendChild(element);
            CurrentPageReference.emit({state: {sid: SID}});
            await flushPromises();

            expect(q(element, '[data-id="error-message"]').textContent).toContain("Boom");
        });
    });

    describe("redirects (sanity check)", () => {
        it.each([
            ["COMPLETE", "Scholarship_Application_Complete__c", {sid: SID}],
            ["CLOSED", "Scholarship_Closed__c", {sid: SID}],
            ["NOT_YET_OPEN", "Scholarship_Closed__c", {sid: SID}],
            ["NOT_FOUND", "Scholarship_Home_Lwc__c", {}]
        ])("navigates away when the status is %s", async (status, pageName, state) => {
            await mountWith({status, configWarnings: []});

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
            expect(q(element, 'lightning-input[data-field="confirmed"]')).toBeNull();
        });

        it("offers a button to the scholarship list when there is no sid", async () => {
            const element = await mountWith(openData(), null);

            q(element, 'lightning-button[data-id="go-home"]').click();

            expect(mockNavigate).toHaveBeenCalledWith(
                {type: "comm__namedPage", attributes: {name: "Scholarship_Home_Lwc__c"}, state: {}},
                true
            );
        });

        it("uses page names configured on the component", async () => {
            getPageData.mockResolvedValue({status: "CLOSED", configWarnings: []});
            const element = createElement("c-scholarship-criteria-lwc", {is: ScholarshipCriteriaLwc});
            element.closedPageName = "Custom_Closed__c";
            document.body.appendChild(element);
            CurrentPageReference.emit({state: {sid: SID}});
            await flushPromises();

            expect(mockNavigate.mock.calls[0][0].attributes.name).toBe("Custom_Closed__c");
        });
    });

    describe("Confirm and Continue", () => {
        it("does not call Apex until the criteria checkbox is checked", async () => {
            const element = await mountWith(openData());

            await clickContinue(element);

            expect(saveCriteria).not.toHaveBeenCalled();
            expect(q(element, '[data-id="confirmed-error"]')).not.toBeNull();
            expect(mockNavigate).not.toHaveBeenCalled();
        });

        it("clears the checkbox error once it is checked", async () => {
            const element = await mountWith(openData());
            await clickContinue(element);

            changeField(element, "confirmed", {checked: true});
            await flushPromises();

            expect(q(element, '[data-id="confirmed-error"]')).toBeNull();
        });

        it("saves and navigates to Page 2 with the sid preserved", async () => {
            saveCriteria.mockResolvedValue({success: true, status: "OPEN", startedEmailFailed: false});
            const element = await mountWith(openData());

            changeField(element, "confirmed", {checked: true});
            await clickContinue(element);

            expect(saveCriteria).toHaveBeenCalledWith({sid: SID, declaredGpa: null, declaredActSat: null, confirmed: true});
            expect(mockNavigate).toHaveBeenCalledWith(
                {type: "comm__namedPage", attributes: {name: "Scholarship_Application_Page_2__c"}, state: {sid: SID}},
                true
            );
        });

        it("blocks invalid self reported values and sends valid ones", async () => {
            saveCriteria.mockResolvedValue({success: true, status: "OPEN", startedEmailFailed: false});
            const element = await mountWith(openData({selfReportRequired: true}));
            changeField(element, "confirmed", {checked: true});
            changeField(element, "gpa", {value: "0.5"});
            changeField(element, "actSat", {value: "5"});

            await clickContinue(element);

            expect(saveCriteria).not.toHaveBeenCalled();
            expect(q(element, '[data-id="gpa-error"]')).not.toBeNull();
            expect(q(element, '[data-id="actsat-error"]')).not.toBeNull();

            changeField(element, "gpa", {value: "3.5"});
            changeField(element, "actSat", {value: "27"});
            await clickContinue(element);

            expect(saveCriteria).toHaveBeenCalledWith({sid: SID, declaredGpa: 3.5, declaredActSat: 27, confirmed: true});
            expect(mockNavigate).toHaveBeenCalledTimes(1);
        });

        it("shows the server message and stays on the page when the save is rejected", async () => {
            saveCriteria.mockResolvedValue({success: false, status: "OPEN", message: "Scholarship not saved: boom"});
            const element = await mountWith(openData());
            changeField(element, "confirmed", {checked: true});

            await clickContinue(element);

            expect(q(element, '[data-id="error-message"]').textContent).toContain("Scholarship not saved: boom");
            expect(mockNavigate).not.toHaveBeenCalled();
        });

        it("redirects when the scholarship closed between loading and saving", async () => {
            saveCriteria.mockResolvedValue({success: false, status: "CLOSED", message: "closed"});
            const element = await mountWith(openData());
            changeField(element, "confirmed", {checked: true});

            await clickContinue(element);

            expect(mockNavigate.mock.calls[0][0].attributes.name).toBe("Scholarship_Closed__c");
        });

        it("shows a warning toast but still continues when the started email fails", async () => {
            saveCriteria.mockResolvedValue({success: true, status: "OPEN", startedEmailFailed: true});
            const element = await mountWith(openData());
            const toastHandler = jest.fn();
            element.addEventListener("lightning__showtoast", toastHandler);
            changeField(element, "confirmed", {checked: true});

            await clickContinue(element);

            expect(toastHandler).toHaveBeenCalledTimes(1);
            expect(toastHandler.mock.calls[0][0].detail.variant).toBe("warning");
            expect(mockNavigate).toHaveBeenCalledTimes(1);
        });

        it("shows an error when the Apex call throws", async () => {
            saveCriteria.mockRejectedValue({body: {message: "Server exploded"}});
            const element = await mountWith(openData());
            changeField(element, "confirmed", {checked: true});

            await clickContinue(element);

            expect(q(element, '[data-id="error-message"]').textContent).toContain("Server exploded");
            expect(mockNavigate).not.toHaveBeenCalled();
        });
    });
});
