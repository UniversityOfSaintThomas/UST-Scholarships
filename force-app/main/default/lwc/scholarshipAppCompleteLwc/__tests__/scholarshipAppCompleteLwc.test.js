import {createElement} from "lwc";
import ScholarshipAppCompleteLwc from "c/scholarshipAppCompleteLwc";
import {CurrentPageReference} from "lightning/navigation";
import getPageData from "@salesforce/apex/ScholarshipAppCompleteLwcController.getPageData";

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

jest.mock("@salesforce/apex/ScholarshipAppCompleteLwcController.getPageData", () => ({default: jest.fn()}), {virtual: true});

const {__mockNavigate: mockNavigate} = require("lightning/navigation");

const SID = "Scholarship-ABC";

const completeData = (overrides = {}) => ({
    status: "COMPLETE",
    scholarshipName: "Test Scholarship",
    reviewAwardProcessDescriptionHtml: "<p>We will review your application.</p>",
    recommenders: [],
    ...overrides
});

const recommender = (recommenderNumber, overrides = {}) => ({
    recommenderNumber,
    name: `Recommender ${recommenderNumber}`,
    email: `rec${recommenderNumber}@example.com`,
    requestedOn: "05/03/2026",
    status: "Unopened",
    ...overrides
});

// eslint-disable-next-line @lwc/lwc/no-async-operation
const flushPromises = () => new Promise((resolve) => setTimeout(resolve, 0));

async function mountWith(data, sid = SID) {
    getPageData.mockResolvedValue(data);
    const element = createElement("c-scholarship-app-complete-lwc", {is: ScholarshipAppCompleteLwc});
    document.body.appendChild(element);
    CurrentPageReference.emit({state: sid ? {sid} : {}});
    await flushPromises();
    return element;
}

const q = (element, selector) => element.shadowRoot.querySelector(selector);
const qAll = (element, selector) => Array.from(element.shadowRoot.querySelectorAll(selector));

describe("c-scholarship-app-complete-lwc", () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    describe("the confirmation", () => {
        it("asks Apex about the sid in the URL", async () => {
            await mountWith(completeData());

            expect(getPageData).toHaveBeenCalledWith({sid: SID});
            expect(mockNavigate).not.toHaveBeenCalled();
        });

        it("shows the scholarship name and that the application was received", async () => {
            const element = await mountWith(completeData());

            expect(q(element, '[data-id="heading"]').textContent).toBe("Test Scholarship");
            expect(q(element, '[data-id="confirmation"]').textContent).toBe(
                "Your application for the Test Scholarship has been received and is being reviewed."
            );
        });

        it("shows 'What happens next?' with the scholarship's description", async () => {
            const element = await mountWith(completeData());

            expect(q(element, '[data-id="what-next"]').textContent).toBe("What happens next?");
            expect(q(element, "lightning-formatted-rich-text")).not.toBeNull();
            expect(q(element, "lightning-formatted-rich-text").value).toBe("<p>We will review your application.</p>");
        });

        it("still shows the heading, as the VF page did, when there is no description", async () => {
            const element = await mountWith(completeData({reviewAwardProcessDescriptionHtml: null}));

            expect(q(element, '[data-id="what-next"]')).not.toBeNull();
            expect(q(element, "lightning-formatted-rich-text")).toBeNull();
        });

        it("shows an error when loading fails", async () => {
            getPageData.mockRejectedValue({body: {message: "Boom"}});
            const element = createElement("c-scholarship-app-complete-lwc", {is: ScholarshipAppCompleteLwc});
            document.body.appendChild(element);
            CurrentPageReference.emit({state: {sid: SID}});
            await flushPromises();

            expect(q(element, '[data-id="load-error"]').textContent).toContain("Boom");
            expect(q(element, '[data-id="heading"]')).toBeNull();
        });
    });

    describe("recommender request status", () => {
        it("shows no recommender section when no request was sent", async () => {
            const element = await mountWith(completeData({recommenders: []}));

            expect(q(element, '[data-id="recommenders"]')).toBeNull();
        });

        it("shows no recommender section when the list is missing", async () => {
            const element = await mountWith(completeData({recommenders: undefined}));

            expect(q(element, '[data-id="recommenders"]')).toBeNull();
        });

        it("shows one recommender, with a singular heading", async () => {
            const element = await mountWith(completeData({recommenders: [recommender(1)]}));

            expect(q(element, '[data-id="recommenders-heading"]').textContent).toBe("Recommendation request sent to:");
            expect(qAll(element, '[data-id="recommender"]')).toHaveLength(1);
            expect(q(element, '[data-id="recommender-summary"]').textContent).toBe("Recommender 1 (rec1@example.com) on 05/03/2026");
            expect(q(element, '[data-id="recommender-status"]').textContent).toBe("Status: Unopened");
        });

        it("shows both recommenders, with a plural heading, in order", async () => {
            const element = await mountWith(completeData({
                recommenders: [recommender(1), recommender(2, {requestedOn: "05/04/2026", status: "Opened"})]
            }));

            expect(q(element, '[data-id="recommenders-heading"]').textContent).toBe("Recommendation requests sent to:");
            expect(qAll(element, '[data-id="recommender-summary"]').map((span) => span.textContent)).toEqual([
                "Recommender 1 (rec1@example.com) on 05/03/2026",
                "Recommender 2 (rec2@example.com) on 05/04/2026"
            ]);
            expect(qAll(element, '[data-id="recommender-status"]').map((span) => span.textContent)).toEqual([
                "Status: Unopened",
                "Status: Opened"
            ]);
        });

        it("shows only the second recommender when only that request was sent", async () => {
            const element = await mountWith(completeData({recommenders: [recommender(2)]}));

            expect(qAll(element, '[data-id="recommender"]')).toHaveLength(1);
            expect(q(element, '[data-id="recommender-summary"]').textContent).toContain("Recommender 2");
            expect(q(element, '[data-id="recommenders-heading"]').textContent).toBe("Recommendation request sent to:");
        });
    });

    describe("anyone whose application is not submitted", () => {
        it.each([
            ["OPEN", "Scholarship_Application_Page_Lwc_2__c", {sid: SID}],
            ["CLOSED", "Scholarship_Closed_Lwc__c", {sid: SID}],
            ["NOT_YET_OPEN", "Scholarship_Closed_Lwc__c", {sid: SID}],
            ["NOT_FOUND", "Scholarship_Home_Lwc__c", {}]
        ])("is sent on when the status is %s", async (status, pageName, state) => {
            const element = await mountWith({status, scholarshipName: "Test Scholarship", recommenders: []});

            expect(mockNavigate).toHaveBeenCalledWith(
                {type: "comm__namedPage", attributes: {name: pageName}, state},
                true
            );
            expect(q(element, '[data-id="confirmation"]')).toBeNull();
        });

        it("uses page names configured on the component", async () => {
            getPageData.mockResolvedValue({status: "OPEN", recommenders: []});
            const element = createElement("c-scholarship-app-complete-lwc", {is: ScholarshipAppCompleteLwc});
            element.applicationPageName = "Custom_Application__c";
            document.body.appendChild(element);
            CurrentPageReference.emit({state: {sid: SID}});
            await flushPromises();

            expect(mockNavigate.mock.calls[0][0].attributes.name).toBe("Custom_Application__c");
        });
    });

    describe("without a sid in the URL", () => {
        it("explains instead of redirecting (e.g. Experience Builder), and does not call Apex", async () => {
            const element = await mountWith(completeData(), null);

            expect(getPageData).not.toHaveBeenCalled();
            expect(mockNavigate).not.toHaveBeenCalled();
            expect(q(element, '[data-id="missing-sid"]')).not.toBeNull();
            expect(q(element, '[data-id="heading"]')).toBeNull();
        });

        it("offers a button to the scholarship list", async () => {
            const element = await mountWith(completeData(), null);

            q(element, 'lightning-button[data-id="go-home"]').click();

            expect(mockNavigate).toHaveBeenCalledWith(
                {type: "comm__namedPage", attributes: {name: "Scholarship_Home_Lwc__c"}, state: {}},
                true
            );
        });
    });
});
